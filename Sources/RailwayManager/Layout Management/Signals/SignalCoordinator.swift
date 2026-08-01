import Foundation

actor SignalCoordinator {
    // Refresh the signal state and return all changes
    static func refresh(snapshot: LayoutTrackSnapshot, layoutState: LayoutManager.LayoutState) throws -> [ Signal : SignalState ]? {
        // Ignore if layout is not active
        if [LayoutManager.LayoutState.dormant, .error].contains(layoutState) { return nil }
        
        // Set initial state on all signals
        var newState: [ Signal : SignalState] = [:]
        for signal in snapshot.allSignals {
            let signalIndication = signal.signalIndication(snapshot: snapshot)
            newState[signal] = translate(signalIndication)
        }
        // Now check for caution
        for signal in newState.filter({ $0.value == .go }).keys {
            
            // Signal is green: check to see if caution needs to be set
            // Find a signal in the next block indicating the same direction
            // if it is set to red update the current signal
            let nextBlock = signal.nextBlock(snapshot: snapshot)
            if let signalForBlock = snapshot.allSignals.first(where: {
                $0.location == nextBlock && $0.direction == signal.direction
            }) {
                if newState[signalForBlock] == .stop {
                    newState[signal] = .caution
                }
            }
        }
        
        return newState.filter({ newSignalState in
            snapshot.signalState(newSignalState.key) != newSignalState.value
        })
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
