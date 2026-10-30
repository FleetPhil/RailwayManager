import Foundation

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

    // True if another train is in the way of the block route: its toBlock is reserved, occupied or vacating
    // by another train or locked by one for the opposite direction, or one of its points is reserved by
    // another train. The train's own blocks and points don't count. Used to find a path round other trains;
    // reservePathItem() still makes the final check (including the blocks contiguous beyond toBlock).
    func isBlocked(_ blockRoute: Layout.BlockRoute, for train: Train) -> Bool {
        if let holder = blockStates[blockRoute.toBlock]?.train, holder != train {
            return true
        }
        if directionLocks[blockRoute.toBlock]?.contains(where: { $0.train != train && $0.direction != blockRoute.toDirection }) == true {
            return true
        }
        return blockRoute.pointSettings.contains(where: { setting in
            reservedTrainForPoint(setting.point).map({ $0 != train }) ?? false
        })
    }
}
