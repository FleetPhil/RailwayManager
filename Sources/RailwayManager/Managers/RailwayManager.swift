import Foundation
import SwiftyBeaver
import ArgumentParser

let log = SwiftyBeaver.self

struct GlobalOptions {
    // Set once from the command line options at startup, before anything reads them
    nonisolated(unsafe) static var noMQTT: Bool = true
    nonisolated(unsafe) static var noCBUS: Bool = true
    nonisolated(unsafe) static var noDCC: Bool = true
    nonisolated(unsafe) static var mqttHost: String = ""
    nonisolated(unsafe) static var mqttPort: Int = 1883
    // Allow test commands (e.g. simulated sensor events) to be entered on stdin
    nonisolated(unsafe) static var consoleTestCommands: Bool = true
}

// Minimum log level selectable from the command line
enum LogLevel: String, CaseIterable, ExpressibleByArgument {
    case verbose, debug, info, warning, error
    
    var swiftyBeaverLevel: SwiftyBeaver.Level {
        switch self {
        case .verbose:  .verbose
        case .debug:    .debug
        case .info:     .info
        case .warning:  .warning
        case .error:    .error
        }
    }
}

// Track layouts selectable from the command line
enum LayoutName: String, CaseIterable, ExpressibleByArgument {
    case testLoop2 = "TestLoop2"
    case final = "Final"
    
    func makeLayout() -> Layout {
        switch self {
        case .testLoop2:    TestLoop2()
        case .final:        Final26()
        }
        
    }
}

@main
struct RailwayManager: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "RailwayManager",
        abstract: "Model railway layout controller")
    
    @Flag(name: .customLong("noMQTT", withSingleDash: true),
          help: "Run without publishing state to the MQTT broker")
    var noMQTT = false
    
    @Flag(name: .customLong("noCBUS", withSingleDash: true),
          help: "Run without the CBUS serial hardware interface")
    var noCBUS = false
    
    @Flag(name: .customLong("noDCC", withSingleDash: true),
          help: "Run without the DCC train commands")
    var noDCC = false

    @Option(help: "MQTT broker host")
    var mqttHost: String = ProcessInfo.processInfo.environment["MQTT_HOST"] ?? "192.168.68.52"
    
    @Option(help: "MQTT broker port")
    var mqttPort: Int = ProcessInfo.processInfo.environment["MQTT_PORT"].flatMap(Int.init) ?? 1883
    
    @Option(help: "Minimum log level")
    var logLevel: LogLevel = .verbose
    
    @Option(name: .customLong("layout", withSingleDash: true),
            help: "Track layout to run (\(LayoutName.allCases.map(\.rawValue).joined(separator: ", ")))")
    var layoutName: LayoutName = .final
    
    @Option(name: .customLong("trains", withSingleDash: true),
            help: "Trains JSON file (default \(TrainRoster.defaultFileURL.path) if it exists, otherwise the built-in trains)")
    var trainsPath: String?
    
    func run() throws {
        // Apply the options before anything reads them
        GlobalOptions.noMQTT = noMQTT
        GlobalOptions.noCBUS = noCBUS
        GlobalOptions.noDCC  = noDCC
        GlobalOptions.mqttHost = mqttHost
        GlobalOptions.mqttPort = mqttPort
        
        Self.setupLog(minLevel: logLevel.swiftyBeaverLevel)
        
        Task {
            await runLayout()
        }
        RunLoop.current.run()
    }
    
    private func runLayout() async {
        var layoutManager: LayoutManager {
            get async {
                do {
                    let layout = layoutName.makeLayout()
                    let trains = try TrainRoster.load(path: trainsPath)
                    
                    // Start MQTT
                    try await MQTTManager.shared.connect()
                    try await MQTTManager.shared.sendTopolology(fromLayout: layout)
                    try await MQTTManager.shared.sendTrains(trains)

                    // State is not retained, so tell viewers every train is idle (location unknown) until a route starts
                    for train in trains.trains {
                        try await MQTTManager.shared.sendTrainState(train: train, state: .idle(nil))
                    }
                    
                    // Start CBUS
                    if noCBUS == false {
                        try CBUSManager.shared.setup()
                    }
                    
                    return try await RailwayManager.createLayoutManager(layout: layout, trains: trains)

                } catch {
                    fatalError("*** Failed to initialise layout: \(error)")
                }
            }
        }
        
        // Create and run the manager
        await Self.runManager(layoutManager: layoutManager)
    }
    
    static func setupLog(minLevel: SwiftyBeaver.Level) {
        let logFormat = "$DHH:mm:ss.SSS$d $d $N:$l $L: $M"
        let console = ConsoleDestination()
        console.format = logFormat
        console.minLevel = minLevel
        log.addDestination(console)
    }
    
    // Main run function
    static func runManager(layoutManager: LayoutManager) async {
        log.info("Starting manager...")
        
#if os(OSX)
        GlobalOptions.consoleTestCommands = true
#else
        GlobalOptions.consoleTestCommands = false
#endif
        
        do {
            if GlobalOptions.noMQTT {
                // No route source without MQTT: run the hardcoded test route for the layout, if any
                if let route = try await setupRoutes(layoutManager: layoutManager) {
                    try await layoutManager.runRoute(route: route, train: layoutManager.trains.trains[0])
                } else {
                    log.info("No built-in route for layout \(type(of: layoutManager.layout))")
                }
            } else {
                // Run routes as they are requested over MQTT
                monitorRouteRequests(layoutManager: layoutManager)
            }
            
            // Start task to process test commands if on macOS
            while GlobalOptions.consoleTestCommands {
                if let input = readLine() {
                    try await processConsoleCommand(input, layoutManager)
                }
            }
        } catch let error as TrainError {
            if error.isFatal {
                try! await layoutManager.setState(.error)
                fatalError("\(error)")
            } else {
                log.error("Non-fatal: \(error)")
            }
        } catch let error as CBUSError {
            if error.isFatal {
                fatalError("Fatal CBUS Error: \(error)")
            } else {
                log.error("Non-fatal CBUS Error: \(error)")
            }
        } catch {
            // Log error and carry on
            log.error("Unexpected error: \(error)")
        }
        
        log.info("Manager setup finished.")
    }
    
    static func createLayoutManager(layout: Layout, trains: TrainRoster) async throws -> LayoutManager {
        do {
            try layout.layoutIsValid()
            try layout.checkInitialTrainBlocks(trains)
        } catch {
            print(error)
            throw TrainError.layoutError("Unable to initialise layout")
        }

        let layoutManager = try await LayoutManager(layout: layout, trains: trains)
        
        // Put the trains in their starting blocks (checked above)
        for (trainID, block) in layout.initialTrainBlocks.sorted(by: { $0.key < $1.key }) {
            if let train = trains.train(id: trainID) {
                try await layoutManager.placeTrain(train, in: block)
            }
        }
        return layoutManager
    }
    
    // Monitor route requests received over MQTT and run each valid one
    // A rejected route is logged and monitoring continues
    static func monitorRouteRequests(layoutManager: LayoutManager) {
        Task {
            do {
                guard let requests = try await MQTTManager.shared.routeRequests() else { return }
                
                for await routeParams in requests {
                    do {
                        switch routeParams.command {
                        case .runRoute:
                            try await runRoute(from: routeParams, layoutManager: layoutManager)
                        case .stopAllTrains:
                            await LayoutEventHub.shared.publish(.stopAllTrainsResetTrack)
                        case .endManager:
                            await LayoutEventHub.shared.publish(.didPushButton(3))  // End manager
                        }
                        await publishRouteResult(for: routeParams, error: nil)
                        
                    } catch {
                        log.error("Route request \(routeParams.routeID) rejected: \(error)")
                        await publishRouteResult(for: routeParams, error: error)
                    }
                }
            } catch {
                log.error("Route request monitoring failed: \(error)")
            }
        }
    }
    
    // Reply to a route request on the result topic: success, or the error that rejected it.
    // A publish failure is only logged.
    private static func publishRouteResult(for routeParams: MQTTManager.RouteParams, error: Error?) async {
        do {
            if let error {
                try await MQTTManager.shared.sendRouteError("\(error)", routeID: routeParams.routeID, trainID: routeParams.trainID)
            } else {
                try await MQTTManager.shared.sendRouteSuccess(routeID: routeParams.routeID, trainID: routeParams.trainID)
            }
        } catch {
            log.error("Failed to publish result for route request \(routeParams.routeID): \(error)")
        }
    }
    
    // Validate raw route parameters and run the resulting route
    // Throws if the train is unknown or already active, or the route is not valid on the layout
    static func runRoute(from routeParams: MQTTManager.RouteParams, layoutManager: LayoutManager) async throws {
        let layout = layoutManager.layout
        
        guard let train = layoutManager.trains.train(id: routeParams.trainID) else {
            throw TrainError.applicationError("Unknown train \(routeParams.trainID) for route \(routeParams.routeID)")
        }
        
        var segments: [Segment] = []
        for segmentParams in routeParams.segments {
            guard layout.hasBlock(segmentParams.toBlock) else {
                throw TrainError.invalidPath("Unknown block \(segmentParams.toBlock) in route \(routeParams.routeID)")
            }
            segments.append(Segment(toBlock: layout.block(segmentParams.toBlock),
                                    direction: segmentParams.direction,
                                    waitTime: segmentParams.waitTime,
                                    stopAt: segmentParams.stopAt ?? .end))
        }
        
        let route = Route(id: routeParams.routeID, segments: segments, initialDCCDirection: routeParams.initialDCCDirection)
        
        // The route is validated when it is run, from where the train is
        log.verbose("Route is: \(route.path)")
        
        try await layoutManager.runRoute(route: route, train: train)
    }
    
    // Simulate a train passing over the sensor with the given logical id: a 1s pulse in the first
    // orientation, then a 1s pulse in the second orientation starting 2s after the first
    private static func simulateSensorPulses(_ sensorID: Int, first: SensorEventOrientation, second: SensorEventOrientation, _ layoutManager: LayoutManager) async {
        // Sensor events carry the hardware address
        guard let sensorAddress = layoutManager.layout.sensors.first(where: { $0.id == sensorID })?.address else {
            log.error("Unknown sensor id \(sensorID)")
            return
        }
        
        await LayoutEventHub.shared.publish(.didSetSensor(sensorAddress, first))
        Task {
            // Task.sleep only throws if the task is cancelled, which stops the simulation
            do {
                try await Task.sleep(for: .seconds(1))
                await LayoutEventHub.shared.publish(.didUnsetSensor(sensorAddress, first))
                
                try await Task.sleep(for: .seconds(3))
                await LayoutEventHub.shared.publish(.didSetSensor(sensorAddress, second))
                
                try await Task.sleep(for: .seconds(1))
                await LayoutEventHub.shared.publish(.didUnsetSensor(sensorAddress, second))
            } catch {
                log.debug("Sensor \(sensorID) simulation cancelled")
            }
        }
    }
    
    static func processConsoleCommand(_ input: String, _ layoutManager: LayoutManager) async throws {
        
        if input.starts(with: "sn") {            // Sensor north, followed by south
            if let sensorID = Int(input.dropFirst(2)) {
                await simulateSensorPulses(sensorID, first: .north, second: .south, layoutManager)
            }
        }
        if input.starts(with: "ss") {            // Sensor south, followed by north
            if let sensorID = Int(input.dropFirst(2)) {
                await simulateSensorPulses(sensorID, first: .south, second: .north, layoutManager)
            }
        }
        if input.starts(with: "x") {
            await LayoutEventHub.shared.publish(.didPushButton(3))
        }
        
        if input.starts(with: "st") {
            await layoutManager.printStatus()
        }

        if input.starts(with: "dp") {            // Dump block routes and paths to a file
            let url = try layoutManager.layout.writeTopologyDump()
            log.info("Topology written to \(url.path)")
        }

        if input.starts(with: "tb") {            // Place train: tb <train> <block>
            let args = input.dropFirst(2).split(separator: " ").map(String.init)
            
            // Block ids are upper case
            guard args.count == 2,
                  let trainID = Int(args[0]),
                  let train = layoutManager.trains.train(id: trainID),
                  layoutManager.layout.hasBlock(args[1].uppercased()) else {
                log.error("Usage: tb <train> <block> (known train and block)")
                return
            }
            
            // A refused placement is logged so that the console keeps running
            do {
                try await layoutManager.placeTrain(train, in: layoutManager.layout.block(args[1].uppercased()))
            } catch {
                log.error("Can't place train \(trainID): \(error)")
            }
        }

        if input.starts(with: "rr") {            // Run route: rr <toBlock> <f|r> [train] [e]
            var args = input.dropFirst(2).split(separator: " ").map(String.init)

            // A trailing e stops the train as soon as it is wholly in toBlock
            let stopAt: StopPosition = args.last == "e" ? .entered : .end
            if stopAt == .entered {
                args.removeLast()
            }

            // Train id is optional and defaults to 1
            guard args.count == 2 || args.count == 3,
                  let direction: BlockDirection = ["f": .forward, "r": .reverse][args[1]],
                  let trainID = args.count == 3 ? Int(args[2]) : 1 else {
                log.error("Usage: rr <toBlock> <f|r> [train] [e]")
                return
            }

            // Block ids are upper case
            let toBlock = args[0].uppercased()

            // Test command: single segment route, route id fixed at 1
            let routeParams = MQTTManager.RouteParams(
                command: .runRoute,
                routeID: 1,
                trainID: trainID,
                segments: [.init(toBlock: toBlock, direction: direction, waitTime: .halt, stopAt: stopAt)])

            // A rejected route is logged so that the console keeps running
            do {
                try await runRoute(from: routeParams, layoutManager: layoutManager)
            } catch {
                log.error("Route to \(toBlock) rejected: \(error)")
            }
        }
    }
}


