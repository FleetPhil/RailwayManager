//
//  TrainSimulator.swift
//  RailwayManager
//
//  Simulates the sensor events of a running train (for testing without hardware, see -test).
//  It watches the train's state and only emits the events a moving train would produce, so a train
//  held for a resource stays still until it is released.
//

import Foundation

actor TrainSimulator {
    // Delays between the simulated sensor events, each measured from the previous event while the train is moving
    struct Delays {
        var clear: TimeInterval = 1         // Front enters a block to rear sets the same (start) sensor
        var block: TimeInterval = 5         // Rear sets start sensor to front sets end sensor
        var settle: TimeInterval = 1        // Front sets end sensor to the check that the train is still moving
        var enter: TimeInterval = 5         // Rear leaves a block to front sets the next block's start sensor
        var pulse: TimeInterval = 1         // How long a sensor stays set
    }

    // The next sensor event of the train, in the order a block is passed through
    private enum Step: CustomStringConvertible {
        case rearAtStart            // Rear sets the start sensor of the block the front is in: previous block is clear
        case frontAtEnd             // Front sets the end sensor of its block
        case rearAtEnd              // Rear sets the end sensor of the block (the train has not stopped)
        case frontAtNextStart       // Front sets the start sensor of the next (reserved) block

        var description: String {
            switch self {
            case .rearAtStart:          "rear at block start"
            case .frontAtEnd:           "front at block end"
            case .rearAtEnd:            "rear at block end"
            case .frontAtNextStart:     "front at next block start"
            }
        }
    }

    private let train: Train
    private let layoutManager: LayoutManager
    private let delays: Delays
    private let pollInterval = Duration.milliseconds(250)

    // Progress of the train through the block its front is in
    private var frontBlock: Block?
    private var isRearAtStartDue = false
    private var isFrontAtEndDone = false
    private var isRearAtEndDone = false

    // When the train last moved on a step, or was last seen not moving
    private var lastEventTime = ContinuousClock.now
    private var wasMoving = false

    init(train: Train, layoutManager: LayoutManager, delays: Delays = Delays()) {
        self.train = train
        self.layoutManager = layoutManager
        self.delays = delays
    }

    // Runs until cancelled. Idle between routes so it can be left running for a repeating routine.
    func run() async {
        log.info("Simulator for train \(train): started")
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: pollInterval)
                try await tick()
            } catch is CancellationError {
                break
            } catch {
                log.error("Simulator for train \(train): \(error)")
            }
        }
        log.info("Simulator for train \(train): stopped")
    }

    private func tick() async throws {
        let snapshot = await layoutManager.trackSnapshot()
        guard let trainState = snapshot.trainState(train) else { return }

        // Not running a route: forget the progress so the next route starts afresh
        if case .idle = trainState {
            resetProgress()
            wasMoving = false
            return
        }

        // Nothing happens while the train is stopped (for a resource, a timer, ...);
        // the delay to the next event starts again when it moves
        guard trainState.isMoving else {
            if wasMoving { log.info("Simulator for train \(train): train not moving (\(trainState))") }
            wasMoving = false
            lastEventTime = .now
            return
        }
        if !wasMoving {
            log.info("Simulator for train \(train): train moving (\(trainState))")
            wasMoving = true
            lastEventTime = .now
        }

        // Find where the front of the train is
        if frontBlock == nil {
            guard locateFrontBlock(snapshot) else { return }
        }
        guard let frontBlock, let direction = snapshot.travelDirection(in: frontBlock) else { return }

        let step = nextStep()
        guard ContinuousClock.now - lastEventTime >= .seconds(delay(for: step)) else { return }

        switch step {
        case .rearAtStart:
            try await emit(step, .rear, block: frontBlock, atBlockStart: true, direction: direction)
            isRearAtStartDue = false

        case .frontAtEnd:
            try await emit(step, .front, block: frontBlock, atBlockStart: false, direction: direction)
            isFrontAtEndDone = true

        case .rearAtEnd:
            try await emit(step, .rear, block: frontBlock, atBlockStart: false, direction: direction)
            isRearAtEndDone = true

        case .frontAtNextStart:
            // The train only moves on once the next block is reserved for it
            guard let (nextBlock, nextDirection) = reservedBlock(snapshot) else { return }
            try await emit(step, .front, block: nextBlock, atBlockStart: true, direction: nextDirection)
            resetProgress()
            self.frontBlock = nextBlock
            isRearAtStartDue = true
        }
        lastEventTime = .now
    }

    private func nextStep() -> Step {
        if isRearAtStartDue { return .rearAtStart }
        if !isFrontAtEndDone { return .frontAtEnd }
        if !isRearAtEndDone { return .rearAtEnd }
        return .frontAtNextStart
    }

    private func delay(for step: Step) -> TimeInterval {
        switch step {
        case .rearAtStart:          delays.clear
        case .frontAtEnd:           delays.block
        case .rearAtEnd:            delays.settle
        case .frontAtNextStart:     delays.enter
        }
    }

    private func resetProgress() {
        frontBlock = nil
        isRearAtStartDue = false
        isFrontAtEndDone = false
        isRearAtEndDone = false
    }

    // The front is in the block occupied by the train (at route start, or after the train has stopped
    // mid route); it is part way past if another block is still being vacated.
    private func locateFrontBlock(_ snapshot: LayoutTrackSnapshot) -> Bool {
        let trainBlocks = snapshot.allBlocks.filter { snapshot.blockState($0)?.train == train }
        guard let occupied = trainBlocks.first(where: {
            if case .occupied = snapshot.blockState($0) { return true } else { return false }
        }) else { return false }

        frontBlock = occupied
        isRearAtStartDue = trainBlocks.contains(where: {
            if case .vacating = snapshot.blockState($0) { return true } else { return false }
        })
        return true
    }

    // The block reserved for the train: the one the front moves into next
    private func reservedBlock(_ snapshot: LayoutTrackSnapshot) -> (Block, BlockDirection)? {
        for block in snapshot.allBlocks {
            if case .reserved(let reservedTrain, let direction) = snapshot.blockState(block), reservedTrain == train {
                return (block, direction)
            }
        }
        return nil
    }

    // Set the sensor at the start or end of the block, in the train's direction, for the front or rear of the train
    private func emit(_ step: Step, _ end: TrainSensor, block: Block, atBlockStart: Bool, direction: BlockDirection) async throws {
        guard let sensor = layoutManager.layout.sensorForBlock(block, atBlockStart: atBlockStart, inDirection: direction) else {
            throw TrainError.applicationError("Simulator: no sensor at \(atBlockStart ? "start" : "end") of block \(block)")
        }
        let orientation = try await layoutManager.sensorOrientation(of: end, for: train)
        log.info("Simulator for train \(train): \(step): sensor \(sensor) \(orientation)")

        await LayoutEventHub.shared.publish(.didSetSensor(sensor.address, orientation))
        let pulse = delays.pulse
        Task {
            try? await Task.sleep(for: .seconds(pulse))
            await LayoutEventHub.shared.publish(.didUnsetSensor(sensor.address, orientation))
        }
    }
}
