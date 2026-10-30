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

// Coded as a plain string ("halt", "station", "terminus") or a number of seconds for a fixed wait
extension WaitTime: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let seconds = try? container.decode(TimeInterval.self) {
            self = .fixed(seconds)
            return
        }
        
        switch try container.decode(String.self) {
        case "halt":        self = .halt
        case "station":     self = .station
        case "terminus":    self = .terminus
        case let unknown:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown wait time '\(unknown)' (expected halt, station, terminus or a number of seconds)")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .fixed(let seconds):   try container.encode(seconds)
        case .halt:                 try container.encode("halt")
        case .station:              try container.encode("station")
        case .terminus:             try container.encode("terminus")
        }
    }
}

// Where a train stops in a segment's end block: when the front reaches the stop sensor (the station
// sensor, otherwise the end of the block), or as soon as it is wholly in the block (the rear passes the
// start of the block). Coded as "end" or "entered"
enum StopPosition: String, Codable, Sendable {
    case end
    case entered
}

// A segment of a route: to a block, starting in the given direction in the block the segment starts
// from (where the train is for the first segment, otherwise where the previous segment ended).
// The path is worked out as the train runs (RouteOperator), so it can avoid other trains.

struct Segment: Sendable, CustomStringConvertible {
    let toBlock: Block
    let direction: BlockDirection   // Travel direction in the block the segment starts from
    let waitTime: WaitTime?         // No stop if null
    let stopAt: StopPosition        // Where the train stops in toBlock

    init(toBlock: Block, direction: BlockDirection, waitTime: WaitTime?, stopAt: StopPosition = .end) {
        self.toBlock = toBlock
        self.direction = direction
        self.waitTime = waitTime
        self.stopAt = stopAt
    }

    // The shortest path for the segment from the given block ignoring other trains; throws if there is none
    func nominalPath(from fromBlock: Block, in layout: Layout) throws -> Path {
        try layout.path(fromBlock: fromBlock, toBlock: toBlock, direction: direction)
    }

    var description: String {
        "\(toBlock) \(direction)\(stopAt == .entered ? " entered" : "")"
    }
}



