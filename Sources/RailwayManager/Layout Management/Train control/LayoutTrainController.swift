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
            throw TrainError.applicationError(21)
        }
        return state
    }
    
    // Return which end of the train (front or rear) has set the sensor taking into account the moving direction
    func trainSensorLocationForOrientation(train: Train, orientation: SensorEventOrientation) -> TrainSensor {
        let direction = try! trainDirection(train)
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
            throw TrainError.applicationError(20)
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

        var activeSession = await dccSessionStore.session(for: train)
        while activeSession == nil {
            try await Task.sleep(for: .milliseconds(200))
            activeSession = await dccSessionStore.session(for: train)
            
            // TODO: timeout this loop
        }
        
        try await train.setSpeed(speed, direction: direction, delay: delay, session: activeSession!)
        log.verbose("Train \(train) speed is \(speed) \(direction)")
    }
    
    func stopAllTrains() async throws {
        let activeTrains = await dccSessionStore.activeTrains()
        for activeTrain in activeTrains {
            try await commandTrain(activeTrain, speed: .stop)
            setTrainState(activeTrain, state: .idle)
        }
    }
}
