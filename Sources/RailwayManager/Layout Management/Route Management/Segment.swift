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
}



