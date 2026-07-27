//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation


// Start/End locations are with respect to the forward power setting
enum SensorLocation: Comparable {
    
    case start(Block, Int)            // At start of block with gap from block start
    case single(Block)                // Only sensor in the block
    case end(Block, Int)              // At end of block with gap to actual block end
    
    // Order of sensors is start, middle, end in the forward direction
    static func < (lhs: SensorLocation, rhs: SensorLocation) -> Bool {
        switch (lhs, rhs) {
        case (start, single):   true
        case (start, end):      true
        case (single, start):   false
        case (single, end):     true
        case (end, start):      false
        case (end, single):     false
        default:                false
        }
    }

    static func == (lhs: SensorLocation, rhs: SensorLocation) -> Bool {
        switch (lhs, rhs) {
        case (start, start):    true
        case (single, single):  true
        case (end, end):        true
        default:                false
        }
    }
    
    // True if the start or only sensor in the block
    var isStart: Bool {
        switch self {
        case .start, .single:       true
        case .end:                  false
            
        }
    }
    // True if the end or only sensor in the block
    var isEnd: Bool {
        switch self {
        case .end, .single:       true
        case .start:              false
        }
    }
    
    var block: Block {
        switch self {
        case .end(let block, _):    block
        case .single(let block):    block
        case .start(let block, _):  block
        }

    }
}

struct Sensor: Equatable, Sendable, CustomStringConvertible {
    let id: Int                             // As known to controller
    private(set) var location: SensorLocation
    // Signal(s) adjacent to this sensor (for station stops)
    // In the indicated direction
    private(set) var signals: [ Direction : Signal]

    nonisolated var description: String {
        return "\(id)"
    }
    
    init(id: Int, location: SensorLocation, signals: [ Direction : Signal] = [:]) {
        self.id = id
        self.location = location
        self.signals = signals
    }
    
    // Block that this sensor is located in
    var block: Block {
        switch location {
        case .start(let block, _):
            return block
        case .end(let block, _):
            return block
        case .single(let block):
            return block
        }
    }
}
    


