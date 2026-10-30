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
    
    var isInactive: Bool {
        switch self {
        case .dormant, .ended:      true
        default:                    false
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
            if routeState != oldValue {
                log.info("\(rd): Route state now \(routeState)")
            }
        }
    }
    
    // Train state
    private var lastCommandedTrainSpeed: TrainSpeed = .stop
    
    // The segment the front of the train is on, and the path item it is on (nil before the route starts).
    // Each path item is worked out as the front reaches the block before it.
    private var frontSegmentIndex: Int = 0
    private var frontItem: PathItem? = nil
    // The block the current segment ends in: its toBlock, or an alternative if that is held by another
    // train (chosen with each path item). The front item leads into it at the end of the segment
    private var frontItemEndBlock: Block? = nil
    // The block the train starts the route from, where it was when the route was run
    private var startBlock: Block? = nil
    // The path items the front has moved on to that the rear has not yet cleared, oldest first:
    // the rear of the train is on the first
    private var rearItems: [PathItem] = []
    
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
        
        guard let routeDirection = route.segments.first?.direction else {
            throw TrainError.noTrainDirection(train.id)
        }
        try await trainController.setTrainDirection(train, direction: routeDirection)
    }
    
    // MARK: - Current position accessors
    private var currentSegment: Segment {
        route.segments[frontSegmentIndex]
    }
    
    private var currentSegmentIsLast: Bool {
        frontSegmentIndex == route.segments.count - 1
    }
    
    private var currentWaitTime: WaitTime? {
        currentSegment.waitTime
    }
    
    // The front is in (or heading for) the segment's end block, and the segment stops as soon as the
    // train is wholly in it: the stop is made when the rear passes the start of the block
    private var isStoppingOnEntry: Bool {
        frontItem != nil && frontItem?.toBlock == frontItemEndBlock && currentSegment.stopAt == .entered
    }
    
    // MARK: - Route lifecycle
    
    func resetRoute(route: Route, startBlock: Block) async throws {
        // Check no active route. Function throws if not
        try await validStateForStart(route: route)
        
        self.route = route
        self.startBlock = startBlock
        
        // Request DCC session if necessary
        try await trainController.requestSession(for: train)
        
        // Update the block and train status
        try await trainController.setTrainDirection(train, direction: route.initialDirection)
        if let initialDCCDirection = route.initialDCCDirection {
            await trainController.setTrainFacing(train, dccDirection: initialDCCDirection, travelling: route.initialDirection)
        }
        try await stateService.setStateForTrain(train, state: .idle(startBlock))
        try await stateService.setStateForBlock(startBlock, newState: .occupied(train, route.initialDirection))
        
        // The first path item is worked out at route start
        frontSegmentIndex = 0
        frontItem = nil
        frontItemEndBlock = nil
        rearItems = []

        try await LayoutEventHub.shared.publish(.didOccupyBlock(startBlock, train))

        log.info("\(rd): \(route): reset complete")
    }
    
    // MARK: - Train commands
    
    // The train's travel direction in a block, which differs from the train's direction part-way
    // round a reversing loop. The block should be held by this train (its block state records the
    // direction); if not, fall back to the train's direction.
    private func travelDirection(in block: Block) async throws -> BlockDirection {
        if let blockState = await stateService.blockState(block),
           blockState.train == train, let direction = blockState.direction {
            return direction
        }
        return try await trainController.trainDirection(train)
    }
    
    // Calculate the correct speed for the train in specified block based on the current track conditions
    private func setTrainSpeed(inBlock: Block) async throws {
        var newSpeed: TrainSpeed = lastCommandedTrainSpeed
        
        // TODO: set delay based on block length and last commanded speed
        
        var delay: TimeInterval = 0
        
        // If train state is stopping speed is slow
        switch try await trainController.trainState(train) {
        case .stoppingForResource, .stoppingAtSensor, .stoppingForTimer:
            newSpeed = .slow
        default:
            // If no block exit speed is slow
            let blockDirection = try await travelDirection(in: inBlock)
            if [.noExit, .none].contains(inBlock.blockExit[blockDirection]) {
                newSpeed = .slow
            } else {
                // Set speed according to signal state
                if let endSignal = layout.endSignalForBlock(inBlock, direction: blockDirection) {
                    let blockEndSignalState = try await stateService.signalState(endSignal)
                    switch blockEndSignalState {
                    case (.stop, _):
                        newSpeed = .slow        // Home state stop
                        delay = 3
                    case (.left, _), (.right, _):
                        newSpeed = .normal      // Transitioning over points
                        delay = 3
                    case (_, .stop):
                        newSpeed = .normal      // Remote stop
                        delay = 0
                    default:
                        newSpeed = .fast
                        delay = 0
                    }
                } else {
                    // No signal at the block exit: run at normal speed (on sight)
                    newSpeed = .normal
                }
            }
        }
        
        if newSpeed != lastCommandedTrainSpeed {
            let trainDirection = try await trainController.trainDirection(train)
            log.info("Train speed is \(newSpeed) \(trainDirection) (was \(lastCommandedTrainSpeed))")
            lastCommandedTrainSpeed = newSpeed
            
            try await trainController.setSpeedforTrain(train, speed: lastCommandedTrainSpeed, delay: delay)
        }
    }
    
    // Stop the train immediately
    private func stopTrain() async throws {
        log.info("Train \(train) stopped (was \(lastCommandedTrainSpeed))")
        
        // Record the stop so the next speed calculation always sends a fresh command
        lastCommandedTrainSpeed = .stop
        try await trainController.setSpeedforTrain(train, speed: .stop)
    }
    
    // Stop the train and wait for the resource to be freed before moving on to the path item
    private func stopForResource(_ resource: TrackResource, item: PathItem) async throws {
        try await stopTrain()
        try await setTrainState(.stoppedForResource(resource, item))
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
                log.verbose("\(rd): Start function \(startFunction.function) for train \(train.id)")
                try await trainController.setTrainFunction(train: train, function: startFunction.function, on: true)
                try await Task.sleep(for: .seconds(startFunction.delay))
                try await trainController.setTrainFunction(train: train, function: startFunction.function, on: false)
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
        
        guard let startBlock else { throw TrainError.noStartBlockForRoute(route.id) }
        try await stateService.setStateForBlock(startBlock, newState: .occupied(train, route.initialDirection))
        
        routeState = .starting
        
        // Set the direction and turn on the light (F0)
        try await trainController.setTrainDirection(train, direction: route.initialDirection)
        try await trainController.setSpeedforTrain(train, speed: .stop)
        try await trainController.setTrainFunction(train: train, function: 0, on: true)
        
        // Run the start sequence in its own task so that the delays between
        // start functions do not block event processing for other trains
        startSequenceTask = Task {
            await self.runStartSequence()
        }
    }
    
    // MARK: - Sensor event handling
    
    // Dispatch a sensor event based on which end of the train tripped it and where it sits on the current path
    func handleSensorSet(_ sensor: Sensor, orientation: SensorEventOrientation) async throws {
        let trainSensor =
            try await trainController.trainSensorLocationForOrientation(train: train, orientation: orientation)

        // Start/end of block depends on the train's travel direction in the sensor's block
        let sensorBlockDirection = try await travelDirection(in: sensor.block)
        let isStartOfBlock = sensor.location.isStart(sensorBlockDirection)
        let isEndOfBlock = sensor.location.isEnd(sensorBlockDirection)
        
        let startEndText = isStartOfBlock ? "start" : isEndOfBlock ? "end" : "mid"
        log.info("Sensor \(sensor) \(orientation) set at \(startEndText) of block \(sensor.block) for train \(train) ")
        
        // MARK: Sensor set scenarios
        switch trainSensor {
        case .front:
            guard let frontItem else { break }      // Route not started
            if isStartOfBlock && sensor.block == frontItem.toBlock {
                // Start of the next block in the path
                try await processOccupiedRouteBlock()
            } else if sensor.block == frontItem.toBlock {
                // Sensor is at the front of the train in the to block but after the start of block sensor
                try await checkForTrainStop(sensor, byRear: false, isEndOfBlock: isEndOfBlock)
            } else if isEndOfBlock && sensor.block == frontItem.fromBlock {
                // Sensor is at the front of the train at the end of the from block
                // Path has not incremented forward so likely this is because of a resource conflict
                // check if the train should stop
                try await handleFrontAtFromBlockEnd(sensor, pathItem: frontItem)
            }
            
        case .rear:
            guard let rearItem = rearItems.first else { break }     // Rear has cleared every item so far
            if isStartOfBlock && sensor.block == rearItem.toBlock {
                // Sensor at the back of the train is at the start of the to block in the current path
                // So train is clear of the previous block and any turnouts etc
                // There could be more than 1 vacating block, only vacate the one where the sensor is
                
                try await processVacatedBlock(train: train, block: rearItem.fromBlock)
            }
            
            // The rear passing the start of the end block: the train is wholly in it
            if isStartOfBlock && isStoppingOnEntry && sensor.block == frontItemEndBlock {
                try await checkForTrainStop(sensor, byRear: true, isEndOfBlock: isEndOfBlock)
            }
        }
    }
    
    // check if we should stop at this sensor at a segment end
    private func checkForTrainStop(_ sensor: Sensor, byRear: Bool, isEndOfBlock: Bool) async throws {
        // A segment that stops once the train is wholly in its end block stops when the rear passes the
        // start sensor. The front reaching the end of the block first means the train is longer than the
        // block: stop there instead. Any other front sensor is ignored
        var isLongTrainStop = false
        if isStoppingOnEntry && !byRear {
            guard isEndOfBlock else { return }
            log.warning("\(rd): Train \(train) reached the end of block \(sensor.block) before it was wholly in it: stopping")
            isLongTrainStop = true
        }
        
        // Check for the last block of the route
        if routeState == .ending {
            try await endRoute(atSensor: sensor)
            return
        }
        
        // Check if we should stop at this sensor for a timer
        if case .stoppingForTimer(let stopSensor, let timer) = try await trainController.trainState(train),
                  sensor == stopSensor || isLongTrainStop {
            let stopDelay = stopDelay(sensor: stopSensor)
            if stopDelay > 0 {
                try await Task.sleep(for: .seconds(stopDelay))
            }
            try await stopTrain()
            try await setTrainState(.stoppedAtSensor(sensor))
            
            try await Task.sleep(for: .seconds(timer.timeInterval))
            
            log.verbose("Timer ends for \(train)")
            
            // Now move on starting with request for the next track resource
            try await processNextFrontPathItem()
        }
    }
    
    // Cleanup at end of route after last sensor has been set
    private func endRoute(atSensor: Sensor) async throws {
        // TODO: add stopping event after timer instead of sleep
        let stopDelay = stopDelay(sensor: atSensor)
        
        // Wait for the delay before ending the route
        try await Task.sleep(for: .seconds(stopDelay))

        try await stopTrain()
        try await setTrainState(.idle(atSensor.location.block))
        
        // Free any resources owned by this train except the block with the sensor that it has stopped at
        // Setting the block state will trigger an event to free associated points
        for block in layout.blocks.filter({ $0 != atSensor.location.block }) {
            if try await stateService.trainForBlock(block) == train {
                try await stateService.setStateForBlock(block, newState: .vacant)
            }
        }
        
        if let waitTime = currentWaitTime {
            try await Task.sleep(for: .seconds(waitTime.timeInterval))
        }
        
        // Turn off light
        try await trainController.setTrainFunction(train: train, function: 0, on: false)
        try await Task.sleep(for: .milliseconds(100))
        
        // End the DCC session
        try await trainController.releaseSession(for: train)

        routeState = .ended
        await LayoutEventHub.shared.publish(.didEndRoute(train))
    }
    
    // Return the delay before stopping for the train at this sensor
    // (the same in either direction: a station stop is half a train length past the station sensor)
    private func stopDelay(sensor: Sensor) -> TimeInterval {
        switch sensor.location {
        case .station:
            // We need to stop after half a train length
            let speed = Double(train.speeds.setting(for: lastCommandedTrainSpeed)?.speed ?? 10)
            let length = Double(train.length) / 2
            
            let delay = length / speed
            
            log.debug("Delay is \((delay*100).rounded()/100) for length \(length) and speed \(speed)")
            
            return delay
            
        default:
            return 0                // No delay
        }
    }
    
    private func handleFrontAtFromBlockEnd(_ sensor: Sensor, pathItem: PathItem) async throws {
        // The front of the train is at the end of the from block
        // Check if we should stop
        switch try await trainController.trainState(train) {
        case .stoppingForResource(let trackResource):
            // Stop and wait as this is the end of a block
            try await stopForResource(trackResource, item: pathItem)
            
        default:
            // Nothing to do, the train is not stopping at the end of this block
            // Set the block state to vacating
            try await stateService.setStateForBlock(sensor.block, newState: .vacating(train, pathItem.fromDirection))
        }
    }
    
    // A track resource has been freed: resume if it is the one we are waiting for, or if waiting to
    // enter the segment's end block and the freed block is one the segment can end in
    func handleFreedResource(_ trackResource: TrackResource) async throws {
        switch try await trainController.trainState(train) {
        case .stoppingForResource(let awaitedResource), .stoppedForResource(let awaitedResource, _):
            guard let waitingItem = frontItem else { break }
            let isAwaited = awaitedResource == trackResource
            var isFreedEndBlock: Bool {
                guard case .block(let block) = trackResource, waitingItem.toBlock == frontItemEndBlock else { return false }
                return layout.endBlocks(for: currentSegment.toBlock).contains(block)
            }
            guard isAwaited || isFreedEndBlock else { break }
            log.verbose("\(rd): Have \(isAwaited ? "expected" : "end block") resource \(trackResource)")
            
            // Work the item out again, as a path round other trains, or to another end block, may now be clear.
            // Nothing was reserved for the waiting item, so it can simply be replaced.
            let (item, endBlock) = try await pathItem(from: waitingItem.fromBlock, direction: waitingItem.fromDirection,
                                                      segmentIndex: frontSegmentIndex)
            guard frontItem == waitingItem else { return }      // Moved on while finding the path
            guard isAwaited || item != waitingItem else { return }      // Still waiting for the same resource
            frontItem = item
            frontItemEndBlock = endBlock
            if rearItems.last == waitingItem {
                rearItems[rearItems.count - 1] = item
            }
            
            routeState = try await requestPathItem(item)

        default:
            break
        }
    }
    
    // MARK: - Path item processing
    
    // The train has occupied the toBlock on the current path item
    private func processOccupiedRouteBlock() async throws {
        
        // At route start there is no path item yet: just execute the first command.
        // The train is stationary and only moves off once the first path item is reserved
        guard let frontItem else {
            try await processNextFrontPathItem()
            return
        }
        
        // Set the state on the vacating block and the occupied block
        try await stateService.setStateForBlock(frontItem.fromBlock, newState: .vacating(train, frontItem.fromDirection))
        try await stateService.setStateForBlock(frontItem.toBlock, newState: .occupied(train, frontItem.toDirection))
        
        // Crossing a loop closure flips the block orientation: the train's travel direction and facing
        // both change, so the DCC direction (and front/rear sensor detection) stays the same
        if frontItem.fromDirection != frontItem.toDirection {
            try await trainController.crossOrientationChange(train)
        }
        
        // Check if we are stopping in this block, if not just carry on
        // We are stopping if this is the end of the segment and a wait time has been defined
        guard frontItem.toBlock == frontItemEndBlock, let waitTime = currentWaitTime else {
            try await processNextFrontPathItem()
            return
        }
        
        // We are stopping in toBlock
        
        // Identify the sensor that we will be stopping at: when stopping on entry the start sensor (set by the rear);
        // otherwise if there is a station sensor in the block use that, otherwise use the end sensor
        let stopAt = currentSegment.stopAt
        var stopSensor: Sensor {
            get throws {
                if stopAt == .entered {
                    let toDirection = frontItem.toDirection
                    guard let startSensor = layout.sensorForBlock(frontItem.toBlock, atBlockStart: true, inDirection: toDirection) else {
                        throw TrainError.applicationError("No start sensor for block \(frontItem.toBlock), \(toDirection)")
                    }
                    return startSensor
                } else if let stationSensor = layout.stationSensorForBlock(frontItem.toBlock) {
                    return stationSensor
                } else {
                    // The train stops at the end of toBlock in the direction it enters it
                    let toDirection = frontItem.toDirection
                    guard let endSensor = layout.sensorForBlock(frontItem.toBlock, atBlockStart: false, inDirection: toDirection) else {
                        throw TrainError.applicationError("No end sensor for block \(frontItem.toBlock), \(toDirection)")
                    }
                    return endSensor
                }
            }
        }
        
        log.verbose("Train \(train) will stop at \(try! stopSensor) in block \(frontItem.toBlock)")
        
        try await setTrainState(.stoppingForTimer(stopSensor, waitTime))
        try await setTrainSpeed(inBlock: frontItem.toBlock)
        
        // If this is also the last segment set the route state
        if currentSegmentIsLast {
            routeState = .ending
        }
        
        // No more processing for now
    }
         
    private func processNextFrontPathItem() async throws {
        let isRouteStart = frontItem == nil
        let trainState = try await trainController.trainState(train)
        
        // Move to the next path item
        guard let nextItem = try await nextFrontPathItem() else {
            routeState = .ending
            return      // No more
        }
        frontItem = nextItem
        rearItems.append(nextItem)
        
        // Check for change in direction: a new segment starting in the opposite direction to the
        // train's travel direction in its current block reverses the train, which reverses its
        // travel direction in every block it holds. Within a segment the next item always starts
        // in the train's direction (a loop closure is handled when the front crosses it).
        if try await trainController.trainDirection(train) != nextItem.fromDirection {
            try await trainController.setTrainDirection(train, direction: nextItem.fromDirection)
            await stateService.reverseTravelDirection(of: train)
        }

        // Allocate resources to the next block
        if let blockingResource = try await reserveOrRun(nextItem) {
            // A stationary train that may already be at or past its end of block sensor would not see it to
            // stop at: at the route start, or stopped at the sensor that is the end of the block in the
            // direction it now leaves (after a reversal the end is the other end, which it will reach).
            // Stay stopped until the resource is freed
            var isPastEndSensor: Bool {
                if isRouteStart { return true }
                if case .stoppedAtSensor(let sensor) = trainState {
                    return sensor.block == nextItem.fromBlock && sensor.location.isEnd(nextItem.fromDirection)
                }
                return false
            }
            if isPastEndSensor {
                try await stopForResource(blockingResource, item: nextItem)
                return
            }
            try await stateService.setStateForTrain(train, state: .stoppingForResource(blockingResource))
        } else {
            // Set the points on this path without default values
            for setting in nextItem.pointSettings where setting.point.defaultPosition == nil {
                // Don't override default positions e.g. on virtual back/back points
                try await stateService.setDirectionForPoint(setting.point, newDirection: setting.direction)
            }
        }
        
        // Set the speed for the new block
        try await setTrainSpeed(inBlock: nextItem.fromBlock)
    }
    
    // Work out the next path item for the front of the train: the first item of the path from the
    // block the front is entering to the end of the segment, or at the end of a segment the first item
    // of the next segment. Nil at the end of the route.
    private func nextFrontPathItem() async throws -> PathItem? {
        var segmentIndex = frontSegmentIndex
        let fromBlock: Block
        let direction: BlockDirection
        if let frontItem, frontItem.toBlock != frontItemEndBlock {
            // Carry on along the segment
            fromBlock = frontItem.toBlock
            direction = frontItem.toDirection
        } else {
            if let frontItem {
                // End of the segment: move on to the next one, starting where this one ended
                guard segmentIndex + 1 < route.segments.count else { return nil }
                segmentIndex += 1
                fromBlock = frontItem.toBlock
            } else {
                guard let startBlock else { throw TrainError.noStartBlockForRoute(route.id) }
                fromBlock = startBlock
            }
            direction = route.segments[segmentIndex].direction
        }

        // Change the segment only after the path search, which awaits the track state
        let (item, endBlock) = try await pathItem(from: fromBlock, direction: direction, segmentIndex: segmentIndex)
        frontSegmentIndex = segmentIndex
        frontItemEndBlock = endBlock
        return item
    }

    // The first item of a path from the block in the given direction to the end of the segment that keeps
    // clear of other trains, and the block it ends in. The segment's toBlock if there is a clear path to it,
    // otherwise the first of its alternative end blocks with one (and from which the route can continue).
    // If there is none, the shortest path to toBlock (the train then waits for the resource).
    private func pathItem(from fromBlock: Block, direction: BlockDirection, segmentIndex: Int) async throws -> (item: PathItem, endBlock: Block) {
        let snapshot = await stateService.snapshot()
        let toBlock = route.segments[segmentIndex].toBlock
        let isBlocked = { (blockRoute: Layout.BlockRoute) in snapshot.isBlocked(blockRoute, for: self.train) }

        // path() throws if there is no route, so the path has at least one item
        let shortestPath = try layout.path(fromBlock: fromBlock, toBlock: toBlock, direction: direction)
        if let clearPath = try? layout.path(fromBlock: fromBlock, toBlock: toBlock, direction: direction, isBlocked: isBlocked) {
            if clearPath != shortestPath {
                log.info("\(rd): Avoiding other trains: path to \(toBlock) is \(clearPath.pathItems) instead of \(shortestPath.pathItems)")
            }
            log.verbose("\(rd): Path to \(toBlock) is \(clearPath.pathItems)")
            return (clearPath.pathItems[0], toBlock)
        }
        
        for alternative in layout.alternativeEndBlocks[toBlock] ?? [] {
            // The next segment must be able to start from the alternative, without coming back through the
            // block being left or the block it stands in for (the train would go round to where it started)
            if segmentIndex + 1 < route.segments.count {
                guard let continuation = try? route.segments[segmentIndex + 1].nominalPath(from: alternative, in: layout) else { continue }
                if continuation.pathItems.dropLast().contains(where: { $0.toBlock == fromBlock || $0.toBlock == toBlock }) {
                    log.verbose("\(rd): Not using \(alternative) for \(toBlock): next segment goes back through \(fromBlock) or \(toBlock)")
                    continue
                }
            }
            if let clearPath = try? layout.path(fromBlock: fromBlock, toBlock: alternative, direction: direction, isBlocked: isBlocked) {
                log.info("\(rd): No clear path to \(toBlock): going to \(alternative) instead, path \(clearPath.pathItems)")
                return (clearPath.pathItems[0], alternative)
            }
        }
        
        log.verbose("\(rd): No path to \(toBlock) clear of other trains, taking \(shortestPath.pathItems)")
        return (shortestPath.pathItems[0], toBlock)
    }
    
    private func requestPathItem(_ item: PathItem) async throws -> RouteState {
        if let blockingResource = try await reserveOrRun(item) {
            // Stop the train if it is moving (normally stopped) and wait for the resource to be freed
            try await stopForResource(blockingResource, item: item)
            return routeState       // Still waiting: leave the route state unchanged
        }
        
        // No blocking resource: update the state to reflect the new item
        try await stateService.setStateForBlock(item.fromBlock, newState : .occupied(train, item.fromDirection))
        try await setTrainSpeed(inBlock: item.fromBlock)
        
        return .active
    }
    
    // Try to reserve the path item, returning the blocking resource if the reservation failed.
    // Otherwise set the speed for the path item, mark the train running and return nil
    private func reserveOrRun(_ item: PathItem) async throws -> TrackResource? {
        if let blockingResource = try await stateService.reservePathItem(item, forTrain: train) {
            return blockingResource
        }
        
        // No blocking resource - just carry on
        // Power the route
        try await setTrainSpeed(inBlock: item.fromBlock)
        try await setTrainState(.running(item))
        return nil
    }
    
    // The train has exited the toBlock on the rear path item
    private func processVacatedBlock(train: Train, block: Block) async throws {
        guard try await stateService.trainForBlock(block) == train else {
            throw TrainError.applicationError("Train \(train) is not valid for vacated block \(block)")
        }
        
        // Free the block and remove the direction lock
        try await stateService.setStateForBlock(block, newState: .vacant)
        try await stateService.releaseDirectionLock(block: block, train: train)
        
        // The rear moves on to the next path item
        rearItems.removeFirst()
    }
        
    // Return if valid or throw if not
    private func validStateForStart(route: Route) async throws {
        switch routeState {
        case .dormant, .ended:
            return          // Never run, or finished: the route starts where the train is
            
        case .starting, .active:          // Unexpected
            throw TrainError.invalidRoute("\(rd): \(route): Run route \(route.id) but already in running state")
        case .error:
            throw TrainError.invalidRoute("\(rd): \(route): Attempt to run route in error state")
        case .ending:
            throw TrainError.invalidRoute("\(rd): \(route): Attempt to run route in ending state")
        }
    }
}
