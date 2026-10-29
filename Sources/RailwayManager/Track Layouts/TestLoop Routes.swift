//
//  TestLoop Routes.swift
//  RailwayManager
//
//  Created by Phil Diggens on 30/09/2026.
//

import Foundation

extension RailwayManager {
    // Turn round through the reversing loop without reversing the train:
    // From S (where train 1 starts) to C forward (through point 1's branch, crossing the loop closure so the train
    // enters C travelling reverse), halt, then C to S reverse (via B, point 1 straight and A).
    // The train stays DCC forward throughout and ends in S facing the other way.
    static func testLoopRoute(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("C"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(toBlock: layout.block("S"), direction: .reverse, waitTime: .station)
        
        let route = Route(id: 1, segments: [segment1, segment2])
        
        log.verbose("Route is \(route.path)")
        
        return route
    }

    // From S1 (where train 1 starts) to S2, then back to S1, both forward
    static func testLoop2Route(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("S2"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(toBlock: layout.block("S1"), direction: .forward, waitTime: .station)

        let route = Route(id: 1, segments: [segment1, segment2])
        
        log.verbose("Route is \(route.path)")
        
        return route
    }

}
