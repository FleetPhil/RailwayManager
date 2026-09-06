//
//  RouteOperator.swift
//  
//
//  Created by Phil Diggens on 20/10/2024.
//

import Foundation

enum RouteState: Equatable {
    case dormant
    case starting           // Start sequence in progress
    case active
    case ending
    case ended
    case error(TrainError)
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
        ) async throws {
        self.route = route
        self.train = train
        self.layout = layout
        self.stateService = stateService
        self.trainController = trainController
        
        guard let routeDirection = route.segments.first?.path.direction else {
            throw TrainError.noTrainDirection(train.id)
        }
        try await trainController.setTrainDirection(train, direction: routeDirection)
        
        currentItemIndex = CurrentItemIndex(segmentIndex: 0, pathItemIndex: 0)
    }
    
    // MARK: - Current position accessors
    
    private var currentSegment: Segment {
        route.segments[currentItemIndex.segmentIndex]
    }
    
    private var currentSegmentIsLast: Bool {
        currentItemIndex.segmentIndex == route.segments.count - 1
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
    
    func resetRoute() async throws {
        guard validForStart(route: route) else {
            throw TrainError.invalidRoute(route.id)
        }
        
        // Request DCC session if necessary
        try await trainController.requestSession(for: train)
        
        // Update the block and train status
        let routeDirection = route.segments.first?.path.direction
        try await trainController.setTrainDirection(train, direction: routeDirection ?? .forward)
        try await stateService.setStateForTrain(train, state: .idle)
        try await stateService.setStateForBlock(route.startBlock, newState: .occupied(train))
        
        // Will be incremented at route start
        currentItemIndex = CurrentItemIndex(segmentIndex: 0, pathItemIndex: -1)
        
        try await LayoutEventHub.shared.publish(.didOccupyBlock(route.startBlock, train))

        log.info("\(rd): \(route): reset complete")
    }
    
    // MARK: - Train commands
    
    // Calculate the correct speed for the train in specified block based on the current track conditions
    private func setTrainSpeed(inBlock: Block) async throws {
        var newSpeed: TrainSpeed = lastCommandedTrainSpeed
        
        // If train state is stopping speed is slow
        switch try await trainController.trainState(train) {
        case .stoppingForResource, .stoppingAtSensor, .stoppingForTimer:
            newSpeed = .slow
        default:
            // If no block exit speed is slow
            let trainDirection = try await trainController.trainDirection(train)
            if [.noExit, .none].contains(inBlock.blockExit[trainDirection]) {
                newSpeed = .slow
            } else {
                // Set speed according to signal state
                if let endSignal = layout.endSignalForBlock(inBlock, direction: trainDirection) {
                    let blockEndSignalState = try await stateService.signalState(endSignal)
                    switch blockEndSignalState {
                    case (.stop, _):                    newSpeed = .slow        // Home state stop
                    case (.left, _), (.right, _):       newSpeed = .normal      // Transitioning over points
                    case (_, .stop):                    newSpeed = .normal      // Remote stop
                    default:                            newSpeed = .fast
                    }
                }
            }
        }
        
        
        if newSpeed != lastCommandedTrainSpeed {
            log.verbose("Train speed is \(newSpeed) (was \(lastCommandedTrainSpeed))")
            lastCommandedTrainSpeed = newSpeed
            
            try await trainController.setSpeedforTrain(train, speed: lastCommandedTrainSpeed)
        }
    }
    
    // Unconditionally stop the train
    private func stopTrain() async throws {
        try await trainController.setSpeedforTrain(train, speed: .stop)
    }
    
    private func setTrainState(_ state: TrainRuntimeState) async throws {
        try await trainController.setTrainState(train, state: state)
    }
    
    // MARK: - Route start sequence
    
    // In-progress start sequence - runs in its own task so its delays do not block event processing
    private var startSequenceTask: Task<Void, Never>? = nil
    
    // Execute the train's start functions (e.g. sounds) in order, waiting for each
    // function's delay before the next, then move off
    private func runStartSequence() async {
        defer { startSequenceTask = nil }
        
        do {
            for startFunction in train.startFunctions {
                log.verbose("\(rd): Start function \(startFunction.startFunction) for train \(train.id)")
                try await trainController.setTrainFunction(train: train, function: startFunction.startFunction, on: true)
                try await Task.sleep(for: .seconds(startFunction.delay))
            }
            
            // Start sequence complete: sensor events are processed from here on
            routeState = .active
            
            try await processOccupiedRouteBlock()
        } catch is CancellationError {
            // Route was cancelled during the start sequence: nothing to do
        } catch {
            log.error("\(rd): Route start failed: \(error)")
            routeState = .error(error as? TrainError ?? .applicationError("Route start failed: \(error)"))
        }
    }
    
    // MARK: - Start route processing
    
    // Process the track event and execute route commands if able based on the layout state
    // Sensor set events are dispatched to handleSensorSet() from the layout manager
    func handleStartRouteEvent() async throws {
        guard [RouteState.dormant, .ended].contains(routeState) else {
            throw TrainError.trainAlreadyActive(train.id)
        }
        
        log.info("\(rd): Starting route for train \(train.id) (\(train.name))")
                
        // Train will be commanded to move when first transition is clear
        // Trigger processing for this block being occupied
        
        try await stateService.setStateForBlock(route.startBlock, newState: .occupied(train))
        
        routeState = .starting
        
        // Run the start sequence in its own task so that the delays between
        // start functions do not block event processing for other trains
        startSequenceTask = Task {
            await self.runStartSequence()
        }
    }
    
    // MARK: - Sensor event handling
    
    // Dispatch a sensor event based on which end of the train tripped it and where it sits on the current path
    func handleSensorSet(_ sensor: Sensor, orientation: SensorEventOrientation) async throws {
        let pathItem = currentPathItem
        let trainSensor =
            try await trainController.trainSensorLocationForOrientation(train: train, orientation: orientation)

        // First update the block states
        let trainDirection = try await trainController.trainDirection(train)
        let isStartOfBlock = sensor.location.isStart(trainDirection)
        let isToBlock = sensor.block == pathItem.toBlock

        switch (trainSensor, isStartOfBlock, isToBlock) {
        case (.front, true, true):
            // Sensor is at the start of the next block in the path
            try await processOccupiedRouteBlock()
            
        case (.rear, true, false):
            // Sensor at the back of the train is at the start of the from block in the current (new) path
            // So train is clear of the previous block and any turnouts etc
            // There could be more than 1 vacating block, only vacate the one where the sensor is
            try await processVacatedBlock(train: train, block: pathItem.fromBlock)
            
        case (.front, false, true):
            // Sensor is at the front of the train at the end of the to block
            try await handleFrontAtToBlockEnd(sensor, pathItem: pathItem)
            try await checkForTrainStop(sensor)

        case (.front, false, false):
            // Sensor is at the front of the train at the end of the from block
            // Path has not incremented forward so likely this is because of a resource conflict
            try await handleFrontAtFromBlockEnd(sensor, pathItem: pathItem)
            
        case (.front, _, true):
            // Sensor is at a sensor in the to block (likely station or end)
            try await checkForTrainStop(sensor)
            
        default:
            break
        }
        
    }
    
    // check if we should stop at this sensor at a segment end
    private func checkForTrainStop(_ sensor: Sensor) async throws {
        // Check for the last block of the route
        if routeState == .ending {
            try await stopTrain()
            try await setTrainState(.idle)
            routeState = .ended
            
            if let waitTime = currentWaitTime {
                try await Task.sleep(for: .seconds(waitTime.timeInterval))
            }
            
            await LayoutEventHub.shared.publish(.didEndRoute(train))
        }
        
        // Check if we should stop at this sensor for a timer
        if case .stoppingForTimer(let stopSensor, let timer) = try await trainController.trainState(train),
                  sensor == stopSensor {
            try await stopTrain()
            try await setTrainState(.stoppedAtSensor(sensor))
            
            try await Task.sleep(for: .seconds(timer.timeInterval))
            
            log.verbose("Timer ends for \(train)")
            
            // Now move on starting with request for the next track resource
            try await processNextPathItem()
        }
    }
    
    // The front of the train has reached an end-of-block sensor in the to block
    private func handleFrontAtToBlockEnd(_ sensor: Sensor, pathItem: PathItem) async throws {
        try await checkForTrainStop(sensor)
    }
    
    private func handleFrontAtFromBlockEnd(_ sensor: Sensor, pathItem: PathItem) async throws {
        // The front of the train is at the end of the from block
        // Check if we should stop
        switch try await trainController.trainState(train) {
        case .stoppingForResource(let trackResource):
            // Stop and wait as this is the end of a block
            try await stopTrain()
            try await setTrainState(.stoppedForResource(trackResource, currentPathItem))
            
        case .stoppingAtSensor(let stopSensor, _) where sensor == stopSensor:
            try await stopTrain()
            try await setTrainState(.stoppedAtSensor(sensor))
            
        default:
            // Nothing to do, the train is not stopping at the end of this block
            // Set the block state to vacating
            try await stateService.setStateForBlock(sensor.block, newState: .vacating(train))
        }
    }
    
    // A track resource has been freed: resume if it is the one we are waiting for
    func handleFreedResource(_ trackResource: TrackResource) async throws {
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
            try await setTrainSpeed(inBlock: currentPathItem.fromBlock)
            try await processNextPathItem()
            return
        }
        
        // Set the state on the vacating block
        try await stateService.setStateForBlock(currentPathItem.fromBlock, newState: .vacating(train))
        
        // Check if we are stopping in this block, if not just carry on
        // We are stopping if this is the last pathItem in the segment and a wait time has been defined
        guard currentPathItem.role.isLast, let waitTime = currentWaitTime else {
            try await processNextPathItem()
            return
        }
        
        // We are stopping in toBlock
        
        // Identify the sensor that we will be stopping at:
        // If there is a station sensor in the block use that, otherwise use the end sensor
        var stopSensor: Sensor {
            get throws {
                if let stationSensor = layout.stationSensorForBlock(currentPathItem.toBlock) {
                    return stationSensor
                } else {
                    let trainDirection = try trainController.trainDirection(train)
                    guard let endSensor = layout.sensorForBlock(currentPathItem.toBlock, atBlockStart: false, inDirection: trainDirection) else {
                        throw TrainError.applicationError("No end sensor for block \(currentPathItem.toBlock), \(trainDirection)")
                    }
                    return endSensor
                }
            }
        }
        
        log.verbose("Train \(train) will stop at \(try! stopSensor) in block \(currentPathItem.toBlock)")
        
        try await setTrainState(.stoppingForTimer(stopSensor, waitTime))
        try await setTrainSpeed(inBlock: currentPathItem.toBlock)
        
        // If this is also the last segment set the route state
        if currentSegmentIsLast {
            routeState = .ending
        }
        
        // No more processing for now
    }
         
    private func processNextPathItem() async throws  {
        // Move to the next path item
        if let nextIndex = nextPathItemIndex() {
            currentItemIndex = nextIndex
            
            // Check for change in direction (setDirection will return if no change)
            try await trainController.setTrainDirection(train, direction: currentSegment.path.direction)
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
        
        // Set the speed for the new block
        try await setTrainSpeed(inBlock: currentPathItem.fromBlock)
    }
    
    private func requestPathItem(_ item: PathItem) async throws -> RouteState {
        if let blockingResource = try await reserveOrRun(item, resumeSpeed: .normal) {
            // Stop the train and wait for the resource to be freed
            try await stopTrain()
            try await setTrainState(.stoppedForResource(blockingResource, item))
        }
        
        // No blocking resource: update the state to reflect the new item
        try await stateService.setStateForBlock(item.fromBlock, newState : .occupied(train))
        try await setTrainSpeed(inBlock: item.fromBlock)
        
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
        try await setTrainSpeed(inBlock: item.fromBlock)
        try await setTrainState(.running(item))
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
    private func processVacatedBlock(train: Train, block: Block) async throws {
        try await stateService.setStateForBlock(block, newState: .vacant)
        try await stateService.releaseDirectionLock(block: block, train: train)
    }
        
    private func validForStart(route: Route) -> Bool {
        switch routeState {
        case .dormant:
            return true
            
        case .starting, .active:          // Unexpected
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
