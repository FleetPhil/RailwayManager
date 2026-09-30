import Foundation


// A train's state in a block, with the train's travel direction in that block
// (a train part-way round a reversing loop travels in different directions in different blocks)
enum BlockRuntimeState: Equatable {
    case vacant
    case reserved(Train, BlockDirection)
    case occupied(Train, BlockDirection)
    case vacating(Train, BlockDirection)
    
    var isVacant: Bool {
        switch self {
        case .vacant:   true
        default:        false
        }
    }
    
    var train: Train? {
        switch self {
        case .reserved(let train, _), .occupied(let train, _), .vacating(let train, _):  train
        case .vacant: nil
        }
    }
    
    var direction: BlockDirection? {
        switch self {
        case .reserved(_, let direction), .occupied(_, let direction), .vacating(_, let direction):  direction
        case .vacant: nil
        }
    }
    
    // The same state with the travel direction reversed (the train has changed direction)
    var reversed: BlockRuntimeState {
        switch self {
        case .vacant:                                   .vacant
        case .reserved(let train, let direction):       .reserved(train, direction.oppositeDirection)
        case .occupied(let train, let direction):       .occupied(train, direction.oppositeDirection)
        case .vacating(let train, let direction):       .vacating(train, direction.oppositeDirection)
        }
    }
    
    var vacatingTrain: Train? {
        switch self {
        case .vacant, .reserved, .occupied:     return nil
        case .vacating(let train, _):           return train
        }
    }
}

struct PointRuntimeState: CustomStringConvertible, Sendable, Equatable {
    var direction: PointDirection
    var reservedByTrain: Train?
    var freeWithBlock: Block?           // When the block frees then free the point as well
    
    var description: String {
        var result = "\(direction)"
        if let reservedByTrain { result.append(", reserved \(reservedByTrain)") }
        if let freeWithBlock { result.append(", free with \(freeWithBlock)") }
        return result
    }
    
    // Return a new struct with just the direction changed
    func newStateWithDirection(_ direction: PointDirection) -> Self {
        return PointRuntimeState(direction: direction,
                                 reservedByTrain: self.reservedByTrain,
                                 freeWithBlock: self.freeWithBlock)
    }
}

actor LayoutTrackStateService {
    private var blockStates: [Block: BlockRuntimeState] = [:]
    private var pointStates: [Point : PointRuntimeState] = [:]
    private var signalStates: [Signal : (SignalState, SignalState)] = [:]
    
    let trainController = LayoutTrainController()
    
    private let layout: Layout
    
    // The direction locks for each block: a train that expects to travel through the block in that direction
    private var directionLocks: [Block : [DirectionLock]] = [:]
    
    // The trains holding direction locks on a block (for telemetry)
    private func lockedTrains(_ block: Block) -> [Train] {
        directionLocks[block]?.map(\.train) ?? []
    }
    
    init(layout: Layout) {
        self.layout = layout
    }

    // Set defaults for block and point states
    func reset() async throws {
        blockStates = layout.blocks.reduce(into: [:]) { result, block in
            result[block] = .vacant
        }
        
        pointStates = layout.points.reduce(into: [:], { result, point in
            result[point] = .init(direction: .single, reservedByTrain: nil)
            
        })
        
        // Reset all points to default position or straight
        for point in layout.points {
            try await resetPoint(point)
        }
        
        signalStates = layout.signals.reduce(into: [:], { result, signal in
            result[signal] = .init((.off, .off))
        })
                
        // Send MQTT updates
        for block in layout.blocks {
            try? await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: .vacant)
        }

        for signal in layout.signals {
            try? await MQTTManager.shared.sendSignalState(signal: signal, state: .off)
        }
        
    }

    func signalState(_ signal: Signal) async throws -> (SignalState, SignalState) {
        // Force a refresh
        try await updateSignals()
        return signalStates[signal] ?? (.off, .off)
    }
    
    func setSignalState(_ signal: Signal, home: SignalState, distant: SignalState?) async throws {
        log.verbose("Signal \(signal) changed from \(signalStates[signal] ?? (.off, .off)) to \(home), \(distant ?? .off)")
        try await signal.setState(home: home, distant: distant ?? .off)
        signalStates[signal] = (home, distant ?? .off)
    }
    
    // Will not be called if layout is dormant
    func updateSignals() async throws {
        let snapshot = await snapshot()
        let signalStates = try SignalCoordinator.refresh(snapshot: snapshot)

        for changedSignal in signalStates {
            try await setSignalState(changedSignal.key,
                                     home: changedSignal.value.0,
                                     distant: changedSignal.value.1)
            // Telemetry: a publish failure must not fail the signal update
            try? await MQTTManager.shared.sendSignalState(signal: changedSignal.key, state: changedSignal.value.0)
        }
    }

    func blockState(_ block: Block) -> BlockRuntimeState? {
        blockStates[block]
    }
    
    // Return the train currently in this block
    func trainForBlock(_ block: Block) throws -> Train? {
        guard let blockState = blockStates[block] else {
            throw TrainError.applicationError("No state for block \(block)")
        }
        switch blockState {
        case .occupied(let train, _), .reserved(let train, _), .vacating(let train, _): return train
        default: return nil
        }
    }
    
    func setDirectionForVacantContiguousBlocks(fromBlock: Block, train: Train, direction: BlockDirection) async throws {
        for (vacantBlock, blockDirection) in layout.contiguousBlocks(fromBlock: fromBlock, direction: direction)
        where blockState(vacantBlock)?.isVacant ?? true {
            try await setDirectionLock(block: vacantBlock, train: train, direction: blockDirection)
        }
    }
    
    func setStateForTrain(_ train: Train, state: TrainRuntimeState) async throws {
        
        if await trainController.isNewTrain(train) {
            log.verbose("Train \(train) state request from none to \(state)")
        } else {
            let oldState = try await trainController.trainState(train)
            if oldState == state { return }
            
            log.verbose("Train \(train) state request from \(oldState, default: "none") to \(state)")
        }
        
        try await trainController.setTrainState(train, state: state)
    }
    
    // Validate the transition and set the new state
    // Return true for valid transition, false for invalid
    func setStateForBlock(_ block: Block, newState: BlockRuntimeState) async throws {
        let oldState = blockStates[block] ?? .vacant
        
        // Ignore
        guard oldState != newState else { return }
        log.debug("Block \(block) state request from \(oldState) to \(newState)")

        switch newState {
        case .vacant:
            if !oldState.isVacant {
                blockStates[block] = newState
                // Release the lock held by the train that was in the block
                if let train = oldState.train {
                    try await releaseDirectionLock(block: block, train: train)
                }
                await LayoutEventHub.shared.publish(.didFreeResource(.block(block)))
            }

        case .reserved(let reservedTrain, _):
            switch oldState {
            case .vacant:
                // Clear any locks from this block for this train
                try await releaseDirectionLock(block: block, train: reservedTrain)

            case .reserved(let previousReservedTrain, _):
                if previousReservedTrain == reservedTrain {
                    // Same train: only the direction can have changed
                    break
                } else {
                    throw TrainError.invalidBlockStateChange("Can't reserve \(block) for \(reservedTrain), reserved by \(previousReservedTrain)")
                }
                
            case .occupied(let train, _), .vacating(let train, _):
                throw TrainError.invalidBlockStateChange("Can't reserve occupied/vacating block \(block). \(train)")
            }
            blockStates[block] = newState

        case .occupied(let newTrain, _):
            switch oldState {
            case .vacant:
                log.info("Train \(newTrain) occupies vacant block \(block)")
                
            case .reserved:
                break
                
            case .occupied(let oldTrain, _):
                if oldTrain != newTrain {
                    throw TrainError.invalidBlockStateChange("Train \(newTrain) can't occupy \(block): occupied by \(oldTrain)")
                }

            case .vacating(let oldTrain, _):
                if oldTrain != newTrain {
                    throw TrainError.invalidBlockStateChange("Train \(newTrain) can't vacate \(block): occupied by \(oldTrain)")
                }

            }
            blockStates[block] = newState
            
            if oldState.train != newTrain {
                // Block stays occupied but train changed
                await LayoutEventHub.shared.publish(.didOccupyBlock(block, newTrain))
            }
            
        case .vacating(let vacatingTrain, _):
            switch oldState {
            case .vacant:
                log.warning("Train \(vacatingTrain) can't vacate \(block): block is vacant")
                // No further action
            case .reserved:
                throw TrainError.invalidBlockStateChange("Train \(vacatingTrain) can't vacate reserved block \(block)")
            case .occupied(let train, _), .vacating(let train, _):
                if train != vacatingTrain {
                    throw TrainError.invalidBlockStateChange("Train \(vacatingTrain) can't vacate \(block): in use by \(train)")
                }
            }
            blockStates[block] = newState
        }
        
        // Telemetry: a publish failure must not fail the state change
        try? await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: newState)
    }
    
    // The train has changed direction: reverse its travel direction in every block it holds
    func reverseTravelDirection(of train: Train) {
        for (block, state) in blockStates where state.train == train {
            blockStates[block] = state.reversed
            log.debug("Block \(block) state reversed to \(state.reversed)")
        }
    }
    
    func releaseDirectionLock(block: Block, train: Train) async throws {
        // Release any direction lock for this train and block
        guard let locks = directionLocks[block] else { return }
        
        if let trainIndex = locks.firstIndex(where: { $0.train == train }) {
            directionLocks[block]!.remove(at: trainIndex)
            if directionLocks[block]!.isEmpty {
                directionLocks[block] = nil
            }
            
            // Publish change
            try? await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: blockStates[block]!, directionLocks: lockedTrains(block))
        }
    }

    func setDirectionLock(block: Block, train: Train, direction: BlockDirection) async throws {
        // Set the direction lock for this train and block - which must not exist
        let locks = directionLocks[block] ?? []
        if locks.contains(where: { $0.train == train }) {
            throw TrainError.lockAlreadyExists(block, train)
        }
        if locks.contains(where: { $0.direction != direction }) {
            throw TrainError.applicationError("Can't lock block \(block) for train \(train): locked in opposite direction")
        }
        directionLocks[block, default: []].append(DirectionLock(train: train, direction: direction))
        
        // Publish change
        try? await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: .vacant, directionLocks: lockedTrains(block))
    }

    // Path Item is a block-block transition, maybe involving 1 or more points
    // This function is called when the next transition is required
    func reservePathItem(_ item: PathItem, forTrain: Train) async throws -> TrackResource? {
        // MARK: Critical section: no awaits until all resources are marked reserved
        let oldState = blockStates[item.toBlock] ?? .vacant
        switch oldState {
        case .vacant:
            break
        case .occupied(let train, _), .vacating(let train, _):
            log.debug("Route \(forTrain.id) reserve fails: \(item.toBlock) state is occupied/vacating by \(train)")
            return .block(item.toBlock)
        case .reserved(let train, _):
            if train != forTrain {
                log.debug("Train \(forTrain) reserve fails: \(item) state is reserved for \(train)")
                return .block(item.toBlock)
            }
        }
        
        // Check for other trains' direction locks against the travel direction in each contiguous block.
        // The train's own locks are ignored: they may be left from before it last reversed.
        let contiguousBlocks = layout.contiguousBlocks(fromBlock: item.toBlock, direction: item.toDirection)
        for (contiguousBlock, blockDirection) in contiguousBlocks {
            if let lock = directionLocks[contiguousBlock]?.first(where: { $0.train != forTrain && $0.direction != blockDirection }) {
                // Block is locked in opposite direction
                log.verbose("Reserve fails for locked block \(contiguousBlock), direction \(lock.direction)")
                return .block(item.toBlock)
            }
        }
        
        // Check none of the points on the path are reserved
        if let reservedPoint = item.pointSettings.first(where: {
            reservedTrainForPoint($0.point) != nil
        }) {
            return .point(reservedPoint.point)
        }

        // All checks passed: mark the block, direction locks and points reserved
        log.verbose("Block \(item.toBlock) state request from \(oldState) to \(BlockRuntimeState.reserved(forTrain, item.toDirection))")
        if oldState.isVacant {
            // Clear any existing lock on this block for this train
            try await releaseDirectionLock(block: item.toBlock, train: forTrain)
        }
        blockStates[item.toBlock] = .reserved(forTrain, item.toDirection)
        
        for (vacantBlock, blockDirection) in contiguousBlocks where blockStates[vacantBlock]?.isVacant ?? true {
            if directionLocks[vacantBlock]?.contains(where: { $0.train == forTrain }) == true {
                throw TrainError.lockAlreadyExists(vacantBlock, forTrain)
            }
            // Lock directions were checked above, so the lock can be added
            try await setDirectionLock(block: vacantBlock, train: forTrain, direction: blockDirection)
        }
        
        for point in item.pointSettings.map( \.point ) {
            try await setReservedTrainForPoint(point, to: forTrain, associatedStartBlock: item.fromBlock)
        }
        // MARK: End critical section
        
        // Command the point hardware
        for pointSetting in item.pointSettings {
            try await setDirectionForPoint(pointSetting.point, newDirection: pointSetting.direction)
        }
        
        // Telemetry: a publish failure must not fail the reservation
        try? await MQTTManager.shared.sendBlockRuntimeState(block: item.toBlock, blockState: .reserved(forTrain, item.toDirection), directionLocks: lockedTrains(item.toBlock))
        
        return nil
    }
    
    // Override == true will set the direction regardless of the current setting (for reset)
    func setDirectionForPoint(_ point: Point, newDirection: PointDirection, override: Bool = false) async throws {
        if !override {
            if pointStates[point]?.direction == newDirection { return }         // No change
        }
        if newDirection == .single { return }                               // Ignore
        
        log.debug("Point \(point.id) set to \(newDirection)")
        
        guard let newState = pointStates[point]?.newStateWithDirection(newDirection) else {
            throw TrainError.unexpectedTrackState("No state for point \(point.id)")
        }
        pointStates[point] = newState
        
        try await point.setDirection(newDirection)

        // Telemetry: a publish failure must not fail the state change
        let associatedBlock = pointStates[point]?.freeWithBlock?.id
        try? await MQTTManager.shared.sendPointState(point: point, state: newDirection, associatedBlock: associatedBlock)
    }
    
    // Reset point to default condition or straight, override will set regardless of current stored state
    func resetPoint(_ point: Point) async throws {
        try await setDirectionForPoint(point, newDirection: point.defaultPosition ?? .splitStraight, override: true)
    }

    func setDefaultPositionforPoint(_ point: Point) async throws {
        if let defaultPosition = point.defaultPosition {
            try await setDirectionForPoint(point, newDirection: defaultPosition)
        }
    }

    func reservedTrainForPoint(_ point: Point) -> Train? {
        return pointStates[point]?.reservedByTrain
    }
    
    func setReserveTrainForPointID(_ id: Int, to: Train?, associatedStartBlock: Block?) async throws {
        try await setReservedTrainForPoint(layout.point(id), to: to, associatedStartBlock: associatedStartBlock)
    }

    func setReservedTrainForPoint(_ point: Point, to: Train?, associatedStartBlock: Block?) async throws {
        log.verbose("Point \(point) set to reserved \(to, default: "None")")

        if reservedTrainForPoint(point) != nil && to != nil {
            throw TrainError.invalidBlockStateChange("Point \(point.id) already reserved by train \(reservedTrainForPoint(point)!), cannot reserve for \(to!)")
        }

        
        pointStates[point]?.reservedByTrain = to
        pointStates[point]?.freeWithBlock = associatedStartBlock
        
        if to == nil {      // If point is freed
            if let defaultPosition = point.defaultPosition {
                do {
                    try await setDirectionForPoint(point, newDirection: defaultPosition)
                } catch {
                    log.warning("Failed to set point to default position")
                }
            }
        }
        
        // Send telemetry
        if let direction = pointStates[point]?.direction {
            try? await MQTTManager.shared.sendPointState(point: point, state: direction, associatedBlock: associatedStartBlock?.id)
        }
    }
    
    func associatedBlockForPoint(_ point: Point) -> Block? {
        return pointStates[point]?.freeWithBlock
    }
    
    func occupiedBlockForTrain(_ train: Train) -> Block? {
        blockStates.filter({ $0.value.train == train }).first?.key
    }
    
    // Return the next block entering the point from this direction or nil if the point is against us or error
    func nextActiveBlock(afterPoint: Point, entering: PointDirection) -> Block? {
        // Check if point is against us
        guard let currentDirection = pointStates[afterPoint]?.direction else { return nil }
        
        if entering == .splitBranch && currentDirection == .splitStraight { return nil }
        if entering == .splitStraight && currentDirection == .splitBranch { return nil }

        // Point is in our favour so find the next block
        // Find the exit from this point
        // If entering single it's the point direction, otherwise it's single
        let exitDirection = entering == .single ? currentDirection : .single
        
        // If the exist is another point then calculate the exit from that
        let connections = layout.point(afterPoint.id).connections
        
        switch connections[exitDirection] {
        case .block(let block):
            return block
        case .point(let point, let direction):
            return nextActiveBlock(afterPoint: point, entering: direction)
        case .none:
            return nil
        }
    }

}

// A train expecting to travel through a vacant block in the given direction.
// Another train can't enter the block in the opposite direction while it is held.
struct DirectionLock: Sendable, Equatable {
    let train: Train
    let direction: BlockDirection
}

struct LayoutTrackSnapshot: Sendable {
    internal init(trainStates: [ Train : TrainRuntimeState],
                  blockStates: [Block : BlockRuntimeState],
                  directionLocks: [Block: [DirectionLock]],
                  signalStates: [Signal : (SignalState, SignalState)],
                  pointStates: [ Point : PointRuntimeState]) {
        self.blockStates = blockStates
        self.trainStates = trainStates
        self.signalStates = signalStates
        self.pointStates = pointStates
        self.directionLocks = directionLocks
    }
    
    private let blockStates: [Block: BlockRuntimeState]
    private let directionLocks: [Block: [DirectionLock]]
    private let trainStates: [Train: TrainRuntimeState]
    private let signalStates: [Signal : (SignalState, SignalState)]
    private let pointStates: [ Point : PointRuntimeState]

    var allBlocks: [Block] { Array(blockStates.keys) }
    var allTrains: [Train] { Array(trainStates.keys) }
    var allSignals: [Signal] { Array(signalStates.keys) }
    var allPoints: [Point] { Array(pointStates.keys) }

    func blockState(_ block: Block) -> BlockRuntimeState? { blockStates[block] }
    func directionLocks(_ block: Block) -> [DirectionLock]? { directionLocks[block] }
    func trainState(_ train: Train) -> TrainRuntimeState? { trainStates[train] }
    func signalState(_ signal: Signal) -> (SignalState, SignalState)? { signalStates[signal] }
    func pointState(_ point: Point) -> PointRuntimeState? { pointStates[point] }

    func reservedTrainForPoint(_ point: Point) -> Train? {
        return pointStates[point]?.reservedByTrain
    }
    
    // Return the travel direction of the train reserving, occupying or vacating the block (nil if vacant)
    func travelDirection(in block: Block) -> BlockDirection? {
        blockState(block)?.direction
    }
}

    // Snapshot for read-only events, e.g. set signals, print status
extension LayoutTrackStateService {
    func snapshot() async -> LayoutTrackSnapshot {
        LayoutTrackSnapshot(trainStates: await trainController.trainStates,
                            blockStates: blockStates,
                            directionLocks: directionLocks,
                            signalStates: signalStates,
                            pointStates: pointStates)
    }
}
