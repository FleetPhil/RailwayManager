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
    
    // Payload for the result topic: the outcome of a route request, the route and train it concerns
    // and the error text (empty on success)
    struct RouteResult: Codable {
        var success: Bool
        var routeID: Int?
        var trainID: Int?
        var message: String
    }
    
    private var client: MQTTClient? = nil
    private var mqttState: MQTTState = .idle
    
    private let topic = "railway"
    private let stateTopic = "/state"
    private let layoutTopic = "/topology"
    private let routeTopic = "/route"
    private let resultTopic = "/result"

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
            try? await client?.shutdown()       // In case connection is open

            do {
                try await client?.connect()
                mqttState = .connected
            } catch {
                mqttState = .error
                throw TrainError.MQTTConnectFail(error.localizedDescription)
            }
            
        case .connected:
            break
        case .error:
            break
            
        }
    }
    
    func disconnect() throws {
        try client?.syncShutdownGracefully()
        client = nil
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
        case .reserved(let train, _):
            itemState = "reserved"
            additionalInformation = "Train \(train)"
        case .occupied(let train, _):
            itemState = "occupied"
            additionalInformation = "Train \(train)"
        case .vacating(let train, _):
            itemState = "vacating"
            additionalInformation = "Train \(train)"
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
    
    // Publish a successful route request result (empty message) on the result topic
    func sendRouteSuccess(routeID: Int? = nil, trainID: Int? = nil) async throws {
        try await sendRouteResult(RouteResult(success: true, routeID: routeID, trainID: trainID, message: ""))
    }
    
    // Publish a failed route request result with the error message on the result topic
    func sendRouteError(_ message: String, routeID: Int? = nil, trainID: Int? = nil) async throws {
        try await sendRouteResult(RouteResult(success: false, routeID: routeID, trainID: trainID, message: message))
    }
    
    private func sendRouteResult(_ result: RouteResult) async throws {
        do {
            let payload = try String(decoding: JSONEncoder().encode(result), as: UTF8.self)
            
            if GlobalOptions.noMQTT {
                log.debug("Payload: \(payload)")
            } else {
                try await client?.publish(to: topic + resultTopic,
                                          payload: ByteBufferAllocator().buffer(string: payload),
                                          qos: .atLeastOnce)
            }
        } catch {
            handleJSONError(error)
            throw TrainError.applicationError("MQTT publish failed for route result")
        }
    }
    
    // Subscribe to the route topic and return a stream of the route requests received on it
    // Invalid payloads are logged and skipped; returns nil if MQTT is disabled
    func routeRequests() async throws -> AsyncStream<RouteParams>? {
        guard GlobalOptions.noMQTT == false, let client else { return nil }
        
        let routeTopicName = topic + routeTopic
        _ = try await client.subscribe(to: [MQTTSubscribeInfo(topicFilter: routeTopicName, qos: .atLeastOnce)])
        
        let listener = client.createPublishListener()
        let (stream, continuation) = AsyncStream.makeStream(of: RouteParams.self)
        
        let task = Task {
            for await result in listener {
                switch result {
                case .success(let publish):
                    guard publish.topicName == routeTopicName else { continue }
                    
                    guard let payload = publish.payload.getString(at: publish.payload.readerIndex,
                                                                  length: publish.payload.readableBytes),
                          let data = payload.data(using: .utf8) else {
                        log.error("Ignored route request with unreadable payload")
                        continue
                    }
                    
                    do {
                        continuation.yield(try JSONDecoder().decode(RouteParams.self, from: data))
                    } catch {
                        log.error("Ignored invalid route request: \(error)")
                    }
                    
                case .failure(let error):
                    log.error("MQTT route listener error: \(error)")
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        
        return stream
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
    // Raw route data received over MQTT: the train to run and the Layout.path()
    // parameters for each segment of the route
    struct RouteParams: Codable, Sendable {
        struct SegmentParams: Codable, Sendable {
            var fromBlock: String
            var toBlock: String
            var direction: BlockDirection
            var waitTime: WaitTime?         // No stop at segment end if nil
        }
        
        // MARK: Commands for the railway manager
        enum RouteCommand: Int, Codable, Sendable {
            case runRoute       = 1
            case stopAllTrains  = 2
            case endManager     = 3
        }

        var command: RouteCommand
        var routeID: Int
        var trainID: Int
        var initialDCCDirection: DCCDirection?     // Keep the train's current facing if nil
        var segments: [SegmentParams]
    }
    
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

