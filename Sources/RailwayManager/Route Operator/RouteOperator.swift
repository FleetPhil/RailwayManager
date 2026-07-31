//
//  File.swift
//  
//
//  Created by Phil Diggens on 20/10/2024.
//

import Foundation

enum RouteState: Equatable {
    case dormant
    case active
    case waitingForEvent(LayoutEvent)
    case ending
    case ended
    case error(TrainError)
}

// Actions to execute at a sensor
enum SensorAction: Equatable {
    case stop                           // Stop
    case proceed                        // Carry on
    case requestPathItem(PathItem)      // Request resource
}

// Individual commands that the route manager will execute, based on the route segments
enum RouteAction: CustomStringConvertible {
    // Lock the blocks in the path in the path direction
    case lockPath(Path)
    // Execute action at sensor
    case waitForSensor(Sensor, SensorAction)
    case setDirection(Direction)
    case setSpeed(TrainSpeed)
    case waitForEvent(LayoutEvent)
    case executeSensorAction(Sensor, SensorAction)
    
    case wait(WaitTime)
    
    var description: String {
        switch self {
        case .lockPath(let path):
            "lock \(path.pathItems.first!.fromBlock)-\(path.pathItems.last!.toBlock), \(path.direction)"
        case .waitForSensor(let sensor, let sensorAction):
            "wait for sensor \(sensor, default: "none"), \(sensorAction)"
        case .setDirection(let direction):
            "set direction \(direction)"
        case .setSpeed(let trainSpeed):
            "set speed \(trainSpeed)"
        case .waitForEvent(let layoutEvent):
            "wait for \(layoutEvent)"
        case .wait(let waitTime):
            "wait \(waitTime)"
        case .executeSensorAction(let sensor, let action):
            "execute action \(action) for sensor \(sensor)"
        }
    }
}

struct CurrentItemIndex {
    var segmentIndex: Int
    var pathItemIndex: Int
}

actor RouteOperator {
    let train: Train            // RouteOperator : Train is 1:1 mapping
    var route: Route
    let layout: Layout
    let stateService: LayoutTrackStateService
    let trainController: LayoutTrainController
    
    // Operator State
    private(set) var routeState: RouteState = .dormant {
        didSet {
            if routeState != oldValue {
                log.info("\(rd): Route state now \(routeState)")
            }
        }
    }
    
    // Train state
    private var routeDirection: Direction
    private var lastCommandedTrainSpeed: TrainSpeed = .stop
    
    // The current session and path for this route
    private var currentItemIndex: CurrentItemIndex
    
    var rd: String {
        "R\(train.id)"
    }
    
    init(route: Route,
         train: Train,
         layout: Layout,
         stateService: LayoutTrackStateService,
         trainController: LayoutTrainController,
        ) throws {
        self.route = route
        self.train = train
        self.layout = layout
        self.stateService = stateService
        self.trainController = trainController
        
        guard let routeDirection = route.segments.first?.path.direction else {
            throw TrainError.noTrainDirection(train.id)
        }
        self.routeDirection = routeDirection
        
        currentItemIndex = CurrentItemIndex(segmentIndex: 0, pathItemIndex: 0)
    }
    
    var currentPathItem: PathItem {
        route.segments[currentItemIndex.segmentIndex].path.pathItems[currentItemIndex.pathItemIndex]
    }
    
    var isFirstPathItem: Bool {
        return currentItemIndex.pathItemIndex == -1
    }
    
    func runRoute() async throws {
        guard validForStart(route: route) else {
            throw TrainError.invalidRoute(route.id)
        }
        
        // Request DCC session if necessary
        try await trainController.requestSession(for: train)
        
        // Update the block and train status
        await trainController.setTrainDirection(train, direction: routeDirection)
        try await stateService.setStateForTrain(train, state: .idle)
        try await stateService.setStateForBlock(route.startBlock, newState: .occupied(train))
        
        // Will be incremented at roiute start
        currentItemIndex = CurrentItemIndex(segmentIndex: 0, pathItemIndex: -1)
        
        try await LayoutEventHub.shared.publish(.didOccupyBlock(route.startBlock, train))

        log.info("\(rd): \(route): reset complete")
    }
    
    // Command a change to the train speed and update the status
    func setTrainSpeed(_ train: Train, speed: TrainSpeed, delay: TimeInterval = 0, state: TrainRuntimeState?) async throws {
        try await trainController.commandTrain(train, speed: speed, delay: delay)

        // Update the status
        lastCommandedTrainSpeed = speed
        // State of nil is no change
        if let state {
            await trainController.setTrainState(train, state: state)
        }
    }
    
    // Process the track event and execute route commands if able based on the layout state
    // Exit with updated layout state or nil if no change or nothing processed
    func processEvent(_ event: LayoutEvent) async throws {

        // Get the current path item
        let pathItem = route
            .segments[currentItemIndex.segmentIndex]
            .path
            .pathItems[currentItemIndex.pathItemIndex == -1 ? 0 : currentItemIndex.pathItemIndex]
        
        log.verbose("Process event: \(event), pathItem: \(pathItem)")
        
        // Check for general cases
        switch (routeState, event) {
        case (.dormant, .didStartRoute(let startedTrain)), (.ended, .didStartRoute(let startedTrain)):
            if startedTrain == self.train {
                log.info("\(rd): Starting route for train \(train.id) (\(train.name))")
                
                // Start the train moving and trigger processing for this block being occupied
                try await setTrainSpeed(train, speed: .normal, state: .running(pathItem))
                
                let _ = try await processOccupiedRouteBlock()
            }
            
        case (.ended, .didEndRoute(let endedTrain)):
            if endedTrain == self.train {
                log.verbose("\(rd): Ended route for train \(self.train)")
                routeState = .ended
            }
            
        // Sensor set: check if this is the start sensor in the next block for this route
        case (_, .didSetSensor(let sensorID, let orientation)):
            let trainSensor =
                await trainController.trainSensorLocationForOrientation(train: train, orientation: orientation)
            guard let sensor = layout.sensor(sensorID) else { throw TrainError.invalidSensor(sensorID) }
            
            if trainSensor == .front
                && sensor.block == pathItem.toBlock
                && sensor.location.isStart {
                
                // Sensor is at the start of the next block in the path
                try await processOccupiedRouteBlock()
            }
            
            if trainSensor == .rear
                && sensor.block == pathItem.fromBlock
                && sensor.location.isStart {
                
                // Sensor is at the start of the from block in the surrent path
                // So train is clear of the previous block and any turnouts etc
                try await processVacatedBlock(train: train)
            }
            
            if trainSensor == .front
                && sensor.location.isEnd {
                if sensor.block == pathItem.toBlock {
                    // Sensor is at the end of the to block in the path
                    // Check if we should stop (only if this is the end of the route)
                    if routeState == .ending {
                        // We are in the last block of the route
                        try await setTrainSpeed(train, speed: .stop, state: .idle)
                        routeState = .ended
                        
                        if let waitTime = route.segments[currentItemIndex.segmentIndex].waitTime {
                            try await Task.sleep(for: .seconds(waitTime.timeInterval))
                        }
                        
                        await LayoutEventHub.shared.publish(.didEndRoute(train))
                        
                    } else {
                        switch try await trainController.trainState(train) {
                        case .stoppingForTimer(let stopSensor, let timer):
                            if sensor == stopSensor {
                                try await setTrainSpeed(train, speed: .stop, state: .stoppedAtSensor(sensor))
                                
                                try await Task.sleep(for: .seconds(timer.timeInterval))
                                
                                log.verbose("Timer ends for \(train)")
                                
                                // Now move on starting with request for the next track resource
                                lastCommandedTrainSpeed = .normal
                                try await processNextPathItem()
                            }
                        default:
                            break
                        }
                    }
                } else if sensor.block == pathItem.fromBlock {
                    // The front of the train is at the end of the from block
                    // Check if we should stop
                    switch try await trainController.trainState(train) {
                    case .idle:                     break
                    case .running(let pathItem):    break
                    case .waiting:                  break
                    case .stoppingForResource(let trackResource):
                        // Stop and wait
                        try await setTrainSpeed(train, speed: .stop, state: .stoppedForResource(trackResource, currentPathItem))
                        
                    case .stoppedForResource(let trackResource, let pathItem):
                        // Should not happen - likely spurious
                        break
                    case .stoppingAtSensor(let stopSensor, let int):
                        if sensor == stopSensor {
                            try await setTrainSpeed(train, speed: .stop, state: .stoppedAtSensor(sensor))
                        }
                        break
                    case .stoppedAtSensor(let sensor):
                        // Ignore, likely spurious
                        break
                    case .stoppingForTimer(let stopSensor, let timer):
                        break
                    }
                }
            }
            
            // End of sensor processing
            // Not a sensor we are interested in
            
        case (_, .didEndTimer(let timerRoute)):
            if timerRoute == route.id {
                routeState = .active
            }
            
        case (_, .didFreeResource(let trackResource)):
            let trainState = try await trainController.trainState(train)
            switch trainState {
            case .stoppingForResource(let freedResource), .stoppedForResource(let freedResource, _):
                if freedResource == trackResource {
                    log.verbose("\(rd): Have expected resource \(freedResource)")
                    
                    routeState = try await requestPathItem(currentPathItem)
                }

            default:
                break
            }
                        
        default:
            break                // Do nothing (unchanged state)
        }
    
        if routeState == .ended {
            await LayoutEventHub.shared.publish(.didEndRoute(train))
        }
        
//        print("*** \(rd): End event: \(event), \(routeState)")
    }
    
    // The train has occupied the toBlock on the current path item
    private func processOccupiedRouteBlock() async throws {
        
        // If this is the placeholder first item just execute the first command
        if isFirstPathItem {
            try await processNextPathItem()
            return
        }
        
        // Set the state on the vacating block
        try await stateService.setStateForBlock(currentPathItem.fromBlock, newState: .vacating(train))
        
        // If this is the last item in the segment check the wait time
        if currentPathItem.role.isLast {
            if let waitTime = route.segments[currentItemIndex.segmentIndex].waitTime {
                // Slow down
                log.debug("Setting slow speed for wait in block \(currentPathItem.toBlock), \(routeDirection)")
                guard let endSensor = layout.sensorForBlock(currentPathItem.toBlock, atBlockStart: false, inDirection: routeDirection) else {
                    throw TrainError.applicationError(24)
                }
                try await setTrainSpeed(train, speed: .slow, state: .stoppingForTimer(endSensor, waitTime))

                // No more processing for now
                return
            }
        }
        
        try await processNextPathItem()
        
        if routeState == .ending {
            // Slow down for the end sensor
            log.debug("Setting slow speed for end in block \(currentPathItem.toBlock), \(routeDirection)")
            guard let endSensor = layout.sensorForBlock(currentPathItem.toBlock, atBlockStart: false, inDirection: routeDirection) else {
                throw TrainError.applicationError(25)
            }
            try await setTrainSpeed(train, speed: .slow, state: .stoppingAtSensor(endSensor, 0))
        }
    }
        
     
    private func processNextPathItem() async throws  {
        // Move to the next path item
        if let nextIndex = nextPathItemIndex() {
            currentItemIndex = nextIndex
        } else {
            routeState = .ending
            return      // No more
        }

        // Allocate resources to the next block
        if let blockingResource = try await stateService.reservePathItem(currentPathItem, forTrain: train) {
            await trainController.setTrainState(train, state: .stoppingForResource(blockingResource))
        } else {
            // No blocking resource - just carry on
            // Power the route
            try await setTrainSpeed(train, speed: lastCommandedTrainSpeed, state: .running(currentPathItem))
            
            // Set the points on this path without default values
            for setting in currentPathItem.pointSettings {
                if setting.point.defaultPosition == nil {
                    // Don't override default positions e.g. on virtual back/back points
                    try await stateService.setDirectionForPoint(setting.point, newDirection: setting.direction)
                }
            }
        }
    }
    
    private func nextPathItemIndex() -> CurrentItemIndex? {
        var newIndex = CurrentItemIndex(
            segmentIndex: currentItemIndex.segmentIndex, pathItemIndex: currentItemIndex.pathItemIndex)
        newIndex.pathItemIndex += 1
        if newIndex.pathItemIndex == route.segments[currentItemIndex.segmentIndex].path.pathItems.count {
            // Reached the end of the path items for this segment
            newIndex.segmentIndex += 1
            newIndex.pathItemIndex = 0
            if newIndex.segmentIndex == route.segments.count {
                // No more segments
                return nil
            }
        }
        return newIndex
    }
    
    // The train has exited the toBlock on the previous path item
    private func processVacatedBlock(train: Train) async throws {
        if let vacatedBlock = await stateService.vacatingBlockForTrain(train) {
            try await stateService.setStateForBlock(vacatedBlock, newState: .vacant)
            try await stateService.releaseDirectionLock(block: vacatedBlock, train: train)
        }
    }
        
    // TODO: this should be able to fail if already locked
    // Lock the path
    private func lockPathForItem(_ pathItem: PathItem, direction: Direction) async throws -> Bool {
        try await stateService.setDirectionForVacantContiguousBlocks(fromBlock: pathItem.fromBlock,
                                                                 train: train,
                                                                 direction: direction)
        return true
    }
    
    private func requestPathItem(_ item: PathItem) async throws -> RouteState {
        if let blockingResource = try await stateService.reservePathItem(item, forTrain: train) {
            // Stop the train
            try await setTrainSpeed(train, speed: .stop, state: .stoppedForResource(blockingResource, item))
            try await stateService.setStateForBlock(
                item.fromBlock,
                newState : .occupied(train))
            
            return .active
            
        } else {
            // No blocking resource - just carry on
            // Power the route
            try await setTrainSpeed(train, speed: .normal, state: .running(item))
            
            // Update the state to reflect the new item
            try await stateService.setStateForBlock(
                item.fromBlock,
                newState : .occupied(train))
                        
            return .active
        }
    }
    
    private func validForStart(route: Route) -> Bool {
        switch routeState {
        case .dormant:
            return true
            
        case .active, .waitingForEvent:          // Unexpected
            log.error("\(rd): \(route): Run route \(route.id) but already in running state")
            return false
        case .error:
            log.error("\(rd): \(route): Attempt to run segment in error state: ends")
            return false
        case .ending, .ended:
            log.error("\(rd): \(route): Attempt to run segment in ended state: ends")
            return false
        }
    }
    
}

extension TimeInterval {
    // Return a timeinterval +- x% of the given interval
    func randomInterval(factor: Double = 0.3) -> TimeInterval {
        return TimeInterval.random(in: self * (1 - factor) ... self * (1 + factor))
    }

}

