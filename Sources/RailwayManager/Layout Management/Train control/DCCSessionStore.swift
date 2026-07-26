import Foundation

enum DCCItemState {
    case active(session: Int)
    case awaitingSession
    case dormant
    
    var activeSession: Int? {
        switch self {
        case .active(let session):  return session
        default:                    return nil
        }
    }
}

actor DCCSessionStore {
    private var sessionState: [Train: DCCItemState] = [:]

    func setAwaiting(_ train: Train) {
        sessionState[train] = .awaitingSession
    }

    func setActive(_ train: Train, session: Int) {
        sessionState[train] = .active(session: session)
    }

    func setDormant(_ train: Train) {
        sessionState[train] = .dormant
    }

    func session(for train: Train) -> Int? {
        sessionState[train]?.activeSession
    }

    func train(forAddress address: Int) -> Train? {
        sessionState.keys.first(where: { $0.address == address })
    }

    func activeSessions() -> [Int] {
        sessionState.values.compactMap(\.activeSession)
    }
    
    func activeTrains() -> [Train] {
        sessionState
            .filter({
            switch $0.value {
            case .active:   true
            default:        false
            }
            })
            .map(\.key)
    }
}
