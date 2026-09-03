import Foundation
import SwiftyBeaver
import ArgumentParser

let log = SwiftyBeaver.self

struct GlobalOptions {
    // Set once from the command line options at startup, before anything reads them
    nonisolated(unsafe) static var noMQTT: Bool = true
    nonisolated(unsafe) static var noCBUS: Bool = true
    nonisolated(unsafe) static var noDCC: Bool = true
    nonisolated(unsafe) static var mqttHost: String = "192.168.86.56"
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
    var mqttHost: String = ProcessInfo.processInfo.environment["MQTT_HOST"] ?? "192.168.86.56"
    
    @Option(help: "MQTT broker port")
    var mqttPort: Int = ProcessInfo.processInfo.environment["MQTT_PORT"].flatMap(Int.init) ?? 1883
    
    @Option(help: "Minimum log level")
    var logLevel: LogLevel = .verbose
    
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
                    let layout = Cellar()
                    
                    // Start MQTT
                    try await MQTTManager.shared.connect()
                    try await MQTTManager.shared.sendTopolology(fromLayout: layout)
                    
                    // Start CBUS
                    if noCBUS == false {
                        try CBUSManager.shared.setup()
                    }
                    
                    return try await RailwayManager.createLayoutManager(layout: layout)

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
                // No route source without MQTT: run the hardcoded test route
                let route = try await setupRoutes(layoutManager: layoutManager)
                let sbb = Trains.trains.first!
                try await layoutManager.runRoute(route: route, train: sbb)
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
    
    static func createLayoutManager(layout: Layout) async throws -> LayoutManager {
        guard layout.layoutIsValid() else {
            fatalError("Layout is invalid — check logs for details")
        }
        return try await LayoutManager(layout: layout)
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
                            await LayoutEventHub.shared.publish(.stopAllTrains)
                        }
                        
                    } catch {
                        log.error("Route request \(routeParams.routeID) rejected: \(error)")
                    }
                }
            } catch {
                log.error("Route request monitoring failed: \(error)")
            }
        }
    }
    
    // Validate raw route parameters and run the resulting route
    // Throws if the train is unknown or already active, or the route is not valid on the layout
    static func runRoute(from routeParams: MQTTManager.RouteParams, layoutManager: LayoutManager) async throws {
        let layout = layoutManager.layout
        
        guard let train = Trains.trains.first(where: { $0.id == routeParams.trainID }) else {
            throw TrainError.applicationError("Unknown train \(routeParams.trainID) for route \(routeParams.routeID)")
        }
        
        guard routeParams.segments.isEmpty == false else {
            throw TrainError.invalidRoute(routeParams.routeID)
        }
        
        var segments: [Segment] = []
        for segmentParams in routeParams.segments {
            guard layout.hasBlock(segmentParams.fromBlock), layout.hasBlock(segmentParams.toBlock) else {
                throw TrainError.invalidPath("Unknown block in segment \(segmentParams.fromBlock)-\(segmentParams.toBlock) of route \(routeParams.routeID)")
            }
            
            // path() throws if the blocks are not connected in the given direction
            let path = try layout.path(fromBlock: layout.block(segmentParams.fromBlock),
                                       toBlock: layout.block(segmentParams.toBlock),
                                       direction: segmentParams.direction)
            segments.append(Segment(path: path, waitTime: segmentParams.waitTime))
        }
        
        try await layoutManager.runRoute(route: Route(id: routeParams.routeID, segments: segments), train: train)
    }
    
    static func processConsoleCommand(_ input: String, _ layoutManager: LayoutManager) async throws {
        if input.starts(with: "sn") {            // Sensor north
            if let sensorAddress = Int(input.dropFirst(2)) {
                await LayoutEventHub.shared.publish(.didSetSensor(sensorAddress, .north))
            }
        }
        if input.starts(with: "ss") {            // Sensor south
            if let sensorAddress = Int(input.dropFirst(2)) {
                await LayoutEventHub.shared.publish(.didSetSensor(sensorAddress, .south))
            }
        }
        if input.starts(with: "p") {
            await LayoutEventHub.shared.publish(.didPushButton(3))
        }
        if input.starts(with: "st") {
            await layoutManager.printStatus()
        }
    }
}


