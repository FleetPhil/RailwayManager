import Foundation


enum BlockRuntimeState: Equatable {
    case vacant
    case reserved(Train)
    case occupied(Train)
    case vacating(Train)
    
    var isVacant: Bool {
        switch self {
        case .vacant:   true
        default:        false
        }
    }
    
    var train: Train? {
        switch self {
        case .reserved(let train), .occupied(let train), .vacating(let train):  train
        case .vacant: nil
        }
    }
    
    var vacatingTrain: Train? {
        switch self {
        case .vacant, .reserved, .occupied:     return nil
        case .vacating(let train):              return train
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
}



actor LayoutTrackStateService {
    private var blockStates: [Block: BlockRuntimeState] = [:]
    private var pointStates: [Point : PointRuntimeState] = [:]
    private var signalStates: [Signal : SignalState] = [:]
    
    let trainController = LayoutTrainController()
    
    private let layout: Layout
    
    // The trains that have direction locks for each block
    private var directionLocks: [Block : [Train]] = [:]
    
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
        for point in layout.points {
            try await resetPoint(point)
        }
        
        signalStates = layout.signals.reduce(into: [:], { result, signal in
            result[signal] = .init(.off)
        })
        
        // Send MQTT updates
        for block in layout.blocks {
            try? await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: .vacant)
        }

        for signal in layout.signals {
            try? await MQTTManager.shared.sendSignalState(signal: signal, state: .off)
        }
    }

    func signalState(_ signal: Signal) -> SignalState {
        signalStates[signal] ?? .off
    }
    
    func setSignalState(_ signal: Signal, _ state: SignalState) {
        log.verbose("Signal \(signal) changed from \(signalStates[signal] ?? .off) to \(state)")
        signalStates[signal] = state
    }

    func blockState(_ block: Block) -> BlockRuntimeState? {
        blockStates[block]
    }
    
    func setDirectionForVacantContiguousBlocks(fromBlock: Block, train: Train, direction: Direction) async throws {
        for vacantBlock in layout.contiguousBlocks(fromBlock: fromBlock, direction: direction)
        .filter({ blockState($0)?.isVacant ?? true }) {
            try await setDirectionLock(block: vacantBlock, train: train)
        }
    }
    
    func setStateForTrain(_ train: Train, state: TrainRuntimeState) async throws {
        
        if await trainController.isNewTrain(train) {
            log.verbose("Train \(train) state request from none) to \(state)")
        } else {
            let oldState = try await trainController.trainState(train)
            log.verbose("Train \(train) state request from \(oldState, default: "none") to \(state)")
        }
        
        await trainController.setTrainState(train, state: state)
    }
    
    func setStateForBlock(_ block: Block, newState: BlockRuntimeState) async throws {
        let oldState = blockStates[block] ?? .vacant
        
        guard oldState != newState else { return }
        log.verbose("Block \(block) state request from \(oldState) to \(newState)")

        switch newState {
        case .vacant:
            if !oldState.isVacant {
                blockStates[block] = newState
                if let train = blockStates[block]?.train {
                    try releaseDirectionLock(block: block, train: train)
                }
                await LayoutEventHub.shared.publish(.didFreeResource(.block(block)))
            }

        case .reserved(let reservedTrain):
            switch oldState {
            case .vacant:
                // Clear any locks from this block for this train
                try releaseDirectionLock(block: block, train: reservedTrain)

            case .reserved(let previousReservedTrain):
                if previousReservedTrain == reservedTrain {
                    // Duplicate
                    break
                } else {
                    throw TrainError.invalidBlockStateChange("Can't reserve \(block) for \(reservedTrain), reserved by \(previousReservedTrain)")
                }
                
            case .occupied(let train), .vacating(let train):
                throw TrainError.invalidBlockStateChange("Can't reserve occupied/vacating block \(block). \(train)")
            }
            blockStates[block] = newState

        case .occupied(let newTrain):
            switch oldState {
            case .vacant:
                log.warning("Train \(newTrain) occupies vacant block \(block)")
                
            case .reserved:
                break
                
            case .occupied(let oldTrain):
                if oldTrain != newTrain {
                    throw TrainError.invalidBlockStateChange("Train \(newTrain) can't occupy \(block): occupied by \(oldTrain)")
                }

            case .vacating(let oldTrain):
                if oldTrain != newTrain {
                    throw TrainError.invalidBlockStateChange("Train \(newTrain) can't vacate \(block): occupied by \(oldTrain)")
                }

            }
            blockStates[block] = newState
            
            if oldState.train != newTrain {
                // Block stays occupied but train changed
                await LayoutEventHub.shared.publish(.didOccupyBlock(block, newTrain))
            }
            
        case .vacating(let vacatingTrain):
            switch oldState {
            case .vacant, .reserved:
                break
            case .occupied(let train), .vacating(let train):
                if train != vacatingTrain {
                    throw TrainError.applicationError(25)
                }
            }
            blockStates[block] = newState
        }
        
        
        
        let trainState = newState.train == nil ? nil : try await trainController.trainState(newState.train!)
        try await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: newState, trainState:trainState)
    }
    
    func releaseDirectionLock(block: Block, train: Train) throws {
        // Release any direction lock for this train and block
        guard let locks = directionLocks[block] else { return }
        
        if locks.contains(train) {
            if let trainIndex = locks.firstIndex(of: train) {
                directionLocks[block]!.remove(at: trainIndex)
                if directionLocks[block]!.isEmpty {
                    directionLocks[block] = nil
                }
            } else {
                throw TrainError.noLockToRelease(block, train)
            }
        }
    }

    func setDirectionLock(block: Block, train: Train) async throws {
        // Set the direction lock for this train and block - which must not exist
        if let locks = directionLocks[block] {
            if locks.contains(train) {
                throw TrainError.lockAlreadyExists(block, train)
            } else {
                // Check the direction on current locks
                let currentLockedDirection = try await trainController.trainDirection(locks.first!)
                let trainDirection = try await trainController.trainDirection(train)
                
                if currentLockedDirection == trainDirection {
                    directionLocks[block]!.append(train)
                } else {
                    throw TrainError.applicationError(23)
                }
            }
        } else {
            // No current locked direction
            directionLocks[block, default: []].append(train)
        }
    }

    // Path Item is a block-block transition, maybe involving 1 or more points
    // This function is called when the next transition is required
    func reservePathItem(_ item: PathItem, forTrain: Train) async throws -> TrackResource? {
        switch blockStates[item.toBlock] {
        case .vacant, .vacating:
            break
        case .occupied:
            log.debug("Route \(forTrain.id) reserve fails: \(item.toBlock) state is occupied")
            return .block(item.toBlock)
        case .reserved(let train):
            if train != forTrain {
                log.debug("Train \(forTrain) reserve fails: \(item) state is reserved for \(train)")
                return .block(item.toBlock)
            }

        case .none:
            break
        }
        
        // Check any opposite direction locks on contiguous blocks
        let trainDirection = try await trainController.trainDirection(forTrain)
        let contiguousBlocks = layout.contiguousBlocks(fromBlock: item.toBlock, direction: trainDirection)
        for contiguousBlock in contiguousBlocks {
            if let locks = directionLocks[contiguousBlock] {
                let lockedTrainDirection = try await trainController.trainDirection(locks.first!)
                if lockedTrainDirection != trainDirection {
                    // Block is locked in opposite direction
                    log.verbose("Reserve fails for locked block \(contiguousBlock), direction \(lockedTrainDirection)")
                    return .block(item.toBlock)
                }
            }
        }
        
        // Check none of the points on the path are reserved
        if let reservedPoint = item.pointSettings.first(where: {
            reservedTrainForPoint($0.point) != nil
        }) {
            return .point(reservedPoint.point)
        }

        try await setStateForBlock(item.toBlock, newState: .reserved(forTrain))
        try await setDirectionForVacantContiguousBlocks(fromBlock: item.toBlock, train: forTrain, direction: trainDirection)
        
        
        for pointID in item.pointSettings.map( \.point ) {
            try await setReservedTrainForPoint(pointID, to: forTrain, associatedStartBlock: item.fromBlock)
        }
        
        for pointSetting in item.pointSettings {
            try await pointSetting.point.setDirection(pointSetting.direction)
        }
        
        return nil
    }
    
    func vacatingBlockForTrain(_ train: Train) -> Block? {
        blockStates.first(where: { $0.value == .vacating(train) })?.key
    }

    func processSensorSetEvent(sensor: Sensor, trainSensor: TrainSensor) async throws {
        guard let blockState = blockStates[sensor.block] else { throw TrainError.applicationError(10) }
        guard let train = blockState.train else { throw TrainError.noTrainForSetSensor(sensor.id) }
        let trainDirection = try await trainController.trainDirection(train) 
        
        // The train end is relative to the train moving forward, so adjust if the block direction is reverse
        let trainDirectionSensor: TrainSensor = trainDirection == .forward ? trainSensor : trainSensor.oppositePosition

        log.verbose("Sensor \(sensor.id) (\(sensor.location)) (\(trainDirection)) for train posn \(trainDirectionSensor)")
        
        switch (sensor.location.isStart, trainDirectionSensor) {
        case (true, .front):
            // Front of the train sets the first or only sensor in the block
            switch blockState {
            case .reserved(let train):
                guard let currentBlockForTrain = occupiedBlockForTrain(train) else {
                    throw TrainError.noCurrentBlockForTrainSensor(sensor.id)
                }
                
                // Occupy this block
                try await setStateForBlock(sensor.block, newState: .occupied(train))
                
                // Previous block will be freed when trailing sensor passes over 
            case .occupied:
                break
            default:
                log.verbose("Sensor \(sensor) set on block \(sensor.block) in state \(blockState)")
            }
            
        case (true, .rear):
            if let vacatingBlock = vacatingBlockForTrain(train) {
                try await setStateForBlock(vacatingBlock, newState: .vacant)
            } else {
                throw TrainError.invalidBlockStateChange("No block for train \(train) to vacate at sensor \(sensor.id)")
            }
            
        default:
            break
        }
    }
    
    func setDirectionForPointID(_ id: Int, newDirection: PointDirection) async throws {
        try await setDirectionForPoint(layout.point(id), newDirection: newDirection)
    }
    
    func setDirectionForPoint(_ point: Point, newDirection: PointDirection) async throws {
        if pointStates[point]?.direction == newDirection { return }         // No change
        
        log.info("Point \(point.id) set to \(newDirection)")
        
        var newState = pointStates[point]!
        newState.direction = newDirection
        pointStates[point] = newState
        
        try await point.setDirection(newDirection)

        // Send to MQTT
        try await MQTTManager.shared.sendPointState(point: point, state: newDirection)
    }
    
    // Reset point to default condition or straight
    func resetPoint(_ point: Point) async throws {
        try await setDirectionForPoint(point, newDirection: point.defaultPosition ?? .splitStraight)
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

struct LayoutTrackSnapshot: Sendable {
    internal init(trainStates: [ Train : TrainRuntimeState],
                  trainDirections: [Train : Direction],
                  blockStates: [Block : BlockRuntimeState],
                  directionLocks: [Block: [Train]],
                  signalStates: [Signal : SignalState],
                  pointStates: [ Point : PointRuntimeState]) {
        self.blockStates = blockStates
        self.trainStates = trainStates
        self.trainDirections = trainDirections
        self.signalStates = signalStates
        self.pointStates = pointStates
        self.directionLocks = directionLocks
    }
    
    private let blockStates: [Block: BlockRuntimeState]
    private let directionLocks: [Block: [Train]]
    private let trainStates: [Train: TrainRuntimeState]
    private let trainDirections: [Train: Direction]
    private let signalStates: [Signal : SignalState]
    private let pointStates: [ Point : PointRuntimeState]

    var allBlocks: [Block] { Array(blockStates.keys) }
    var allTrains: [Train] { Array(trainStates.keys) }
    var allSignals: [Signal] { Array(signalStates.keys) }
    var allPoints: [Point] { Array(pointStates.keys) }

    func blockState(_ block: Block) -> BlockRuntimeState? { blockStates[block] }
    func directionLocks(_ block: Block) -> [Train]? { directionLocks[block] }
    func trainState(_ train: Train) -> TrainRuntimeState? { trainStates[train] }
    func signalState(_ signal: Signal) -> SignalState? { signalStates[signal] }
    func pointState(_ point: Point) -> PointRuntimeState? { pointStates[point] }

    func reservedTrainForPoint(_ point: Point) -> Train? {
        return pointStates[point]?.reservedByTrain
    }
    
    // Return the current direction for the block
    func blockDirection(block: Block) -> Direction? {
        if let train = blockState(block)?.train {
            return trainDirections[train]
        } else {
            return nil
        }
    }
}

    // Snapshot for read-only events, e.g. set signals, print status
extension LayoutTrackStateService {
    func snapshot() async -> LayoutTrackSnapshot {
        LayoutTrackSnapshot(trainStates: await trainController.trainStates,
                            trainDirections: await trainController.trainDirections,
                            blockStates: blockStates,
                            directionLocks: directionLocks,
                            signalStates: signalStates,
                            pointStates: pointStates)
    }
}
