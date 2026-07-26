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

    internal init(id: Int, segments: [Segment]) {
        self.id = id
        self.segments = segments
        
        log.info("Route \(id) created with \(segments.count) segments")
    }
        
    var startBlock: Block {
        return segments.first!.fromBlock
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

