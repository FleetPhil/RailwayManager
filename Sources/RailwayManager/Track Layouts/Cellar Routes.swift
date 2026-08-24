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

        let path1 = try layout.path(fromBlock: layout.block("D"),
                                    toBlock: layout.block("L"),
                                    direction: .forward)
        let segment1 = Segment(path: path1, waitTime: .halt)
//        let path2 = try layout.path(fromBlock: layout.block("A"),
//                                    toBlock: layout.block("N"),
//                                    direction: .forward)
//        let segment2 = Segment(path: path2, waitTime: .station)
        let route1 = Route(id: 1, segments: [segment1])
        
        return route1
    }
    

}
