//
//  LayoutManager.swift
//  RailwayManager
//
//  Created by Phil Diggens on 27/07/2026.
//

import Foundation

actor LayoutManager {
    enum LayoutState {
        case dormant
        case running
        case ending
        case error
    }
    
    // Layout
    let layout: Layout
    
    // The trains that can be run
    let trains: TrainRoster
    
    // Active Routes
    private var routeOperators: [Train : RouteOperator] = [:]

    // Handles for long-lived background tasks — stored so they can be cancelled
    private var backgroundTasks: [Task<Void, Never>] = []

    // Layout & state
    private(set) var layoutState: LayoutState = .dormant
    private let trackStateService: LayoutTrackStateService
    private nonisolated var trainController: LayoutTrainController { trackStateService.trainController }
    
    // Signal coordinator
    private let signalCoordinator: SignalCoordinator
    static let signalRefreshInterval: TimeInterval = 0.2
    
    // DCC Item States
    private let keepAliveInterval: TimeInterval = 3.0
    
    // Shutdown Delay
    private let shutdownDelay: TimeInterval = 10
    
    // Pending delayed shutdown - cancelled if a route starts during the delay
    private var shutdownTask: Task<Void, Never>? = nil
    
    // MARK: Init
    init(layout: Layout, trains: TrainRoster) async throws {
        self.layout = layout
        self.trains = trains
        
        self.trackStateService = LayoutTrackStateService(layout: layout)
        self.signalCoordinator = SignalCoordinator()
        
        backgroundTasks = [eventLoopTask(), cbusEventTask(), keepAliveTask(), signalRefreshTask()]
        
        try await resetTrackState()
    }
    
    // MARK: Background tasks
    
    // Process layout events. Each event is dispatched into its own Task so the loop keeps consuming
    // new events without waiting for prior ones to complete. This is needed because some events
    // (e.g. didStartRoute) wait for DCC session state that only arrives via a later event (didGetSession).
    private func eventLoopTask() -> Task<Void, Never> {
        Task {
            let stream = await LayoutEventHub.shared.subscribe()
            for await event in stream {
                log.verbose("Event: \(event)")
                Task {
                    do {
                        try await self.processEvent(event)
                    } catch {
                        log.warning("Failed to process event \(event): \(error)")
                        do {
                            try await CBUSManager.shared.stopAllTrains()
                        } catch {
                            // Can't reach the command station: show the error (red LED)
                            // and try stopping trains individually rather than crashing
                            log.error("Emergency stop failed: \(error)")
                            try? await self.setState(.error)
                        }
                    }
                }
            }
        }
    }
    
    // Pass CBUS events on to the layout event hub
    private func cbusEventTask() -> Task<Void, Never> {
        Task {
            let stream = try! await CBUSManager.shared.CBUSEvents()
            for await event in stream {
                await LayoutEventHub.shared.publish(event)
            }
        }
    }
    
    // Send DCC keep-alives
    private func keepAliveTask() -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                // Per-session failures are logged inside sendKeepAlives
                await self.trainController.sendKeepAlives()
                do {
                    try await Task.sleep(for: .seconds(self.keepAliveInterval))
                } catch {
                    break       // Cancelled
                }
            }
        }
    }
    
    // Refresh the signals while the layout is not dormant
    private func signalRefreshTask() -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                do {
                    if layoutState != .dormant {
                        try await trackStateService.updateSignals()
                    }
                    try await Task.sleep(for: .seconds(LayoutManager.signalRefreshInterval))
                } catch is CancellationError {
                    break
                } catch {
                    log.error("Signal update error: \(error)")
                }
            }
        }
    }
    
    // Set track state to dormant
    private func resetTrackState() async throws {
        routeOperators.removeAll()
        
        try await setState(.dormant)
        
        // Reset block and point states
        try await trackStateService.reset()
        
        // Trains are still standing in their last known blocks. A conflict is only logged, so the reset completes
        for train in trains.trains {
            guard let block = try? await trainController.trainState(train).lastKnownBlock else { continue }
            let direction = (try? await trainController.trainDirection(train)) ?? .forward
            do {
                try await trackStateService.setStateForBlock(block, newState: .occupied(train, direction))
            } catch {
                log.error("Can't occupy block \(block) for train \(train.id) after reset: \(error)")
            }
        }
    }
    
    // Put an idle train in a block, at startup or after it has been moved by hand: free any other
    // blocks it holds and occupy this one. Throws if the train is running a route or the block is
    // held by another train
    func placeTrain(_ train: Train, in block: Block) async throws {
        if await isRunningRoute(train) {
            throw TrainError.trainAlreadyActive(train.id)
        }
        if let holder = try await trackStateService.trainForBlock(block), holder != train {
            throw TrainError.invalidBlockStateChange("Can't place train \(train.id) in block \(block): held by train \(holder.id)")
        }
        
        // Keep the train's direction if it has one
        let direction = (try? await trainController.trainDirection(train)) ?? .forward
        try await trainController.setTrainDirection(train, direction: direction)
        
        for otherBlock in layout.blocks where otherBlock != block {
            if try await trackStateService.trainForBlock(otherBlock) == train {
                try await trackStateService.setStateForBlock(otherBlock, newState: .vacant)
            }
        }
        try await trainController.setTrainState(train, state: .idle(block))
        try await trackStateService.setStateForBlock(block, newState: .occupied(train, direction))
        
        log.info("Train \(train.id) placed in block \(block)")
    }

    func runRoute(route: Route, train: Train) async throws {
        // The route starts from the block the train is in
        guard let startBlock = try? await trainController.trainState(train).lastKnownBlock else {
            throw TrainError.invalidRoute("Route \(route.id): position of train \(train.id) not known; place it with tb")
        }
        
        // Throws if there are no segments or a segment has no path from where it starts
        try route.validate(from: startBlock, in: layout)
        
        // Reject a route that takes the train round a loop too short for it
        try route.checkLoopLengths(for: train, from: startBlock, in: layout)
        
        // Reuse the train's route operator if it has one (it must not be running a route), otherwise create one
        let routeOperator: RouteOperator
        if let existingOperator = routeOperators[train] {
            if await isRunningRoute(train) {
                throw TrainError.trainAlreadyActive(train.id)
            }
            routeOperator = existingOperator
        } else {
            log.debug("Creating route operator for train \(train.name) (\(train))")
            routeOperator = RouteOperator(
                route: route,
                train: train,
                layout: layout,
                stateService: trackStateService,
                trainController: trainController
            )
            routeOperators[train] = routeOperator
        }
        
        log.info("Route \(route.id) running with train \(train.name)")

        // OK all looking good
        try await setState(.running)
        
        try await routeOperator.resetRoute(route: route, startBlock: startBlock)
        
        await LayoutEventHub.shared.publish(.didStartRoute(train))
    }
    
    // MARK: Route operators
    
    // The train's route operator: one is created when the train first runs a route
    private func routeOperator(for train: Train) throws -> RouteOperator {
        guard let routeOperator = routeOperators[train] else {
            throw TrainError.applicationError("No route operator for train \(train)")
        }
        return routeOperator
    }
    
    // The train is running a route (one is starting, active or ending)
    private func isRunningRoute(_ train: Train) async -> Bool {
        guard let routeOperator = routeOperators[train] else { return false }
        return await !routeOperator.routeState.isInactive
    }
    
    // Any train is running a route
    private func hasActiveRoutes() async -> Bool {
        for train in routeOperators.keys {
            if await isRunningRoute(train) { return true }
        }
        return false
    }
    
    // MARK: Layout state
    
    func setState(_ newState: LayoutState) async throws {
        if self.layoutState == .error {
            log.error("Layout in error state, cannot update")
            return
        }

        switch newState {
        case .dormant:
            if self.layoutState == .dormant {
                log.verbose("No change to dormant state: ignored")
                break           // Ignore
            }
            
            log.verbose("Layout shutting down in \(shutdownDelay)s")
            
            // Schedule the shutdown: a route started during the delay cancels it
            shutdownTask?.cancel()
            shutdownTask = Task {
                do {
                    try await Task.sleep(for: .seconds(self.shutdownDelay))
                } catch {
                    return          // Cancelled: a new route started
                }
                await self.completeShutdown()
            }
            return                  // State becomes dormant when the shutdown completes
            
        case .running:
            // Cancel any pending shutdown
            shutdownTask?.cancel()
            shutdownTask = nil
            
            if layoutState == .running {
                log.error("State change to running ignored")
                return
            }
            
            Led.setState(.off, forColour: .blue)
            Led.setState(.on, forColour: .green)

        case .ending:
            Led.setState(.slowFlash, forColour: .green)

        case .error:
            Led.setState(.off, forColour: .green)
            Led.setState(.off, forColour: .blue)
            Led.setState(.on, forColour: .red)
            await trainController.stopAllTrains()
        }
        
        self.layoutState = newState
    }
    
    // Complete a delayed transition to dormant: stop everything and turn off the signals
    private func completeShutdown() async {
        // A route may have started, or an error occurred, while the shutdown was pending
        guard !Task.isCancelled, layoutState != .error, layoutState != .dormant else { return }
        
        Led.setState(.on, forColour: .blue)
        Led.setState(.off, forColour: .red)
        Led.setState(.off, forColour: .green)

        await trainController.stopAllTrains()

        layoutState = .dormant
        shutdownTask = nil

        for signal in layout.signals {
            try? await trackStateService.setSignalState(signal, home: .off, distant: .off)
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        log.info("Layout is now dormant")
    }
    
    // MARK: Process track level events
    func processEvent(_ event: LayoutEvent) async throws {
        switch event {
            
        case .didStartRoute(let train):
            try await routeOperator(for: train).handleStartRouteEvent()
            
        // MARK: Check for events that change the track or signal state
        case .didFreeResource(let resource):
            switch resource {
            case .block(let block):
                // Free any points associated with this route
                // Points are blocked only when required and set
                // Free any points associated with this block (and associated conflicting points)
                for point in layout.points {
                    if await trackStateService.associatedBlockForPoint(point) == block {
                        await LayoutEventHub.shared.publish(.didFreeResource(.point(point)))
                        // Wait otherwise all points set at once causing potential short
                        try await Task.sleep(for: .milliseconds(200))
                    }
                }
                
            case .point(let point):
                try await trackStateService.setReservedTrainForPoint(point, to: nil, associatedStartBlock: nil)
                // If point has been freed and it has a default value reset to that value
                try await trackStateService.setDefaultPositionforPoint(point)
            }
            
            // Send the event to route operators to check if any are waiting for the resource
            for routeOperator in routeOperators.values {
                try await routeOperator.handleFreedResource(resource)
            }
            
        case .didSetSensor(let sensorAddress, let sensorOrientation):
            guard let sensor = layout.sensor(sensorAddress) else { throw TrainError.invalidSensor(sensorAddress) }
            
            // Find the train in the sensor block
            guard let train = try await trackStateService.trainForBlock(sensor.location.block) else {
                throw TrainError.applicationError("Sensor \(sensor) set but no train in block \(sensor.location.block)")
            }
            
            try await routeOperator(for: train).handleSensorSet(sensor, orientation: sensorOrientation)
            
        case .didEndTimer:
            // Currently unused
            log.error("Unexpected end timer event")
            
        case .didPushButton(let button):
            log.info("Button \(button) pressed")
            switch button {
            case 1:
                // Run default route
                break
                
            case 2:     // disconnect MQTT
                try await MQTTManager.shared.disconnect()

            case 3:
                // Stop all trains & shut down
                await completeShutdown()
                try? await MQTTManager.shared.disconnect()
                
                // Print sensor stats
                if !GlobalOptions.noCBUS {
                    await CBUSManager.shared.printSensorStats()
                }
                
                try await Task.sleep(for: .seconds(1))      // Allow time to print stats
                
                exit(0)
                
            case 5:     // Touch sensor
                break
                
            default:
                log.error("Unknown button \(button) pressed")
            }
            
        case .didEndRoute(let train):
            log.info("Train \(train) ended")

            if await !hasActiveRoutes() {
                log.info("No active route operators: setting dormant state")
                try await setState(.dormant)
            }
            
        // MARK: Stop trains and reset track state
        case .stopAllTrainsResetTrack:
            await trainController.stopAllTrains()
            try await resetTrackState()
            
        // MARK: DCC Management
        case .didGetSession(session: let session, address: let address):
            await trainController.activateSession(session, forAddress: address)
            
        case .sessionAllocated(address: let address):
            try await trainController.stealSession(address: address)
            
        default:        // Ignore
            break
        }
    }
    
    func printStatus() async {
        await trackStateService.printStatus()
    }
}
