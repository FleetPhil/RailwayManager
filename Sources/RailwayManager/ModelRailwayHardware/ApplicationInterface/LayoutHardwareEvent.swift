////
////  File.swift
////  
////
////  Created by Phil Diggens on 19/10/2024.
////
//
//import Foundation
//
//actor LayoutHardwareEventHub {
//    static let shared = LayoutHardwareEventHub()
//
//    private let bus = EventBus<LayoutHardwareEvent>()
//
//    func publish(_ event: LayoutHardwareEvent) async {
//        await bus.publish(event)
//    }
//
//    func subscribe() async -> AsyncStream<LayoutHardwareEvent> {
//        await bus.subscribe()
//    }
//}
//
//enum LayoutEventType {
//    case layout
//    case route
//}
//
//enum SensorEventOrientation: CustomStringConvertible {
//    case north
//    case south
//    
//    var description: String {
//        return self == .north ? "N" : "S"
//    }
//}
//
//enum LayoutHardwareEvent: CustomStringConvertible, Equatable, Sendable {
//    
//    // Hardware events
//    case didPushButton(Int)
//    
//    case didSetSensor(Int, SensorEventOrientation)
//    case didUnsetSensor(Int, SensorEventOrientation)
//    
//    // DCC Management
//    case didGetSession(session: Int, address: Int)
//    
//    nonisolated var description: String {
//        switch self {
//        case .didSetSensor(let sensor, let orientation):
//            return "sensor \(sensor) set \(orientation)"
//        case .didUnsetSensor(let sensor, let orientation):
//            return "sensor \(sensor) unset \(orientation)"
//        case .didPushButton(let button):
//            return "button \(button)"
//            
//        case .didGetSession(let session, let address):
//            return "did get session \(session) for address \(address)"
//        }
//    }
//    
//    // True if event is relevant to route operators
//    var isRouteEvent: Bool {
//        switch self {
//        case .didSetSensor:                 true
//        case .didUnsetSensor:               false
//            
//        case .didPushButton:                false
//            
//        case .didGetSession(_, _):          false
//        }
//    }
//    
//
//}
//
