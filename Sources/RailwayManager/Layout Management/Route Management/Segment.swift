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

// A segment of a route: from one block to another, starting in the given direction in fromBlock.
// The path between them is worked out as the train runs (RouteOperator), so it can avoid other trains.

struct Segment: Sendable, CustomStringConvertible {
    let fromBlock: Block
    let toBlock: Block
    let direction: BlockDirection   // Travel direction in fromBlock
    let waitTime: WaitTime?         // No stop if null

    init(fromBlock: Block, toBlock: Block, direction: BlockDirection, waitTime: WaitTime?) {
        self.fromBlock = fromBlock
        self.toBlock = toBlock
        self.direction = direction
        self.waitTime = waitTime
    }

    // The shortest path for the segment ignoring other trains; throws if there is none
    func nominalPath(in layout: Layout) throws -> Path {
        try layout.path(fromBlock: fromBlock, toBlock: toBlock, direction: direction)
    }

    var description: String {
        "\(fromBlock)-\(toBlock) \(direction)"
    }
}



