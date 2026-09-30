//
//  BlockDirection.swift
//  RailwayManager
//
//  Direction of travel through a block, relative to the block's own orientation
//  (forward = from the block's reverse-end exit towards its forward-end exit).
//  Not the same as the DCC direction commanded to a loco.
//

import Foundation

public enum BlockDirection: String, Codable, Sendable, CaseIterable, CustomStringConvertible {
    case forward
    case reverse
    
    var oppositeDirection: BlockDirection {
        switch self {
        case .forward:      .reverse
        case .reverse:      .forward
        }
    }
    
    public var description: String {
        switch self {
        case .forward:      "forward"
        case .reverse:      "reverse"
        }
    }
}
