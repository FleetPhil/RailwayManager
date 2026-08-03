//
//  RouteOperator.swift
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
            "lock \(path.pathItems.first.map { "\($0.fromBlock)" } ?? "?")-\(path.pathItems.last.map { "\($0.toBlock)" } ?? "?"), \(path.direction)"
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
    
    // MARK: - Current position accessors
    
    private var currentSegment: Segment {
        route.segments[currentItemIndex.segmentIndex]
    }
    
    private var currentWaitTime: WaitTime? {
        currentSegment.waitTime
    }
    
    var currentPathItem: PathItem {
        // Clamp the placeholder start index (-1) to the first item
        currentSegment.path.pathItems[max(currentItemIndex.pathItemIndex, 0)]
    }
    
    var isFirstPathItem: Bool {
        return currentItemIndex.pathItemIndex == -1
    }
    
    // MARK: - Route lifecycle
    
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
    
    // MARK: - Train commands
    
    // Command a change to the train speed and update the status
    func setTrainSpeed(_ train: Train, speed: TrainSpeed, delay: TimeInterval = 0, state: TrainRuntimeState?) async throws {
        try await trainController.commandTrain(train, speed: speed, delay: delay)

        // Update the status
        lastCommandedTrainSpeed = speed
        // State of nil is no change
        if let state {
            try await stateService.setStateForTrain(train, state: state)
        }
    }
    
    // Stop the train, optionally updating the runtime state
    private func stopTrain(state: TrainRuntimeState?) async throws {
        try await setTrainSpeed(train, speed: .stop, state: state)
    }
    
    // MARK: - Event processing
    
    // Process the track event and execute route commands if able based on the layout state
    func processEvent(_ event: LayoutEvent) async throws {
        log.verbose("Process event: \(event), pathItem: \(currentPathItem)")
        
        switch (routeState, event) {
        case (.dormant, .didStartRoute(let startedTrain)), (.ended, .didStartRoute(let startedTrain)):
            if startedTrain == self.train {
                log.info("\(rd): Starting route for train \(train.id) (\(train.name))")
                
                // Start the train moving and trigger processing for this block being occupied
                try await setTrainSpeed(startedTrain, speed: .normal, state: .running(currentPathItem))
                
                try await stateService.setStateForBlock(route.startBlock, newState: .occupied(startedTrain), trainStateChanged: true)
                
                routeState = .active
                try await processOccupiedRouteBlock()
            }
            
        case (.ended, .didEndRoute(let endedTrain)):
            if endedTrain == self.train {
                log.verbose("\(rd): Ended route for train \(self.train)")
                routeState = .ended
            }
            
        case (_, .didSetSensor(let sensorID, let orientation)):
            try await handleSensorSet(sensorID, orientation: orientation)
            
        case (_, .didEndTimer(let timerRoute)):
            if timerRoute == route.id {
                routeState = .active
            }
            
        case (_, .didFreeResource(let trackResource)):
            try await handleFreedResource(trackResource)
                        
        default:
            break                // Do nothing (unchanged state)
        }
   
    }
    
    // MARK: - Sensor event handling
    
    // Dispatch a sensor event based on which end of the train tripped it and where it sits on the current path
    private func handleSensorSet(_ sensorID: Int, orientation: SensorEventOrientation) async throws {
        let pathItem = currentPathItem
        let trainSensor =
            try await trainController.trainSensorLocationForOrientation(train: train, orientation: orientation)
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
            try await handleFrontAtBlockEnd(sensor, pathItem: pathItem)
        }
    }
    
    // The front of the train has reached an end-of-block sensor
    private func handleFrontAtBlockEnd(_ sensor: Sensor, pathItem: PathItem) async throws {
        if sensor.block == pathItem.toBlock {
            // Sensor is at the end of the to block in the path
            // Check if we should stop (only if this is the end of the route)
            if routeState == .ending {
                // We are in the last block of the route
                try await stopTrain(state: .idle)
                routeState = .ended
                
                if let waitTime = currentWaitTime {
                    try await Task.sleep(for: .seconds(waitTime.timeInterval))
                }
                
                await LayoutEventHub.shared.publish(.didEndRoute(train))
                
            } else if case .stoppingForTimer(let stopSensor, let timer) = try await trainController.trainState(train),
                      sensor == stopSensor {
                try await stopTrain(state: .stoppedAtSensor(sensor))
                
                try await Task.sleep(for: .seconds(timer.timeInterval))
                
                log.verbose("Timer ends for \(train)")
                
                // Now move on starting with request for the next track resource
                lastCommandedTrainSpeed = .normal
                try await processNextPathItem()
            }
        } else if sensor.block == pathItem.fromBlock {
            // The front of the train is at the end of the from block
            // Check if we should stop
            switch try await trainController.trainState(train) {
            case .stoppingForResource(let trackResource):
                // Stop and wait
                try await stopTrain(state: .stoppedForResource(trackResource, currentPathItem))
                
            case .stoppingAtSensor(let stopSensor, _) where sensor == stopSensor:
                try await stopTrain(state: .stoppedAtSensor(sensor))
                
            default:
                break       // Other states are no-ops or likely spurious
            }
        }
    }
    
    // A track resource has been freed: resume if it is the one we are waiting for
    private func handleFreedResource(_ trackResource: TrackResource) async throws {
        switch try await trainController.trainState(train) {
        case .stoppingForResource(let freedResource), .stoppedForResource(let freedResource, _):
            if freedResource == trackResource {
                log.verbose("\(rd): Have expected resource \(freedResource)")
                
                routeState = try await requestPathItem(currentPathItem)
            }

        default:
            break
        }
    }
    
    // MARK: - Path item processing
    
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
        if currentPathItem.role.isLast, let waitTime = currentWaitTime {
            // Slow down for the wait
            try await slowForEndSensor { .stoppingForTimer($0, waitTime) }
            
            // No more processing for now
            return
        }
        
        try await processNextPathItem()
        
        if routeState == .ending {
            // Slow down for the end sensor
            try await slowForEndSensor { .stoppingAtSensor($0, 0) }
        }
    }
    
    // Slow the train for the end sensor of the current toBlock, moving to the given state
    private func slowForEndSensor(state: (Sensor) -> TrainRuntimeState) async throws {
        log.debug("Setting slow speed in block \(currentPathItem.toBlock), \(routeDirection)")
        guard let endSensor = layout.sensorForBlock(currentPathItem.toBlock, atBlockStart: false, inDirection: routeDirection) else {
            throw TrainError.applicationError("No end sensor for block \(currentPathItem.toBlock), \(routeDirection)")
        }
        try await setTrainSpeed(train, speed: .slow, state: state(endSensor))
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
        if let blockingResource = try await reserveOrRun(currentPathItem, resumeSpeed: lastCommandedTrainSpeed) {
            try await stateService.setStateForTrain(train, state: .stoppingForResource(blockingResource))
        } else {
            // Set the points on this path without default values
            for setting in currentPathItem.pointSettings where setting.point.defaultPosition == nil {
                // Don't override default positions e.g. on virtual back/back points
                try await stateService.setDirectionForPoint(setting.point, newDirection: setting.direction)
            }
        }
    }
    
    private func requestPathItem(_ item: PathItem) async throws -> RouteState {
        if let blockingResource = try await reserveOrRun(item, resumeSpeed: .normal) {
            // Stop the train and wait for the resource to be freed
            try await stopTrain(state: .stoppedForResource(blockingResource, item))
        }
        
        // Update the state to reflect the new item
        try await stateService.setStateForBlock(
            item.fromBlock,
            newState : .occupied(train), trainStateChanged: true)
        
        return .active
    }
    
    // Try to reserve the path item, returning the blocking resource if the reservation failed.
    // Otherwise power the route at the given speed and return nil
    private func reserveOrRun(_ item: PathItem, resumeSpeed: TrainSpeed) async throws -> TrackResource? {
        if let blockingResource = try await stateService.reservePathItem(item, forTrain: train) {
            return blockingResource
        }
        
        // No blocking resource - just carry on
        // Power the route
        try await setTrainSpeed(train, speed: resumeSpeed, state: .running(item))
        return nil
    }
    
    private func nextPathItemIndex() -> CurrentItemIndex? {
        var newIndex = CurrentItemIndex(
            segmentIndex: currentItemIndex.segmentIndex, pathItemIndex: currentItemIndex.pathItemIndex)
        newIndex.pathItemIndex += 1
        if newIndex.pathItemIndex == currentSegment.path.pathItems.count {
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
