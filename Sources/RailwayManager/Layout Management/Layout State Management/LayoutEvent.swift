//
//  File.swift
//  
//
//  Created by Phil Diggens on 19/10/2024.
//

import Foundation

actor LayoutEventHub {
    static let shared = LayoutEventHub()

    private let bus = EventBus<LayoutEvent>()

    func publish(_ event: LayoutEvent) async {
        await bus.publish(event)
    }

    func subscribe() async -> AsyncStream<LayoutEvent> {
        await bus.subscribe()
    }
}

enum LayoutEventType {
    case layout
    case route
}

enum SensorEventOrientation: CustomStringConvertible {
    case north
    case south
    
    var description: String {
        return self == .north ? "N" : "S"
    }
    
    var trainSensor: TrainSensor {
        self == .north ? .front : .rear
    }
}

enum LayoutEvent: CustomStringConvertible, Equatable, Sendable {
    
    // Layout events
    case didOccupyBlock(Block, Train)        
    case didPushButton(Int)
    
    // Route events
    case didStartRoute(Train)
    case didEndTimer(Int)
    
    // Shared events
    case didFreeResource(TrackResource)
    case didSetSensor(Int, SensorEventOrientation)
    case didUnsetSensor(Int, SensorEventOrientation)
    case didEndRoute(Train)
    
    // DCC Management
    case didGetSession(session: Int, address: Int)
    
    nonisolated var description: String {
        switch self {
        case .didSetSensor(let sensor, let orientation):
            return "sensor \(sensor) set \(orientation)"
        case .didUnsetSensor(let sensor, let orientation):
            return "sensor \(sensor) unset \(orientation)"
        case .didPushButton(let button):
            return "button \(button)"
            
        case .didOccupyBlock(let block, let route):
            return "block \(block) occupied by route \(route)"
        case .didFreeResource(let resource):
            return "did free resource \(resource)"
        case .didEndTimer(let route):
            return "timer ended for route \(route)"
        case .didStartRoute(let route):
            return "did start route \(route)"
        case .didEndRoute(let route):
            return "did end routine \(route)"
            
        case .didGetSession(let session, let address):
            return "did get session \(session) for address \(address)"
        }
    }
    
    // True if event is relevant to route operators
    var isRouteEvent: Bool {
        switch self {
        case .didStartRoute:              true
        case .didEndRoute:                true

        case .didEndTimer:                  true
        case .didFreeResource:              true
        case .didSetSensor:                 true
        case .didUnsetSensor:               false
            
        case .didPushButton:                false
        case .didOccupyBlock:               false
            
        case .didGetSession(_, _):          false
        }
    }
    
    // True if the event could have changed signals
    var didChangeSignals: Bool {
        switch self {
        case .didOccupyBlock:               true
        case .didFreeResource:              true
        case .didSetSensor:                 true
        default:                            false
        }
    }

}

