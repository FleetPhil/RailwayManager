//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 28/10/2026.
//

import Foundation

extension RailwayManager {
    
    // From D (where train 1 starts) to G, then on to C, both forward
    static func Xmas26FlatRoute(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("G"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(toBlock: layout.block("C"), direction: .forward, waitTime: .station)
        let route1 = Route(id: 1, segments: [segment1, segment2])
        
        log.info("Route is \(route1)")
        
        return route1
    }
}
