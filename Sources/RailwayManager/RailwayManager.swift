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
            
            let path1 = try layout.path(fromBlock: layout.block("D"),
                                       toBlock: layout.block("C"),
                                       direction: .forward)
            let segment1 = Segment(path: path1, waitTime: .station)
            let path2 = try layout.path(fromBlock: layout.block("C"),
                                       toBlock: layout.block("A1"),
                                       direction: .forward)
            let segment2 = Segment(path: path2, waitTime: nil)
            
            let route1 = Route(id: 1, segments: [segment1, segment2])
            
            let train1 = Train(trainParams: TrainParams(id: 1, name: "Train 1", address: 20, trainSpeeds: [:]))
            try await layoutManager.runRoute(route: route1, train: train1)

//            let path2 = try layout.path(fromBlock: layout.block("A1"),
//                                       toBlock: layout.block("A2"),
//                                       direction: .forward)
//            let segment2 = Segment(path: path2, waitTime: nil)
//            let route2 = Route(id: 2, segments: [segment2])
//            
//            let train2 = Train(trainParams: TrainParams(id: 2, name: "Train 2", address: 21, trainSpeeds: [:]))
//            try await layoutManager.runRoute(route: route2, train: train2)

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



