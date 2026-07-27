import Foundation


enum BlockRuntimeState: Equatable {
    case vacant(Direction?)                 // Non nil if track section blocked for direction
    case reserved(Train, Direction)
    case occupied(Train, Direction)
    
    var direction: Direction? {
        switch self {
        case .reserved(_, let direction): direction
        case .occupied(_, let direction):  direction
        case .vacant(let direction): direction
        }
    }
    
    var isVacant: Bool {
        switch self {
        case .vacant:   true
        default:        false
        }
    }
    
    var train: Train? {
        switch self {
        case .reserved(let train, _), .occupied(let train, _):  train
        case .vacant: nil
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


struct LayoutTrackSnapshot: Sendable {
    internal init(trainStates: [ Train : TrainRuntimeState],
                  blockStates: [Block : BlockRuntimeState],
                  signalStates: [Signal : SignalState],
                  pointStates: [ Point : PointRuntimeState]) {
        self.blockStates = blockStates
        self.trainStates = trainStates
        self.signalStates = signalStates
        self.pointStates = pointStates
    }
    
    private let blockStates: [Block: BlockRuntimeState]
    private let trainStates: [Train: TrainRuntimeState]
    private let signalStates: [Signal : SignalState]
    private let pointStates: [ Point : PointRuntimeState]

    var allBlocks: [Block] { Array(blockStates.keys) }
    var allTrains: [Train] { Array(trainStates.keys) }
    var allSignals: [Signal] { Array(signalStates.keys) }
    var allPoints: [Point] { Array(pointStates.keys) }

    func blockState(_ block: Block) -> BlockRuntimeState? { blockStates[block] }
    func trainState(_ train: Train) -> TrainRuntimeState? { trainStates[train] }
    func signalState(_ signal: Signal) -> SignalState? { signalStates[signal] }
    func pointState(_ point: Point) -> PointRuntimeState? { pointStates[point] }

    func reservedTrainForPoint(_ point: Point) -> Train? {
        return pointStates[point]?.reservedByTrain
    }

}

actor LayoutTrackStateService {
    private var blockStates: [Block: BlockRuntimeState] = [:]
    private var pointStates: [Point : PointRuntimeState] = [:]
    private var signalStates: [Signal : SignalState] = [:]
    
    let trainController = LayoutTrainController()
    
    private let layout: Layout
    
    init(layout: Layout) {
        self.layout = layout
    }

    // Set defaults for block and point states
    func reset() async throws {
        blockStates = layout.blocks.reduce(into: [:]) { result, block in
            result[block] = .vacant(nil)
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
            try? await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: .vacant(nil))
        }

        for signal in layout.signals {
            try? await MQTTManager.shared.sendSignalState(signal: signal, state: .off)
        }
    }

    // Snapshot for read-only events, e.g. set signals, print status
    func snapshot() async -> LayoutTrackSnapshot {
        LayoutTrackSnapshot(trainStates: await trainController.trainStates,
                            blockStates: blockStates,
                            signalStates: signalStates,
                            pointStates: pointStates)
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
    
    func directionForBlock(_ block: Block) -> Direction? {
        blockStates[block]?.direction
    }
    
    func setDirectionForVacantContiguousBlocks(fromBlock: Block, direction: Direction) {
        for vacantBlock in layout.contiguousBlocks(fromBlock: fromBlock, direction: direction)
        .filter({ blockState($0)?.isVacant ?? false }) {
            blockStates[vacantBlock] = .vacant(direction)
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
        let oldState = blockStates[block] ?? .vacant(nil)
        
        guard oldState != newState else { return }
        log.verbose("Block \(block) state request from \(oldState) to \(newState)")

        switch newState {
        case .vacant:
            if !oldState.isVacant {
                blockStates[block] = newState
                await LayoutEventHub.shared.publish(.didFreeResource(.block(block)))
            }

        case .reserved:
            switch oldState {
            case .vacant, .reserved:
                break
            case .occupied(let oldRoute, let state):
                throw TrainError.invalidBlockStateChange("Can't reserve occupied block \(block). \(oldRoute), \(state)")
            }
            blockStates[block] = newState

        case .occupied(let newTrain, _):
            switch oldState {
            case .vacant:
                log.warning("Train \(newTrain) occupies vacant block \(block)")
                
            case .reserved:
                break
                
            case .occupied(let oldTrain, let state):
                if oldTrain != newTrain {
                    throw TrainError.invalidBlockStateChange("Train \(newTrain) can't occupy \(block): occupied by \(oldTrain), \(state)")
                }
            }
            blockStates[block] = newState
            
            if oldState.train != newTrain {
                // Block stays occupied but train changed
                await LayoutEventHub.shared.publish(.didOccupyBlock(block, newTrain))
            }
        }
        
        let trainState = newState.train == nil ? nil : try await trainController.trainState(newState.train!)
        try await MQTTManager.shared.sendBlockRuntimeState(block: block, blockState: newState, trainState:trainState)
    }

    // Path Item is a block-block transition, maybe involving 1 or more points
    // This function is called when the next transition is required
    func reservePathItem(_ item: PathItem, forTrain: Train) async throws -> TrackResource? {
        switch blockStates[item.toBlock] {
        case .vacant:
            break
        case .occupied:
            log.debug("Route \(forTrain.id) reserve fails: \(item.toBlock) state is occupied")
            return .block(item.toBlock)
        case .reserved(let train, _):
            if train != forTrain {
                log.debug("Train \(forTrain) reserve fails: \(item) state is reserved for \(train)")
                return .block(item.toBlock)
            }

        case .none:
            break
        }
        
        // Check none of the points on the path are reserved
        if let reservedPoint = item.pointSettings.first(where: {
            reservedTrainForPoint($0.point) != nil
        }) {
            return .point(reservedPoint.point)
        }

        let trainDirection = try await trainController.trainDirection(forTrain)
        try await setStateForBlock(item.toBlock, newState: .reserved(forTrain, trainDirection))
        
        for pointID in item.pointSettings.map( \.point ) {
            try await setReservedTrainForPoint(pointID, to: forTrain, associatedStartBlock: item.fromBlock)
        }
        
        for pointSetting in item.pointSettings {
            try await pointSetting.point.setDirection(pointSetting.direction)
        }
        
        return nil
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
            case .reserved(let train, _):
                guard let currentBlockForTrain = occupiedBlockForTrain(train) else {
                    throw TrainError.noCurrentBlockForTrainSensor(sensor.id)
                }
                
                // Occupy this block
                try await setStateForBlock(sensor.block, newState: .occupied(train, trainDirection))
                
                // Free previously occupied block
                try await setStateForBlock(currentBlockForTrain, newState: .vacant(nil))
            case .occupied:
                break
            default:
                log.verbose("Sensor \(sensor) set on block \(sensor.block) in state \(blockState)")
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
