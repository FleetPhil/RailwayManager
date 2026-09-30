//
//  DCCDirection.swift
//  RailwayManager
//
//  Direction commanded to a loco over DCC (the decoder's forward/reverse).
//  Relative to the loco, not the track: not the same as BlockDirection.
//

import Foundation

public enum DCCDirection: String, Sendable, CaseIterable, CustomStringConvertible {
    case forward
    case reverse
    
    var oppositeDirection: DCCDirection {
        switch self {
        case .forward:      .reverse
        case .reverse:      .forward
        }
    }
    
    public var description: String {
        switch self {
        case .forward:      "DCC forward"
        case .reverse:      "DCC reverse"
        }
    }
}
