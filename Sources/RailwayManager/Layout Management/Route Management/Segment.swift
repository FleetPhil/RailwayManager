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
    
    var timeInterval: TimeInterval {
        switch self {
        case .fixed(let timeInterval):  return timeInterval
        case .halt:                     return 5
        case .station:                  return 10
        case .terminus:                 return  20
        }
    }
}

// A segment is a runtime wrapper for a path indicating any runtime parameters

struct Segment: Sendable {
    let path: Path              // Path inc direction
    let waitTime: WaitTime?     // No stop if null
    
    init(path: Path, waitTime: WaitTime?) {
        self.path = path
        self.waitTime = waitTime
    }

    //
    //    init(fromParam: SegmentParam, layout: Layout) throws {
    //        self.name = fromParam.fromBlock + "-" + fromParam.toBlock
    //
    //        guard layout.hasBlock(fromParam.fromBlock) else {
    //            throw TrainError.invalidSegment("From block \(fromParam.fromBlock) not defined for segment \(name)")
    //        }
    //        guard layout.hasBlock(fromParam.toBlock) else {
    //            throw TrainError.invalidSegment("To block \(fromParam.toBlock) not defined for segment \(name)")
    //        }
    //
    //        self.fromBlock  = layout.block(fromParam.fromBlock)
    //        self.toBlock    = layout.block(fromParam.toBlock)
    //        self.direction  = fromParam.reverse == true ? .reverse : .forward
    //
    //        self.items = [
    //            .lockPathToBlock(layout.block(fromParam.toBlock)),
    //            try Self.sensorItem(stopSensor: fromParam.stopSensor, layout: layout, toBlock: toBlock, direction: direction),
    //            try Self.waitTimeItem(fromParam.wait)
    //        ]
    //    }
    //
    //    private static func sensorItem(stopSensor: Int?, layout: Layout, toBlock: Block, direction: Direction) throws -> SegmentItem {
    //        if let stopSensor {
    //            return .moveToSensor(stopSensor, true)
    //        } else {
    //            if let s = layout.sensorForBlock(toBlock, atBlockStart: false, inDirection: direction) {
    //                return .moveToSensor(s.id, false)
    //            } else {
    //                throw TrainError.invalidSegment("No end sensor for toBlock \(toBlock.id)")
    //            }
    //        }
    //    }
}



