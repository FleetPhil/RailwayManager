//
//  LayoutManager.swift
//  RailwayManager
//
//  Created by Phil Diggens on 27/07/2026.
//

import Foundation

actor LayoutManager: Sendable {
    private enum LayoutState {
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
    private var layoutState: LayoutState = .dormant
    private let trackStateService: LayoutTrackStateService
    
    // Signal coordinator
    private let signalCoordinator: SignalCoordinator
    
    // DCC Item States
    private let keepAliveInterval: TimeInterval = 3.0
    
    // MARK: Init
    init(layout: Layout) async throws {
        self.layout = layout
        
        self.trackStateService = LayoutTrackStateService(layout: layout)
        self.signalCoordinator = SignalCoordinator()
        
        backgroundTasks.append(Task {
            let stream = await LayoutEventHub.shared.subscribe()
            for await event in stream {
                log.verbose("Event: \(event)")
                do {
                    try await self.processEvent(event)
                } catch {
                    log.error("Failed to process event \(event): \(error)")
                    layoutState = .error
                }
            }
        })

        // Set up Keepalive
        backgroundTasks.append(Task {
            while !Task.isCancelled {
                do {
                    try await trackStateService.trainController.sendKeepAlives()
                    try await Task.sleep(for: .seconds(self.keepAliveInterval))
                } catch is CancellationError {
                    break
                } catch {
                    log.error("Keep-alive error: \(error)")
                }
            }
        })

        // Setup signal updates
        backgroundTasks.append(Task {
            while !Task.isCancelled {
                do {
                    if layoutState != .dormant {
                        try await updateSignals()
                    }
                    try await Task.sleep(for: .seconds(0.2))
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
        guard routeOperators[train] == nil else {
            log.error("Train \(train) already active - ignored")
            return
        }
        
        log.info("Route \(route.id) running with train \(train.name)")

        // OK all looking good
        try await setState(.running)
        
        let routeOperator = RouteOperator(
            route: route,
            train: train,
            layout: layout,
            stateService: trackStateService,
            trainController: trackStateService.trainController
        )
        self.routeOperators[train] = routeOperator
        try await routeOperator.resetRoute()
        
        await LayoutEventHub.shared.publish(.didStartRoute(train))
    }
    
    // MARK: Layout state
    
    private func setState(_ newState: LayoutState) async throws {
        if self.layoutState == .error {
            log.error("Layout in error state, cannot update")
            return
        }

        log.info("Set layout state to \(newState)")
        
        switch newState {
        case .dormant:
            if self.layoutState == .dormant {
                log.verbose("No change to dormant state: ignored")
                break           // Ignore
            }
            
            Led.setState(.on, forColour: .blue)
            Led.setState(.off, forColour: .red)
            Led.setState(.off, forColour: .green)

            try await trackStateService.trainController.stopAllTrains()

            for signal in layout.signals {
                await trackStateService.setSignalState(signal, .off)
                try await Task.sleep(for: .milliseconds(100))
            }
            
        case .running:
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
            try await trackStateService.trainController.stopAllTrains()
        }
        
        self.layoutState = newState
    }
    
    // MARK: Process track level events
    func processEvent(_ event: LayoutEvent) async throws {
        
        switch event {
            
        // MARK: Check for events that change the track or signal state
        case .didFreeResource(let resource):
            log.info("Freed resource \(resource)")
            switch resource {
            case .block(let block):
                // Free any points associated with this route
                // Points are blocked only when required and set
                // Free any points associated with this block (and associated conflicting points)
                for point in layout.points {
                    let associatedBlock = await trackStateService.associatedBlockForPoint(point)
//                    Log.log.debug("Point \(point) has associated \(associatedBlock, default: "None")")
                    if let associatedBlock {
                        if associatedBlock == block {
                            await LayoutEventHub.shared.publish(.didFreeResource(.point(point)))
                        }
                    }
                }
                                
            case .point(let point):
                try await trackStateService.setReservedTrainForPoint(point, to: nil, associatedStartBlock: nil)
                // If point has been freed and it has a default value reset to that value
                try await trackStateService.setDefaultPositionforPoint(point)
            }
            
        case .didSetSensor(let sensorID, let sensorOrientation):
            guard let sensor = layout.sensor(sensorID) else { throw TrainError.applicationError(9) }

            try await trackStateService.processSensorSetEvent(sensor: sensor, trainSensor: sensorOrientation.trainSensor)
            
        case .didPushButton(let button):
            log.info("Button \(button) pressed")
            switch button {
            case 1:
                // Run default route
                break
                
            case 2:
                // Stop all trains
                try await trackStateService.trainController.stopAllTrains()
                
            case 3:
                // Report state
                break
                
            case 5:     // Touch sensor
                break
                
            default:
                log.error("Unknown button \(button) pressed")
            }
            
        case .didEndRoute(let train):
            log.info("Train \(train) ended")
            
            routeOperators[train] = nil

            if self.routeOperators.isEmpty {
                log.info("No active route operators: setting dormant state")
                try await setState(.dormant)
            }
            
        // MARK: DCC Management
        case .didGetSession(session: let session, address: let address):
            await trackStateService.trainController.activateSession(session, forAddress: address)
            
        default:        // Ignore
            break
        }
        
        // Now pass event to route operators
        if event.isRouteEvent {
            for routeOperator in routeOperators.values {
                try await routeOperator.processEvent(event)
            }
        }
    }
    
    private func updateSignals() async throws {
        if layoutState != .dormant {
            for changedSignal in try SignalCoordinator.refresh(snapshot: await trackStateService.snapshot()) {
                await trackStateService.setSignalState(changedSignal.key, changedSignal.value)
                try await MQTTManager.shared.sendSignalState(signal: changedSignal.key, state: changedSignal.value)
            }
        }
    }
}

extension LayoutManager {
    func printStatus() async {
        await trackStateService.printStatus()
    }
}
