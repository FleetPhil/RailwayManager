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
        case is Final26:     return try finalRoute(layout: layout)
        default:            return nil
        }
    }
    
    // From D (where train 1 starts) to F forward, then on to C
    private static func finalRoute(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("F"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(toBlock: layout.block("C"), direction: .forward, waitTime: .station)
        let route1 = Route(id: 1, segments: [segment1, segment2])
        
        log.info("Route is \(route1)")
        
        return route1
    }
    

}
