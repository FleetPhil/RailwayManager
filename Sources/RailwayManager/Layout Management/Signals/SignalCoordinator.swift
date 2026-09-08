import Foundation

actor SignalCoordinator {
    // Refresh the signal state and return all changes
    static func refresh(snapshot: LayoutTrackSnapshot) throws -> [ Signal : (SignalState, SignalState)] {
        
        // Set initial state on all signals
        var homeState: [ Signal : SignalState] = [:]
        var distantState: [ Signal : SignalState] = [:]
        for signal in snapshot.allSignals {
            let signalIndication = signal.signalIndication(snapshot: snapshot)
            
            homeState[signal] = translate(signalIndication)
            distantState[signal] = .off     // Default value
        }
        // Now check state of turnouts and next blocks for all green signals
        for signal in homeState.filter({ $0.value == .go }).keys {
            // Check if the route out of this block contains any diverging signals before the next block
            // If so set the signal state to right or left (initial direction)
            if let divergingDirection = divergingDirection(signal, snapshot) {
                homeState[signal] = divergingDirection
            }

            // Find a signal in the next block indicating the same direction
            // if it is set to red update the current signal distant state
            let nextBlock = signal.nextBlock(snapshot: snapshot)
            if let signalForBlock = snapshot.allSignals.first(where: {
                $0.location == nextBlock && $0.direction == signal.direction
            }) {
                distantState[signal] = homeState[signalForBlock]
            }
        }
        
        let changedSignals = homeState.filter({
            if let snap = snapshot.signalState($0.key) {
                return snap.0 != homeState[$0.key] || snap.1 != distantState[$0.key]
            } else {
                return false
            }
        }).keys
        
        let result = changedSignals.reduce(into: [Signal : (SignalState, SignalState)]()) { result, key in
             result[key] = (homeState[key]!, distantState[key]!)
        }
        
        return result
    }
    
    // If there is a point between this signal and the next monitored block and the point is set
    // to diverge, return the diverging direction as a SignalState (left or right)
    private static func divergingDirection(_ signal: Signal, _ snapshot: LayoutTrackSnapshot) -> SignalState? {
        // The path out of the signal's block is given by the signal indication
        switch signal.indication {
        case .block(let block):
            // Unmonitored blocks are passed through, as for the next block logic
            return block.isUnMonitored
                ? divergingDirection(afterBlock: block, direction: signal.direction, snapshot: snapshot)
                : nil
        case .point(let point, let entering):
            return divergingDirection(afterPoint: point, entering: entering, direction: signal.direction, snapshot: snapshot)
        }
    }
    
    // Follow the active path through the points until the next monitored block is reached, returning
    // the branch direction of the first point that is set to diverge, or nil if there is none
    private static func divergingDirection(afterPoint point: Point, entering: PointDirection, direction: Direction, snapshot: LayoutTrackSnapshot) -> SignalState? {
        guard let currentDirection = snapshot.pointState(point)?.direction else { return nil }
        
        // No active path if the point is set against the entering branch
        if entering == .splitBranch && currentDirection == .splitStraight { return nil }
        if entering == .splitStraight && currentDirection == .splitBranch { return nil }
        
        // The first point set to diverge determines the indicated direction
        // (entering via the branch is a converging move, so straight ahead for the driver)
        if currentDirection == .splitBranch && entering != .splitBranch {
            return point.branchOrientation.signalState
        }
        
        // Not diverging: follow the active path to the next connection
        let exitDirection = entering == .single ? currentDirection : .single
        switch point.connections[exitDirection] {
        case .block(let block):
            // Unmonitored blocks are passed through, as for the next block logic
            return block.isUnMonitored
                ? divergingDirection(afterBlock: block, direction: direction, snapshot: snapshot)
                : nil
        case .point(let nextPoint, let nextEntering):
            return divergingDirection(afterPoint: nextPoint, entering: nextEntering, direction: direction, snapshot: snapshot)
        case .none:
            return nil
        }
    }
    
    // Continue the walk through an unmonitored block to whatever follows it
    private static func divergingDirection(afterBlock block: Block, direction: Direction, snapshot: LayoutTrackSnapshot) -> SignalState? {
        switch block.blockExit[direction] {
        case .point(let pointSetting)?:
            return divergingDirection(afterPoint: pointSetting.point, entering: pointSetting.direction, direction: direction, snapshot: snapshot)
        default:
            return nil      // A monitored block, end of line or unknown exit follows
        }
    }

    private static func translate(_ state: SignalTrackState) -> SignalState {
        switch state {
        case    .signalIndicationNotBlockDirection,
                .signalBlockOccupiedOppositeDirection,
                .indicatedBlockOccupiedSameDirection,
                .indicatedBlockOccupiedOppositeDirection,
                .stoppingAtAssociatedSensor,
                .nextBlockUnavailable,
                .unexpectedState:
                return .stop
        case    .signalBlockOccupiedIndicatedBlockVacant,
                .signalBlockVacantIndicatedBlockVacant:
                return .go
        }
    }
}
