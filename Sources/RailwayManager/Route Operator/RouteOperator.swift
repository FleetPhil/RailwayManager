//
//  File.swift
//  
//
//  Created by Phil Diggens on 20/10/2024.
//

import Foundation

enum RouteState: Equatable {
    case dormant
    case processingActions
    case waitingForEvent(LayoutEvent)
    case waitingForResource(TrackResource, PathItem)        // Waiting for resource for pathItem transition
    case waitingforLock(Path)                               // Path waiting for a lock
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

actor RouteOperator {
    let train: Train            // RouteOperator : Train is 1:1 mapping
    var route: Route
    let layout: Layout
    let stateService: LayoutTrackStateService
    let trainController: LayoutTrainController
    
    // Operator State
    private(set) var routeState: RouteState = .dormant {
        didSet {
            if routeState != oldValue, routeState != .processingActions {
                log.info("\(rd): Route state now \(routeState)")
            }
        }
    }
    private var sensorActions: [ Int : SensorAction ] = [:]
    
    // Train state
    private var routeDirection: Direction = .forward        // Default
    private var lastCommandedTrainSpeed: TrainSpeed = .stop
    
    // Action queue
    private var actionQueue: ArrayQueue<RouteAction> = ArrayQueue(capacity: 200)
    
    
    var rd: String {
        "R\(train.id)"
    }
    
    init(route: Route,
         train: Train,
         layout: Layout,
         stateService: LayoutTrackStateService,
         trainController: LayoutTrainController,
        )  {
        self.route = route
        self.train = train
        self.layout = layout
        self.stateService = stateService
        self.trainController = trainController
    }
    
    func resetRoute() async throws {
        // Expand the segments into individual route action items
        actionQueue = try actionsforRoute(route)
        
        guard validForStart(route: route) else {
            throw TrainError.invalidRoute(route.id)
        }
        
        // Request DCC session if necessary
        try await trainController.requestSession(for: train)
        
        // Update the block and train status
        await trainController.setTrainDirection(train, direction: routeDirection)
        try await stateService.setStateForTrain(train, state: .idle)
        try await stateService.setStateForBlock(route.startBlock, newState: .occupied(train, routeDirection))
        
        log.info("\(rd): \(route): Have \(route.segments.count) segments, \(actionQueue.count) actions for route \(route.id)")
    }
    
    // Command a change to the train speed and update the status
    func setTrainSpeed(_ train: Train, speed: TrainSpeed, delay: TimeInterval = 0, state: TrainRuntimeState? = nil) async throws {
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
        
        log.verbose("Process event: \(event)")
        
        // Check for general cases
        switch (routeState, event) {
        case (.dormant, .didStartRoute(let startedTrain)), (.ended, .didStartRoute(let startedTrain)):
            if startedTrain == self.train {
                log.info("\(rd): Starting route for train \(train.id) (\(train.name))")
                                
                // Set up the initial block state
                let direction = route.segments.first?.direction ?? .forward
                
                let initialPathItem = PathItem.initialPathItemForBlock(route.startBlock)
                try await stateService.setStateForBlock(route.startBlock,
                                                newState: .occupied(startedTrain, direction))
                
                // Start processing actions
                routeState = .processingActions
            }
            
        case (.ended, .didEndRoute(let endedTrain)):
            if endedTrain == self.train {
                log.verbose("\(rd): Ended route for train \(self.train)")
                routeState = .ended
            }
            
        case (.waitingForEvent(.didSetSensor(let waitingSensor, _)), .didSetSensor(let setSensor, _)):
            
            // Check this is the sensor we are waiting for
            if waitingSensor == setSensor {
                guard let sensor = layout.sensor(setSensor) else { throw TrainError.applicationError(13) }
                routeState = try await executeSensorAction(sensorActions[setSensor]!, sensor: sensor)
            } else {
                // Train set a sensor that we are not waiting for: check if a speed change is necessary
                
                if layout.sensor(setSensor)!.block.blockExit[routeDirection] == .noExit {
                    // The sensor is in a block with no exit in this direction so slow down
                    if lastCommandedTrainSpeed != .slow {
                        let block = layout.sensor(setSensor)?.location
                        log.debug("Setting slow speed as no exit in block \(block, default: "no block?"), \(routeDirection)")
                        try await setTrainSpeed(train, speed: .slow)
                    }
                }
            }
            
        case (_, .didEndTimer(let timerRoute)):
            if timerRoute == route.id {
                routeState = .processingActions
            }
            
        case (.waitingForResource(let awaitedResource, let pathItem), .didFreeResource(let freedResource)):
            if awaitedResource == freedResource {
                log.verbose("\(rd): Have expected resource \(awaitedResource)")
                
                routeState = try await requestPathItem(pathItem)
            }
            
        case (.waitingforLock(let path), .didFreeResource):
            if try await lockPath(path) {
                log.info("\(rd): path \(path) now unlocked")
                
                routeState = try await requestPathItem(path.pathItems.first!)
            }
            
        default:
            break                // Do nothing (unchanged state)
        }
    

        // Process actions if appropriate
        if routeState == .processingActions {
            try await processActions()
        }
        
        if routeState == .ended {
            await LayoutEventHub.shared.publish(.didEndRoute(train))
        }
        
//        print("*** \(rd): End event: \(event), \(routeState)")
    }
    
    private func executeSensorAction(_ action: SensorAction, sensor: Sensor) async throws -> RouteState {
        
        var newState: RouteState = .dormant
        
        switch action {
        case .stop:
            log.info("\(rd): Sensor \(sensor) action: Stop")

            // Set the train state
            try await setTrainSpeed(train, speed: .stop, state: .stoppedAtSensor(sensor))
            
            // Set the state
            try await stateService.setStateForBlock(sensor.block, newState: .occupied(train, routeDirection))
            
            log.verbose("Train \(train) stopped at sensor \(sensor)")
            
            // Carry on
            newState = .processingActions
            
        case .requestPathItem(let pathItem):
            log.info("\(rd): Sensor \(sensor) action: Request \(pathItem)")

            newState = try await requestPathItem(pathItem)

        case .proceed:
            log.info("\(rd): Sensor \(sensor) action: Proceed")
            newState = .processingActions
        }
        
//        print("*** \(rd): End sensor action: \(action), \(newState)")
        
        return newState
    }

    private func processActions() async throws {
        
        while routeState == .processingActions {
            // Process the commands
            
            // Get the next action item and break if no more
            guard let nextItem = actionQueue.dequeue() else {
                routeState = .ended
                break
            }

            log.verbose("Process action: \(nextItem)")
            
            // Process the next item
            switch nextItem {
            case .lockPath(let path):
                // Attempt to lock the path
                
                // If successful:
                //      sets direction for the blocks on the path
                //      return a state of .processingActions so continue
                // If failed the status will be .waitingForResource
                
                if try await lockPath(path) {
                    // Set the points on this path without default values
                    for pathItem in path.pathItems {
                        for setting in pathItem.pointSettings {
                            if setting.point.defaultPosition == nil {
                                // Don't override default positions e.g. on virtual back/back points
                                try await stateService.setDirectionForPoint(setting.point, newDirection: setting.direction)
                            }
                        }
                    }
                }
                
            case .waitForSensor(let sensor, let action):
                // Queue the action and wait for the sensor to be set
                sensorActions[sensor.id] = action
                routeState = .waitingForEvent(.didSetSensor(sensor.id, .north))         // Orientation ignored
                try await trainController.setTrainState(train, state: .stoppingAtSensor(sensor, 0))
                
            case .executeSensorAction(let sensor, let action):
                routeState = try await executeSensorAction(action, sensor: sensor)
                
            case .setDirection(let newDirection):
                // If the direction has changed the speed must be zero
                if lastCommandedTrainSpeed != .stop {
                    log.error("Direction change for moving train \(train)")
                    try await setTrainSpeed(train, speed: .stop)
                } else {
                    // Valid change in direction for stationary train
                    routeDirection = newDirection
                    await trainController.setTrainDirection(train, direction: newDirection)
                }

            case .setSpeed(let trainSpeed):
                try await setTrainSpeed(train, speed: trainSpeed)
                routeState = .processingActions
                
            case .waitForEvent(let layoutEvent):
                routeState = .waitingForEvent(layoutEvent)
                
            case .wait(let time):
                var waitTime: TimeInterval {
                    switch time {
                    case .fixed(let interval):      interval
                        // TODO: Fix with params
                    case .halt:                     5
                    case .station:                  5
                    case .terminus:                 5
                    }
                }

                log.verbose("\(rd): Timer wait \(time) (\(waitTime)s)")
                routeState = .waitingForEvent(.didEndTimer(route.id))
                let routeID = route.id
                Task {
                    try? await Task.sleep(for: .seconds(waitTime))
                    guard !Task.isCancelled else { return }
                    await LayoutEventHub.shared.publish(.didEndTimer(routeID))
                }
                routeState = .waitingForEvent(.didEndTimer(route.id))
                
            }
            
            log.verbose("*** End process action: state \(routeState)")
        }
    }
        
    // TODO: this should be able to fail if already locked
    // Lock the path
    private func lockPath(_ path: Path) async throws -> Bool {
        var pathBlocks: [Block] = [path.pathItems.first!.fromBlock]
        pathBlocks += path.pathItems.map({ $0.toBlock })
        await stateService.setDirectionForVacantContiguousBlocks(fromBlock: path.pathItems.first!.fromBlock,
                                                                 direction: path.direction)
        return true
    }
    
    private func requestPathItem(_ item: PathItem) async throws -> RouteState {
        if let blockingResource = try await stateService.reservePathItem(item, forTrain: train) {
            // Stop the train
            try await setTrainSpeed(train, speed: .stop, state: .stoppedForResource(blockingResource, item))
            try await stateService.setStateForBlock(
                item.fromBlock,
                newState : .occupied(train, item.direction))
            
            return .waitingForResource(blockingResource, item)
            
        } else {
            // No blocking resource - just carry on
            // Power the route
            try await setTrainSpeed(train, speed: .normal)
            
            // Update the state to reflect the new item
            try await stateService.setStateForBlock(
                item.fromBlock,
                newState : .occupied(train, item.direction))
                        
            return .processingActions
        }
    }
    
    private func validForStart(route: Route) -> Bool {
        switch routeState {
        case .dormant:
            return true
            
        case .processingActions, .waitingForEvent, .waitingForResource, .waitingforLock:          // Unexpected
            log.error("\(rd): \(route): Run route \(route.id) but already in running state")
            return false
        case .error:
            log.error("\(rd): \(route): Attempt to run segment in error state: ends")
            return false
        case .ended:
            log.error("\(rd): \(route): Attempt to run segment in ended state: ends")
            return false
        }
    }
    
    // MARK: Set the actions for the entire route
    private func actionsforRoute(_ route: Route) throws -> ArrayQueue<RouteAction> {
        var currentBlock = route.startBlock
        
        var queue = ArrayQueue<RouteAction>(capacity: 200)
        
        for segment in route.segments {
            
            // First set the direction for this segment
            try queue.enqueue(.setDirection(segment.direction))
            
            // Now process the individual items
            for item in segment.items {
                switch item {
                case .lockPathToBlock(let endBlock):
                    guard let path = try layout.path(fromBlock: currentBlock, toBlock: endBlock, direction: segment.direction) else {
                        throw TrainError.invalidSegment("No path from \(currentBlock) to \(endBlock) direction \(segment.direction)")
                    }
                    try queue.enqueue(.lockPath(path))
                    
                // Move to the sensor in the segment direction, stop if indicated
                case .moveToSensor(let sensor, let stop):
                    guard let sensor = layout.sensor(sensor) else { break }
                    
                    for action in try actionsToSensor(fromBlock: currentBlock,
                                                      toSensor: sensor,
                                                      direction: segment.direction) {
                        try queue.enqueue(action)
                    }
                    
                    // Append the stop action at the end if appropriate
                    if stop {
                        try queue.enqueue(.waitForSensor(sensor, .stop))
                    } else {
                        try queue.enqueue(.waitForSensor(sensor, .proceed))
                    }
                    
                    currentBlock = sensor.block
                case .wait(let waitTime):
                    try queue.enqueue(.wait(waitTime))
                }
            }
        }
        
        // Now validate the queue and remove duplicate sensor stops
        var currentSensor: Sensor? = nil
        for i in 0 ..< queue.count {
            let action = queue.item(i)!
            
            switch action {
            case .waitForSensor(let sensor, let sensorAction):
                if currentSensor == nil || currentSensor == sensor {
                    // No current sensor  means this is the start of the route, so just execute the action
                    // Sensor same as current means just carry on with the action
                    queue.replace(at: i, with: .executeSensorAction(sensor, sensorAction))
                }
                currentSensor = sensor
                
            default:
                break
            }
        }

//        for index in 0 ..< queue.count {
//            print("*** Q: \(queue.item(index)!)")
//        }
        
        return queue
    }
    
    // Return all the actions from the block to the sensor
    private func actionsToSensor(fromBlock: Block, toSensor: Sensor, direction: Direction) throws -> [RouteAction] {
        guard let path = try layout.path(fromBlock: fromBlock,
                                                        toBlock: toSensor.block,
                                                        direction: direction) else {
            throw TrainError.invalidSegment("No path from \(fromBlock) to \(toSensor) direction \(direction)")
        }
        
        var newActions: [RouteAction] = []
        
        // Each item is a single block-block move
        
        for pathItem in path.pathItems {
            // Append the next action
            // Get the stop sensor for the next block, if none just carry on
            if let stopSensor =
                layout.sensorForBlock(pathItem.fromBlock, atBlockStart: false, inDirection: pathItem.direction) {
                newActions.append(.waitForSensor(stopSensor,.requestPathItem(pathItem)))
            } else {
                throw TrainError.applicationError(15)
            }
        }
        
        return newActions
    }
}

extension TimeInterval {
    // Return a timeinterval +- x% of the given interval
    func randomInterval(factor: Double = 0.3) -> TimeInterval {
        return TimeInterval.random(in: self * (1 - factor) ... self * (1 + factor))
    }

}

