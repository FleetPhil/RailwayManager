import Foundation

actor SignalCoordinator {
    // Refresh the signal state and return all changes
    static func refresh(snapshot: LayoutTrackSnapshot, layoutState: LayoutManager.LayoutState) throws -> [ Signal : (SignalState, SignalState)]? {
        // Ignore if layout is not active
        if [LayoutManager.LayoutState.dormant, .error].contains(layoutState) { return nil }
        
        // Set initial state on all signals
        var homeState: [ Signal : SignalState] = [:]
        var distantState: [ Signal : SignalState] = [:]
        for signal in snapshot.allSignals {
            let signalIndication = signal.signalIndication(snapshot: snapshot)
            
            homeState[signal] = translate(signalIndication)
            distantState[signal] = .off     // Default value
        }
        // Now check state of next block for all green signals
        for signal in homeState.filter({ $0.value == .go }).keys {
            // TODO: check if the route out of this block contains any diverging signals
            // If so set the signal state to goDiverging
            

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
