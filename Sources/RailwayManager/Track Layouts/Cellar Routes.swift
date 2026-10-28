//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 04/08/2026.
//

import Foundation

extension RailwayManager {
    // The hard-coded route run with -noMQTT, or nil if the layout has none
    static func setupRoutes(layoutManager: LayoutManager) async throws -> Route?  {
        let layout = layoutManager.layout
        switch layout {
        case is Cellar:     return try cellarRoute(layout: layout)
        case is TestLoop:   return try testLoopRoute(layout: layout)
        case is TestLoop2:  return try testLoop2Route(layout: layout)
        case is Xmas26Flat: return try Xmas26FlatRoute(layout: layout)
        default:            return nil
        }
    }
    
    // B to H forward, then back to B in reverse
    private static func cellarRoute(layout: Layout) throws -> Route {
        let segment1 = Segment(fromBlock: layout.block("B"), toBlock: layout.block("H"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(fromBlock: layout.block("H"), toBlock: layout.block("B"), direction: .reverse, waitTime: .station)
        let route1 = Route(id: 1, segments: [segment1, segment2])
        try route1.validate(in: layout)
        
        log.info("Route is \(route1)")
        
        return route1
    }
    

}
