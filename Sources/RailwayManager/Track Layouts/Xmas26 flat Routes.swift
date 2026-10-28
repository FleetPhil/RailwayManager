//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 28/10/2026.
//

import Foundation

extension RailwayManager {
    
    // B to H forward, then back to B in reverse
    static func Xmas26FlatRoute(layout: Layout) throws -> Route {
        let segment1 = Segment(fromBlock: layout.block("D"), toBlock: layout.block("G"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(fromBlock: layout.block("G"), toBlock: layout.block("C"), direction: .forward, waitTime: .station)
        let route1 = Route(id: 1, segments: [segment1, segment2])
        try route1.validate(in: layout)
        
        log.info("Route is \(route1)")
        
        return route1
    }
}
