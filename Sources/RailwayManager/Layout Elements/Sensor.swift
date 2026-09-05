//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation


// Start/End locations are with respect to the forward power setting
enum SensorLocation: Comparable, Hashable {
    case start(Block, Int)            // At start of block with gap from block start
    case single(Block)                // Only sensor in the block
    case station(Block)               // At the mid point of a station (block must have start and end as well)
    case end(Block, Int)              // At end of block with gap to actual block end
    
    // Order of sensors is start, middle, end in the forward direction
    static func < (lhs: SensorLocation, rhs: SensorLocation) -> Bool {
        switch (lhs, rhs) {
        case (start, single):       true
        case (start, station):      true
        case (start, end):          true
        case (single, start):       false
        case (single, end):         true
        case (station, start):      false
        case (station, end):        true
        case (end, start):          false
        case (end, single):         false
        case (end, station):        false
        default:                    false
        }
    }

    static func == (lhs: SensorLocation, rhs: SensorLocation) -> Bool {
        switch (lhs, rhs) {
        case (start, start):        true
        case (single, single):      true
        case (end, end):            true
        case (station, station):    true
        default:                    false
        }
    }
    
    // True if the start or only sensor in the block in the specified direction
    func isStart(_ direction: Direction) -> Bool {
        switch self {
        case .start:    direction == .forward ? true : false
        case .single:   true
        case .station:  false
        case .end:      direction == .forward ? false : true
            
        }
    }
    // True if the end or only sensor in the block in the specified direction
    func isEnd(_ direction: Direction) -> Bool {
        switch self {
        case .start:    direction == .forward ? false : true
        case .single:   true
        case .station:  false
        case .end:      direction == .forward ? true : false
        }
    }

    var block: Block {
        switch self {
        case .end(let block, _):    block
        case .single(let block):    block
        case .start(let block, _):  block
        case .station(let block):   block
        }

    }
}

struct Sensor: Equatable, Sendable, CustomStringConvertible, Hashable {
    let id: Int                             // Logical ID
    let address: Int                        // Hardware address
    private(set) var location: SensorLocation
    // Signal(s) adjacent to this sensor (for station stops)
    // In the indicated direction
    private(set) var signals: [ Direction : Signal]

    nonisolated var description: String {
        return "\(id)"
    }
    
    init(id: Int, address: Int, location: SensorLocation, signals: [ Direction : Signal] = [:]) {
        self.id = id
        self.address = address
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
        case .station(let block):
            return block
        }
    }
    
    var isStation: Bool {
        switch location {
        case .station:      true
        default:            false
        }
    }
}
    


