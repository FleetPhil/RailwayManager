// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import SwiftyBeaver

nonisolated(unsafe) var log = SwiftyBeaver.self

struct GlobalOptions {
    static let noMQTT: Bool = false
}

@main
struct CommandLineTool {
    static func main() async {
        
        print("Starting async task...")
        
        do {
            let point = DCCHardwarePoint(id: 52, address: 52)
            try await point.resetPoint(52, toDirection: .splitStraight)
        } catch {
            log.error("Error encountered: \(error)")
        }
        
        print("Task finished.")
    }
}

