//
//  TramSplit.swift
//
//
//  Created by Phil Diggens on 23/10/2024.
//

import Foundation

class TramSplit: Layout, @unchecked Sendable {
    override init() {
        super.init()
        
        // Define the track layout
        blocks = [
            Block(id: "A"),
            Block(id: "B"),
            Block(id: "C"),
        ]
        
        points = [
            Point(id: 51, address: 51,
                  connections: [
                    .single : .block(block("A")),
                    .splitStraight : .block(block("B")),
                    .splitBranch : .block(block("C")),
                  ],
                  orientation: .right),
        ]
        
        block("A").setExit(.reverse, .noExit)
        block("A").setExit(.forward, .point(PointSetting(point: point(51), direction: .single)))
        block("B").setExit(.forward, .noExit)
        block("B").setExit(.reverse, .point(PointSetting(point: point(51), direction: .splitStraight)))
        block("C").setExit(.forward, .noExit)
        block("C").setExit(.reverse, .point(PointSetting(point: point(51), direction: .splitBranch)))

        signals = [
            Signal(id: 209, location: block("A"), indication: .point(point(51), .single), direction: .forward),
            Signal(id: 202, location: block("B"), indication: .point(point(51), .splitStraight), direction: .reverse),
            Signal(id: 201, location: block("C"), indication: .point(point(51), .splitBranch), direction: .reverse),
        ]
        
        // NB: Location is relative to the forward direction
        sensors = [
            Sensor(id: 106, location: .end(block("A"), 0), signals: [ .forward : signal(209)]),
            Sensor(id: 105, location: .start(block("A"), 0)),
            Sensor(id: 104, location: .start(block("B"), 0)),
            Sensor(id: 101, location: .end(block("B"), 0)),
            Sensor(id: 103, location: .start(block("C"), 0)),
            Sensor(id: 102, location: .end(block("C"), 0)),
        ]
        buildLayout()
    }
}

