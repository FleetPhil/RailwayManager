import Foundation

actor LayoutTrainController {
    private let dccSessionStore = DCCSessionStore()
    private(set) var trainStates: [ Train: TrainRuntimeState] = [:]
    private(set) var trainDirections: [Train: Direction] = [:]

    init() {
    }

    func activateSession(_ session: Int, forAddress address: Int) async {
        guard let train = await dccSessionStore.train(forAddress: address) else { return }
        await dccSessionStore.setActive(train, session: session)
        
        trainStates[train] = .idle
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
    
    func trainDirection(_ train: Train) throws -> Direction {
        guard let state = trainDirections[train] else {
            throw TrainError.noTrainDirection(train.id)
        }
        return state
    }
    
    // Return which end of the train (front or rear) has set the sensor taking into account the moving direction
    func trainSensorLocationForOrientation(train: Train, orientation: SensorEventOrientation) throws -> TrainSensor {
        let direction = try trainDirection(train)
        if orientation == train.trainFrontSensorOrientation {           // Front sensor
            if direction == .forward {
                return .front
            } else {
                return .rear
            }
        } else {                // Rear sensor
            if direction == .forward {
                return .rear
            } else {
                return .front
            }
        }
    }
    
    func setTrainDirection(_ train: Train, direction: Direction) {
        log.verbose("Train \(train) direction is \(direction)")
        trainDirections[train] = direction
    }
    
    func isNewTrain(_ train: Train) -> Bool {
        trainStates[train] == nil
    }
    
    func trainState(_ train: Train) throws -> TrainRuntimeState {
        guard let state = trainStates[train] else {
            throw TrainError.applicationError("No runtime state for train \(train.id)")
        }
        return state
    }
    
    func setTrainState(_ train: Train, state: TrainRuntimeState) {
        trainStates[train] = state
    }
    
    func sendKeepAlives() async throws {
        for session in await dccSessionStore.activeSessions() {
            try await CBUSManager.shared.sendKeepAlive(session: session)
      }
    }
    
    func commandTrain(_ train: Train,
                      speed: TrainSpeed,
                      delay: TimeInterval = 0) async throws {
        
        let direction = try trainDirection(train)

        if GlobalOptions.noCBUS {
            log.verbose("Train \(train) speed is \(speed) \(direction)")
            return
        }

        // Wait for an active DCC session, but not forever: a command (especially a stop)
        // must fail loudly rather than hang if the session never arrives
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var activeSession = await dccSessionStore.session(for: train)
        while activeSession == nil {
            guard ContinuousClock.now < deadline else {
                throw TrainError.noDCCSession(train.id)
            }
            try await Task.sleep(for: .milliseconds(200))
            activeSession = await dccSessionStore.session(for: train)
        }
        guard let session = activeSession else {
            throw TrainError.noDCCSession(train.id)
        }
        
        try await train.setSpeed(speed, direction: direction, delay: delay, session: session)
        log.verbose("Train \(train) speed is \(speed) \(direction)")
    }
    
    // Stop every active train, best effort: a failure for one train must not prevent
    // stopping the others. Falls back to a track-wide emergency stop on any failure.
    func stopAllTrains() async {
        var stopFailed = false
        let activeTrains = await dccSessionStore.activeTrains()
        for activeTrain in activeTrains {
            do {
                try await commandTrain(activeTrain, speed: .stop)
                setTrainState(activeTrain, state: .idle)
            } catch {
                stopFailed = true
                log.error("Failed to stop train \(activeTrain): \(error)")
            }
        }
        
        if stopFailed {
            do {
                try await CBUSManager.shared.stopAllTrains()
            } catch {
                log.error("CBUS emergency stop failed: \(error)")
            }
        }
    }
}
