//
//  MQTTManager.swift
//  ModelRailway
//
//  Created by Phil Diggens on 29/03/2026.
//

import Foundation
import MQTTNIO
import NIOPosix
import NIOCore

actor MQTTManager: Sendable {
    static let shared: MQTTManager = MQTTManager()
    
    enum MQTTState {
        case idle
        case connected
        case error
    }
    
    enum LayoutItem: Int, Codable {
        case signal     = 1
        case block      = 2
        case point      = 3
    }

    struct LayoutItemState: Codable {
        var itemType: LayoutItem
        var itemID: String
        var itemState: String
        var additionalInformation: String?
    }
    
    private var client: MQTTClient? = nil
    private var mqttState: MQTTState = .idle
    
    private let topic = "railway"
    private let stateTopic = "/state"
    private let layoutTopic = "/topology"

    private init() {
        client = MQTTClient(
            host: "192.168.86.56",
            port: 1883,
            identifier: "ModelRailway",
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton)
        )
    }
    
    func connect() async throws {
        if GlobalOptions.noMQTT {
            try client?.syncShutdownGracefully()
            client = nil
            return
        }
        
        switch mqttState {
        case .idle:
            // connect to MQTT
            do {
                try await client?.connect()
                mqttState = .connected
            } catch {
                mqttState = .error
                throw TrainError.MQTTConnectFail
            }
            
        case .connected:
            break
        case .error:
            break
            
        }
    }
    
//    func sendTopolology(fromLayout: LayoutTopology) async throws {
//        do {
//            let payload = try String(decoding: JSONEncoder().encode(stateTopology(fromLayout)), as: UTF8.self)
//            try await client?.publish(to: topic + layoutTopic,
//                                      payload: ByteBufferAllocator().buffer(string: payload),
//                                      qos: .atLeastOnce)
//        } catch {
//            handleJSONError(error)
//            throw TrainError.applicationError(17)
//        }
//
//    }
    
    func sendSignalState(signal: Signal, state: SignalState) async throws {
        do {
            let state = LayoutItemState(itemType: .signal,
                                        itemID: "\(signal.id)",
                                        itemState: state.description)
            let payload = try String(decoding: JSONEncoder().encode(state), as: UTF8.self)
            if GlobalOptions.noMQTT {
//                log.debug("Payload: \(payload)")
            } else {
                try await client?.publish(to: topic + stateTopic,
                                          payload: ByteBufferAllocator().buffer(string: payload),
                                          qos: .atLeastOnce)
            }
        } catch {
            handleJSONError(error)
            throw TrainError.applicationError(17)
        }
    }

    func sendPointState(point: Point, state: PointDirection) async throws {
        do {
            let state = LayoutItemState(itemType: .point,
                                        itemID: "\(point.id)",
                                        itemState: state.rawValue)
            let payload = try String(decoding: JSONEncoder().encode(state), as: UTF8.self)
            
            if GlobalOptions.noMQTT {
//                log.debug("Payload: \(payload)")
            } else {
                try await client?.publish(to: topic + stateTopic,
                                          payload: ByteBufferAllocator().buffer(string: payload),
                                          qos: .atLeastOnce)
            }
        } catch {
            handleJSONError(error)
            try? await Task.sleep(for: .milliseconds(500))
            throw TrainError.applicationError(18)
        }
    }

    func sendBlockRuntimeState(block: Block, blockState: BlockRuntimeState, trainState: TrainRuntimeState? = nil) async throws {
        var itemState: String = ""
        var additionalInformation: String? = nil
        
        switch blockState {
        case .vacant:
            itemState = "vacant"
        case .reserved(let train, _):
            itemState = "reserved"
            additionalInformation = "Train \(train)"
        case .occupied(let train, _):
            itemState = "occupied"
            additionalInformation = {
                switch trainState {
                case .idle:
                    return "idle (Train \(train))"
                case .running:
                    return "Running (Train \(train))"
                case .waiting:
                    return "Waiting (Train \(train))"
                case .stoppingForResource(let resource, let sensor, _, _):
                    return "Stopping at \(sensor.id) for \(resource) (Train \(train))"
                case .stoppedForResource(let trackResource, _):
                    switch trackResource {
                    case .point(let point):
                        return "Waiting for point \(point.id) (Train \(train))"
                    case .block(let block):
                        return "Waiting for block \(block.id) (Train \(train))"
                    }
                case .stoppingAtSensor(let sensor, _):
                    return "Stopping at sensor \(sensor.id) (Train \(train))"
                case .stoppedAtSensor(let sensor):
                    return "Stopped at sensor \(sensor.id) (Train \(train))"
                case .none:
                    return "No train state??"
                }
            }()
        }
        
        do {
            
            let state = LayoutItemState(itemType: .block,
                                        itemID: block.id,
                                        itemState: itemState,
                                        additionalInformation: additionalInformation)
            
            let payload = try String(decoding: JSONEncoder().encode(state), as: UTF8.self)
            if GlobalOptions.noMQTT {
//                log.debug("Payload: \(payload)")
            } else {
                try await client?.publish(to: topic + stateTopic,
                                          payload: ByteBufferAllocator().buffer(string: payload),
                                          qos: .atLeastOnce)
            }
        } catch {
            handleJSONError(error)
            throw TrainError.applicationError(19)
        }
    }
    
    private func handleJSONError(_ error: Error) {
        switch error {
        case EncodingError.invalidValue(let value, let context):
            log.error("JSON encoding error: invalid value \(value), path: \(context.codingPath), description: \(context.debugDescription)")
        default:
            log.error("MQTT publish error: \(error)")
        }
    }

}

extension MQTTManager {
    struct BlockTopology: Codable {
        var forwardEndSignal: Int?   // Signal at block end in the forward direction
        var reverseEndSignal: Int?   // Signal at block end in the reverse direction
    }
    
    struct StateTopology: Codable {
        var blockTopologies: [String : BlockTopology]
        var signalLocations: [ Int : String ]
        var points: [ Int ]
    }

//    func stateTopology(_ from: LayoutTopology) -> StateTopology {
//        let blockTopologies: [ String : BlockTopology ] = from.blocks.reduce(into: [:], { result, next in
//            let fs = from.signals.first(where: { $0.value.location == next.value && $0.value.direction == .forward })
//            let rs = from.signals.first(where: { $0.value.location == next.value && $0.value.direction == .reverse })
//
//            result[next.key] = BlockTopology(forwardEndSignal: fs?.key, reverseEndSignal: rs?.key)
//        })
//        
//        let signalLocations: [ Int :  String ] = from.signals.reduce(into: [:], { result, next in
//            result[next.key] = next.value.location.id
//        })
//
//        return StateTopology(blockTopologies: blockTopologies,
//                             signalLocations: signalLocations,
//                             points: from.allPoints.map(\.id)
//        )
//    }
}

