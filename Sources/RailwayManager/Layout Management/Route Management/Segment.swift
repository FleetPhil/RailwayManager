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

// A segment is a runtime wrapper for a path indicating any runtime parameters

struct Segment: Sendable {
    let path: Path              // Path inc direction
    let waitTime: WaitTime?     // No stop if null
    
    init(path: Path, waitTime: WaitTime?) {
        self.path = path
        self.waitTime = waitTime
    }
}



