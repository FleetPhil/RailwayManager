//
//  LayoutManager.swift
//  RailwayManager
//
//  Created by Phil Diggens on 27/07/2026.
//

import Foundation

actor LayoutManager: Sendable {
    enum LayoutState {
        case dormant
        case running
        case ending
        case error
    }
    
    // Layout
    let layout: Layout
    
    // Active Routes
    private var routeOperators: [Train : RouteOperator] = [:]

    // Handles for long-lived background tasks — stored so they can be cancelled
    private var backgroundTasks: [Task<Void, Never>] = []

    // Layout & state
    private(set) var layoutState: LayoutState = .dormant
    private let trackStateService: LayoutTrackStateService
    
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
    init(layout: Layout) async throws {
        self.layout = layout
        
        self.trackStateService = LayoutTrackStateService(layout: layout)
        self.signalCoordinator = SignalCoordinator()
        
        backgroundTasks.append(Task {
            let stream = await LayoutEventHub.shared.subscribe()
            for await event in stream {
                log.verbose("Event: \(event)")
                // Each event is dispatched into its own Task so the loop keeps consuming
                // new events without waiting for prior ones to complete. This is needed
                // because some events (e.g. didStartRoute) wait for DCC session state that
                // only arrives via a later event (didGetSession).
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
        })
        
        // Monitor events
        backgroundTasks.append(Task {
            let stream = try! await CBUSManager.shared.CBUSEvents()
            for await event in stream {
                await LayoutEventHub.shared.publish(event)
            }
        })

        // Set up Keepalive
        backgroundTasks.append(Task {
            while !Task.isCancelled {
                // Per-session failures are logged inside sendKeepAlives
                await trackStateService.trainController.sendKeepAlives()
                do {
                    try await Task.sleep(for: .seconds(self.keepAliveInterval))
                } catch {
                    break       // Cancelled
                }
            }
        })

        // Setup signal updates
        backgroundTasks.append(Task {
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
        })

        try await resetTrackState(layout: layout)
        
        
        
    }
    
    // Set track state to dormant
    private func resetTrackState(layout: Layout) async throws {
        // Remove all route operators
        for routeOperator in routeOperators {
            routeOperators.removeValue(forKey: routeOperator.key)
        }
        
        try await setState(.dormant)
        
        // Reset block and point states
        try await trackStateService.reset()
    }

    func runRoute(route: Route, train: Train) async throws {
        // Look for an existing inActive route operator for this train
        if let routeOperator = routeOperators[train] {
            if await !routeOperator.routeState.isInactive {
                throw TrainError.trainAlreadyActive(train.id)
            }
        } else {
            // No route operator for this train
            log.debug("Creating route operator for train \(train.name) (\(train))")
            let routeOperator = try await RouteOperator(
                route: route,
                train: train,
                layout: layout,
                stateService: trackStateService,
                trainController: trackStateService.trainController
            )
            self.routeOperators[train] = routeOperator
        }
        
        log.info("Route \(route.id) running with train \(train.name)")

        // OK all looking good
        try await setState(.running)
        
        try await routeOperators[train]!.resetRoute(route: route)
        
        await LayoutEventHub.shared.publish(.didStartRoute(train))
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
            await trackStateService.trainController.stopAllTrains()
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

        await trackStateService.trainController.stopAllTrains()

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
            guard let routeOperator = routeOperators[train] else {
                throw TrainError.applicationError("No route operator for train \(train)")
            }
            try await routeOperator.handleStartRouteEvent()
            
        // MARK: Check for events that change the track or signal state
        case .didFreeResource(let resource):
            switch resource {
            case .block(let block):
                // Free any points associated with this route
                // Points are blocked only when required and set
                // Free any points associated with this block (and associated conflicting points)
                for point in layout.points {
                    let associatedBlock = await trackStateService.associatedBlockForPoint(point)
                    if let associatedBlock, associatedBlock == block {
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
            
            // Get the route operator for this train
            guard let routeOperator = routeOperators[train] else {
                throw TrainError.applicationError("No route operator for train \(train)")
            }
            
            try await routeOperator.handleSensorSet(sensor, orientation: sensorOrientation)
            
        case .didEndTimer(let timerRoute):
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

            var isActiveRouteOperators: Bool {
                get async {
                    for routeOperator in routeOperators.values {
                        if routeOperator.routeState.isInactive == false {
                            return true
                        }
                    }
                    return false            // No active operators
                }
            }
            
            if await isActiveRouteOperators == false {
                log.info("No active route operators: setting dormant state")
                try await setState(.dormant)
            }
            
        // MARK: Stop trains and reset track state
        case .stopAllTrainsResetTrack:
            await trackStateService.trainController.stopAllTrains()
            try await resetTrackState(layout: layout)
            
        // MARK: DCC Management
        case .didGetSession(session: let session, address: let address):
            await trackStateService.trainController.activateSession(session, forAddress: address)
            
        case .sessionAllocated(address: let address):
            try await trackStateService.trainController.stealSession(address: address)
            
            
            
        default:        // Ignore
            break
        }       
    }
    
}

extension LayoutManager {
    func printStatus() async {
        await trackStateService.printStatus()
    }
}
