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
                                    toBlock: layout.block("H"),
                                    direction: .forward)
        let segment1 = Segment(path: path11, waitTime: .halt)
        let path12 = try layout.path(fromBlock: layout.block("H"),
                                    toBlock: layout.block("B"),
                                    direction: .reverse)
        let segment2 = Segment(path: path12, waitTime: .station)
        let route1 = Route(id: 1, segments: [segment1, segment2])
        
        return route1
    }
    

}
