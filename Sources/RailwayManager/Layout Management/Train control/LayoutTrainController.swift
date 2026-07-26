import Foundation

actor LayoutTrainController {
    private let dccSessionStore = DCCSessionStore()
    private let trainDirection: [Train: Direction] = [:]

    init() {
    }

    func activateSession(_ session: Int, forAddress address: Int) async {
        guard let train = await dccSessionStore.train(forAddress: address) else { return }
        await dccSessionStore.setActive(train, session: session)
    }

    func requestSession(for train: Train) async throws {
        if await dccSessionStore.session(for: train) != nil {
            return
        }

        await dccSessionStore.setAwaiting(train)
        log.verbose("Sending RLOC for train address \(train.address)")
        try await CBUSManager.shared.requestSession(forAddress: train.address)
    }

    func releaseSession(for train: Train) async throws {
        guard let session = await dccSessionStore.session(for: train) else { return }
        try await CBUSManager.shared.releaseSession(session)
        await dccSessionStore.setDormant(train)
    }

    func session(for train: Train) async -> Int? {
        await dccSessionStore.session(for: train)
    }

    func sendKeepAlives() async throws {
        for session in await dccSessionStore.activeSessions() {
            try await CBUSManager.shared.sendKeepAlive(session: session)
      }
    }
    
    func commandTrain(_ train: Train,
                      direction: Direction?,        // Default to current
                      speed: TrainSpeed,
                      delay: TimeInterval = 0) async throws {

        var activeSession = await dccSessionStore.session(for: train)
        while activeSession == nil {
            try await Task.sleep(for: .milliseconds(200))
            activeSession = await dccSessionStore.session(for: train)
            
            // TODO: timeout this loop
        }
        
        var newDirection: Direction? {
            if let commandedDirection = direction { return commandedDirection }
            if let currentDirection = trainDirection[train] { return currentDirection }
            return nil
        }
        
        guard let newDirection else { throw TrainError.noTrainDirection(train.id)}
        
        try await train.setSpeed(speed, direction: newDirection, delay: delay, session: activeSession!)
    }
    
    func stopAllTrains() async throws {
        let activeTrains = await dccSessionStore.activeTrains()
        for activeTrain in activeTrains {
            try await commandTrain(activeTrain, direction: .forward, speed: .stop)
        }
    }
}
