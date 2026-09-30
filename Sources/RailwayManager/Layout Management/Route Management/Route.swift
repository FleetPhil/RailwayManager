//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation

struct Route: CustomStringConvertible, Sendable {
    let id: Int
    let segments: [Segment]
    // The DCC direction the loco sets off in, which fixes which way it faces at the start.
    // Nil keeps the train's current facing (forward if it has not run before).
    let initialDCCDirection: DCCDirection?

    internal init(id: Int, segments: [Segment], initialDCCDirection: DCCDirection? = nil) {
        self.id = id
        self.segments = segments
        self.initialDCCDirection = initialDCCDirection
        
        log.info("Route \(id) created with \(segments.count) segments\(initialDCCDirection.map({ ", starting \($0)" }) ?? "")")
    }
        
    var startBlock: Block  {
        get throws {
            if let startBlock = segments.first?.path.pathItems.first?.fromBlock {
                return startBlock
            } else {
                throw TrainError.noStartBlockForRoute(id)
            }
        }
    }
    
    // The direction for the first segment in the route
    var initialDirection: BlockDirection {
        return segments.first?.path.direction ?? .forward
    }

    nonisolated var description: String {
        return "\(self.id)"
    }
    

}

extension Route: Equatable, Hashable {
    nonisolated static func == (lhs: Route, rhs: Route) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

