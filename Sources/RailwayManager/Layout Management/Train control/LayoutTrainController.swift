import Foundation

actor LayoutTrainController {
    private let dccSessionStore = DCCSessionStore()
    private(set) var trainStates: [ Train: TrainRuntimeState] = [:]
    private(set) var trainDirections: [Train: BlockDirection] = [:]

    init() {
    }

    func activateSession(_ session: Int, forAddress address: Int) async {
        guard let train = await dccSessionStore.train(forAddress: address) else {
            log.debug("DCC: Can't activate session: no train for address \(address)")
            return
        }
        await dccSessionStore.setActive(train, session: session)
        
        log.debug("DCC: Session active and train \(train) idle for address \(address)")
        
        trainStates[train] = .idle
    }
    
    func stealSession(address: Int) async throws  {
        log.verbose("DCC: Steal: sending GLOC for train address \(address)")
        try await CBUSManager.shared.stealSession(address: address)
        
        
    }


    func requestSession(for train: Train) async throws {
        if await dccSessionStore.session(for: train) != nil {
            log.debug("DCC: Session already active for train \(train)")
            return
        }
        
        await dccSessionStore.setAwaiting(train)
        log.debug("DCC: Sending RLOC for train address \(train.address)")
        try await CBUSManager.shared.requestSession(forAddress: train.address)
    }

    func releaseSession(for train: Train) async throws {
        guard let session = await dccSessionStore.session(for: train) else {
            log.debug("DCC: No session to release for train \(train)")
            return
        }
        try await CBUSManager.shared.releaseSession(session)
        await dccSessionStore.setDormant(train)
    }
    
    private func activeDCCSession(_ train: Train) async throws -> Int {
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
        
        return session
    }
    
    func trainDirection(_ train: Train) throws -> BlockDirection {
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
    
    func setTrainDirection(_ train: Train, direction: BlockDirection) throws {
        if let currentDirection = trainDirections[train] {
            if direction == currentDirection { return }
        }
         
        // Either no current direction is set or it is different to the one being commanded
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
    
    func setTrainState(_ train: Train, state: TrainRuntimeState) async throws {
        if state == trainStates[train] { return }
        
        log.debug("Train \(train) state from \(trainStates[train], default: "none") to \(state)")
        
        trainStates[train] = state
        
        try await MQTTManager.shared.sendTrainState(train: train, state: state)
    }
    
    // Send a keep-alive to every active session, best effort: a failure for one
    // session must not prevent the others from being kept alive
    func sendKeepAlives() async {
        for session in await dccSessionStore.activeSessions() {
            do {
                try await CBUSManager.shared.sendKeepAlive(session: session)
            } catch {
                log.error("Keep-alive failed for session \(session): \(error)")
            }
        }
    }
    
    func setSpeedforTrain(_ train: Train,
                      speed: TrainSpeed,
                      delay: TimeInterval = 0) async throws {
        
        let direction = try trainDirection(train)
        log.verbose("Train \(train) speed is \(speed) \(direction)")

        if GlobalOptions.noCBUS || GlobalOptions.noDCC {
            return
        }
        
        let session = try await activeDCCSession(train)
        try await train.setSpeed(speed, direction: direction, delay: delay, session: session)
    }
    
    public func setTrainFunction(train: Train, function: Int, on: Bool) async throws {
        if GlobalOptions.noCBUS || GlobalOptions.noDCC {
            log.verbose("Train \(train) function \(function) \(on ? "on" : "off")")
            return
        }
        
        let session = try await activeDCCSession(train)
        
        try await train.setFunction(function, on: on, session: session)
    }

    
    // Stop every active train, best effort: a failure for one train must not prevent
    // stopping the others. Falls back to a track-wide emergency stop on any failure.
    func stopAllTrains() async {
        var stopFailed = false
        let activeTrains = await dccSessionStore.activeTrains()
        for activeTrain in activeTrains {
            do {
                try await setSpeedforTrain(activeTrain, speed: .stop)
                try await setTrainState(activeTrain, state: .idle)
            } catch {
                stopFailed = true
                log.error("Failed to stop train \(activeTrain): \(error)")
            }
        }
        
        if stopFailed {
            do {
                log.warning("CBUS emergency stop")
                try await CBUSManager.shared.stopAllTrains()
            } catch {
                log.error("CBUS emergency stop failed: \(error)")
            }
        }
        
        
    }
}
