//
//  TrackResource.swift
//  ModelRailway
//
//  Created by Phil Diggens on 11/03/2025.
//

import Foundation

enum TrackResource: Sendable, CustomStringConvertible {
    case point(Point)
    case block(Block)
    
    nonisolated var description: String {
        switch self {
        case .point(let point):
            return "point \(point)"
        case .block(let block):
            return "block \(block)"
        }
    }
}

extension TrackResource: Equatable {
    static func ==(lhs: TrackResource, rhs: TrackResource) -> Bool {
        switch (lhs, rhs) {
        case (.point(let lhsPoint), .point(let rhsPoint)):
            return lhsPoint.id == rhsPoint.id
        case (.block(let lhsBlock), .block(let rhsBlock)):
            return lhsBlock.id == rhsBlock.id
        default:
            return false
        }
    }
}
