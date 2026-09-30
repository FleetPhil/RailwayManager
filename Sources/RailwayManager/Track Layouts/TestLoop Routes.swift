//
//  TestLoop Routes.swift
//  RailwayManager
//
//  Created by Phil Diggens on 30/09/2026.
//

import Foundation

extension RailwayManager {
    // Turn round through the reversing loop without reversing the train:
    // S to C forward (through point 1's branch, crossing the loop closure so the train
    // enters C travelling reverse), halt, then C to S reverse (via B, point 1 straight and A).
    // The train stays DCC forward throughout and ends in S facing the other way.
    static func testLoopRoute(layout: Layout) throws -> Route {
        let path1 = try layout.path(fromBlock: layout.block("S"),
                                    toBlock: layout.block("C"),
                                    direction: .forward)
        let segment1 = Segment(path: path1, waitTime: .halt)
        let path2 = try layout.path(fromBlock: layout.block("C"),
                                    toBlock: layout.block("S"),
                                    direction: .reverse)
        let segment2 = Segment(path: path2, waitTime: .station)
        return Route(id: 1, segments: [segment1, segment2])
    }
}
