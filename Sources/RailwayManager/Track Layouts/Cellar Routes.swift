//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 04/08/2026.
//

import Foundation

extension RailwayManager {
    static func setupRoutes(layoutManager: LayoutManager) async throws -> Route  {
        let layout = layoutManager.layout

        let path11 = try layout.path(fromBlock: layout.block("B"),
                                    toBlock: layout.block("G"),
                                    direction: .forward)
        let segment1 = Segment(path: path11, waitTime: .none)
        let path12 = try layout.path(fromBlock: layout.block("G"),
                                    toBlock: layout.block("B"),
                                    direction: .forward)
        let segment2 = Segment(path: path12, waitTime: .none)
        let route1 = Route(id: 1, segments: [segment1])
        
        return route1
    }
    

}
