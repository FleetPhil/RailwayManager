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
        case train      = 4
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
        // Broker location is set from the command line options (or their env/default values)
        client = MQTTClient(
            host: GlobalOptions.mqttHost,
            port: GlobalOptions.mqttPort,
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
    
    func sendTopolology(fromLayout: Layout) async throws {
        do {
            let payload = try String(decoding: JSONEncoder().encode(stateTopology(fromLayout)), as: UTF8.self)
            try await client?.publish(to: topic + layoutTopic,
                                      payload: ByteBufferAllocator().buffer(string: payload),
                                      qos: .atLeastOnce)
        } catch {
            handleJSONError(error)
            throw TrainError.applicationError("Failed to publish layout topology")
        }
    }
    
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
            throw TrainError.applicationError("MQTT publish failed for signal state")
        }
    }

    func sendPointState(point: Point, state: PointDirection, associatedBlock: String?) async throws {
        do {
            let state = LayoutItemState(itemType: .point,
                                        itemID: "\(point.id)",
                                        itemState: state.rawValue + "/" + "\(associatedBlock ?? "-")")
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
            throw TrainError.applicationError("MQTT publish failed for point state")
        }
    }

    func sendTrainState(train: Train, state: TrainRuntimeState) async throws {
        do {
            let state = LayoutItemState(itemType: .train,
                                        itemID: "\(train.id)",
                                        itemState: state.description)
            let payload = try String(decoding: JSONEncoder().encode(state), as: UTF8.self)
            
            if GlobalOptions.noMQTT {
                log.debug("Payload: \(payload)")
            } else {
                try await client?.publish(to: topic + stateTopic,
                                          payload: ByteBufferAllocator().buffer(string: payload),
                                          qos: .atLeastOnce)
            }
        } catch {
            handleJSONError(error)
            throw TrainError.applicationError("MQTT publish failed for train state")
        }
    }

    func sendBlockRuntimeState(block: Block,
                               blockState: BlockRuntimeState,
                               directionLocks: [Train] = []
    ) async throws {
        var itemState: String = ""
        var additionalInformation: String = ""
        
        switch blockState {
        case .vacant:
            itemState = "vacant"
        case .reserved(let train):
            itemState = "reserved"
            additionalInformation = "Train \(train)"
        case .occupied(let train), .vacating(let train):
            itemState = "occupied"
        }
        
        do {
            if directionLocks.isEmpty == false {
                let lockString: String = "Locks: ".appending(directionLocks.map({ "\($0.id)" } ).joined(separator: ","))
                additionalInformation.append(lockString)
            }
            
            let state = LayoutItemState(itemType: .block,
                                        itemID: block.id,
                                        itemState: itemState,
                                        additionalInformation: additionalInformation.isEmpty ? nil : additionalInformation)
            
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
            throw TrainError.applicationError("MQTT publish failed for block state")
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

    func stateTopology(_ from: Layout) -> StateTopology {
        let blockTopologies: [ String : BlockTopology ] = from.blocks.reduce(into: [:], { result, next in
            let fs = from.signals.first(where: { $0.location == next && $0.direction == .forward })
            let rs = from.signals.first(where: { $0.location == next && $0.direction == .reverse })

            result[next.id] = BlockTopology(forwardEndSignal: fs?.id, reverseEndSignal: rs?.id)
        })
        
        let signalLocations: [ Int :  String ] = from.signals.reduce(into: [:], { result, next in
            result[next.id] = next.location.id
        })

        return StateTopology(blockTopologies: blockTopologies,
                             signalLocations: signalLocations,
                             points: from.points.map(\.id)
        )
    }
}

