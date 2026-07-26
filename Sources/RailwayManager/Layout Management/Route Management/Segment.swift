//
//  Segment.swift
//  ModelRailway
//
//  Created by Phil Diggens on 06/01/2026.
//

import Foundation

// Waiting time depends on train if moving after points, or fixed in station etc
enum WaitTime: Sendable, Equatable {
    case fixed(TimeInterval)
    case halt
    case station
    case terminus
}

// A segment is a route section that allocates track for the indicated direction while active
struct SegmentParam: Codable, Equatable {
    var fromBlock: String       // Start block
    var toBlock: String         // End Block
    var reverse: Bool?          // Assumes forward if not present
    var stopSensor: Int?        // Assumes no stop if not present
    var wait: String?              // Wait time
}

enum SegmentItem: Equatable {
    // Lock the path to the end block
    case lockPathToBlock(_ block: Block)
    
    // Move to the sensor, stop if true
    case moveToSensor(Int, Bool)
    
    // Wait
    case wait(WaitTime)
}

struct Segment: Sendable {
    let name: String
    let fromBlock: Block
    let toBlock: Block
    let direction: Direction
    let items: [SegmentItem]

    init(name: String, fromBlock: Block, toBlock: Block, direction: Direction, items: [SegmentItem]) {
        self.name = name
        self.fromBlock = fromBlock
        self.toBlock = toBlock
        self.direction = direction
        self.items = items
    }
    
    init(fromParam: SegmentParam, layout: Layout) throws {
        self.name = fromParam.fromBlock + "-" + fromParam.toBlock
        
        guard layout.hasBlock(fromParam.fromBlock) else {
            throw TrainError.invalidSegment("From block \(fromParam.fromBlock) not defined for segment \(name)")
        }
        guard layout.hasBlock(fromParam.toBlock) else {
            throw TrainError.invalidSegment("To block \(fromParam.toBlock) not defined for segment \(name)")
        }
        
        self.fromBlock  = layout.block(fromParam.fromBlock)
        self.toBlock    = layout.block(fromParam.toBlock)
        self.direction  = fromParam.reverse == true ? .reverse : .forward
        
        self.items = [
            .lockPathToBlock(layout.block(fromParam.toBlock)),
            try Self.sensorItem(stopSensor: fromParam.stopSensor, layout: layout, toBlock: toBlock, direction: direction),
            try Self.waitTimeItem(fromParam.wait)
        ]
    }

    private static func sensorItem(stopSensor: Int?, layout: Layout, toBlock: Block, direction: Direction) throws -> SegmentItem {
        if let stopSensor {
            return .moveToSensor(stopSensor, true)
        } else {
            if let s = layout.sensorForBlock(toBlock, atBlockStart: false, inDirection: direction) {
                return .moveToSensor(s.id, false)
            } else {
                throw TrainError.invalidSegment("No end sensor for toBlock \(toBlock.id)")
            }
        }
    }

    private static func waitTimeItem(_ waitParam: String?) throws -> SegmentItem {
        if let waitTime = waitParam {
            switch waitTime {
            case "halt":
                return .wait(.halt)
            case "station":
                return .wait(.station)
            case "terminus":
                return .wait(.terminus)
            default:
                if let timeInterval = Double(waitTime) {
                    return .wait(.fixed(timeInterval))
                } else {
                    throw TrainError.invalidSegment("Unknown wait time \(waitTime)")
                }
            }
        } else {
            // TEMP
            return .wait(.halt)
        }
    }
}

extension Segment: Equatable {
    static func == (lhs: Segment, rhs: Segment) -> Bool {
        lhs.name == rhs.name && lhs.direction == rhs.direction
    }
}


