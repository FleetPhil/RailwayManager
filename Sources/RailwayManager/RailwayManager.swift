// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import SwiftyBeaver

nonisolated(unsafe) var log = SwiftyBeaver.self

struct GlobalOptions {
    static let noMQTT: Bool = true
    static let noCBUS: Bool = true
}

@main
struct CommandLineTool {
    static func main() {
        setupLog()
        
        Task {
            await runManager()
        }
        
        RunLoop.current.run()
        
    }
    
    static func setupLog() {
        let logFormat = "$Dyyyy-MM-dd HH:mm:ss $d $N.$F:$l $L: $M"
        let console = ConsoleDestination()
        console.minLevel = .verbose
        log.addDestination(console)
    }
    
    static func runManager() async {
        log.info("Starting manager...")
        
        do {
            let layout = TestTrack2()
            log.info("Is valid: \(layout.layoutIsValid())")
            
            let layoutManager = try await LayoutManager(layout: layout)
                        
            let route = try layout.route(id: 1, fromBlock: layout.block("D"), toSensor: layout.sensor(2)!, direction: .forward)
            
            let train = Train(trainParams: TrainParams(id: 1, name: "Train 1", address: 20, trainSpeeds: [:]))
            try await layoutManager.runRoute(route: route, train: train)
            
            // Start task to process test commands if on macOS
    #if os(OSX)
            while true {
                if let input = readLine() {
                    if input.starts(with: "sn") {            // Sensor north
                        if let sensorID = Int(input.dropFirst(2)) {
                            await LayoutEventHub.shared.publish(.didSetSensor(sensorID, .north))
                        }
                    }
                    if input.starts(with: "ss") {            // Sensor south
                        if let sensorID = Int(input.dropFirst(2)) {
                            await LayoutEventHub.shared.publish(.didSetSensor(sensorID, .south))
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
    #endif
        } catch {
            log.info("Error encountered: \(error)")
        }
        
        log.info("Manager finished.")
    }
    
    static func trainParams() -> TrainParams {
        TrainParams(id: 1, name: "Train 1", address: 20, trainSpeeds: [:])
    }
}



