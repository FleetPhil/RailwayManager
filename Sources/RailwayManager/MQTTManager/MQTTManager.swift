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
    
    // Payload for the trains topic: one entry per train in the roster
    struct TrainInfo: Codable {
        var id: Int
        var name: String
        var address: Int        // DCC address
        var length: Int         // cm
    }
    
    private var client: MQTTClient? = nil
    private var mqttState: MQTTState = .idle
    
    private let topic = "railway"
    private let stateTopic = "/state"
    private let layoutTopic = "/topology"
    private let routeTopic = "/route"
    private let resultTopic = "/result"
    private let trainsTopic = "/trains"

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
    
    // Collects topic names from a publish listener task
    private actor TopicCollector {
        private(set) var names: Set<String> = []
        func add(_ name: String) { names.insert(name) }
    }
    
    // Remove every retained block and train state left on the broker, e.g. by a previous run or another
    // layout. The broker can't list its retained topics, so subscribe to them (retained messages arrive
    // straight after the subscription), collect their names for a moment and then clear each one by
    // publishing an empty retained payload.
    func clearRetainedStates() async throws {
        guard GlobalOptions.noMQTT == false, let client else { return }
        
        let prefix = topic + stateTopic + "/"
        let filters = [prefix + "block/+", prefix + "train/+"]
        
        let collector = TopicCollector()
        let listener = client.createPublishListener()
        let task = Task {
            for await result in listener {
                if case .success(let publish) = result,
                   publish.retain,
                   publish.topicName.hasPrefix(prefix),
                   publish.payload.readableBytes > 0 {
                    await collector.add(publish.topicName)
                }
            }
        }
        
        _ = try await client.subscribe(to: filters.map { MQTTSubscribeInfo(topicFilter: $0, qos: .atLeastOnce) })
        try await Task.sleep(for: .milliseconds(750))
        task.cancel()
        try await client.unsubscribe(from: filters)
        
        let names = await collector.names
        for name in names {
            try await client.publish(to: name, payload: ByteBuffer(), qos: .atLeastOnce, retain: true)
        }
        log.info("Cleared \(names.count) retained states")
    }
    
    func sendTopolology(fromLayout: Layout) async throws {
        // A new topology means a new run: wipe the retained states of the previous one first
        do {
            try await clearRetainedStates()
        } catch {
            log.error("Failed to clear retained states: \(error)")
        }
        
        do {
            let payload = try String(decoding: JSONEncoder().encode(stateTopology(fromLayout)), as: UTF8.self)
            // Retained so that a state viewer connecting later still receives the topology
            try await client?.publish(to: topic + layoutTopic,
                                      payload: ByteBufferAllocator().buffer(string: payload),
                                      qos: .atLeastOnce,
                                      retain: true)
        } catch {
            handleJSONError(error)
            throw TrainError.applicationError("Failed to publish layout topology")
        }
    }
    
    // Publish the train roster, retained so that a viewer connecting later still receives it
    func sendTrains(_ roster: TrainRoster) async throws {
        do {
            let trains = roster.trains.map { TrainInfo(id: $0.id, name: $0.name, address: $0.address, length: $0.length) }
            let payload = try String(decoding: JSONEncoder().encode(trains), as: UTF8.self)
            try await client?.publish(to: topic + trainsTopic,
                                      payload: ByteBufferAllocator().buffer(string: payload),
                                      qos: .atLeastOnce,
                                      retain: true)
        } catch {
            handleJSONError(error)
            throw TrainError.applicationError("Failed to publish train roster")
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

    // Publish an item's state on the state topic and, retained, on its own subtopic
    // (state/<kind>/<id>) so a viewer that connects later can read the latest state of every item.
    // A retained message is kept per topic, so the shared state topic cannot be retained itself.
    private func publishRetainedState(_ state: LayoutItemState, payload: String, kind: String) async throws {
        try await client?.publish(to: topic + stateTopic + "/" + kind + "/" + state.itemID,
                                  payload: ByteBufferAllocator().buffer(string: payload),
                                  qos: .atLeastOnce,
                                  retain: true)
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
                try await publishRetainedState(state, payload: payload, kind: "train")
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
                try await publishRetainedState(state, payload: payload, kind: "block")
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

