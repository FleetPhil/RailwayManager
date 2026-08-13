//
//  TestTrack2.swift
//
//
//  Created by Phil Diggens on 23/10/2024.
//

import Foundation

// Sendable is safe as no changes are made to the layout topology once init is complete
class TestTrack2: Layout, @unchecked Sendable {
    override init() {
        super.init()
        
        // Define the track layout
        // Simple oval with points for inner half loop and siding
        blocks = [
            Block(id: "A1"),
            Block(id: "A2"),
            Block(id: "B1"),
            Block(id: "B2"),
            Block(id: "C"),
            Block(id: "D")
        ]
        points = [
            Point(id: 50, address: 50, orientation: .left),
            Point(id: 51, address: 51, orientation: .right),
            Point(id: 52, address: 52, orientation: .right)
        ]
        
        point(50).setConnection(from: .single, to: .block(block("A1")))
        point(50).setConnection(from: .splitStraight, to: .block(block("B2")))
        point(50).setConnection(from: .splitBranch, to: .block(block("C")))

        point(51).setConnection(from: .single, to: .block(block("A2")))
        point(51).setConnection(from: .splitStraight, to: .block(block("B1")))
        point(51).setConnection(from: .splitBranch, to: .point(point(52), .splitBranch))

        point(52).setConnection(from: .single, to: .block(block("C")))
        point(52).setConnection(from: .splitStraight, to: .block(block("D")))
        point(52).setConnection(from: .splitBranch, to: .point(point(51), .splitBranch))

        block("A1").setExit(.forward, .block(block("A2")))
        block("A1").setExit(.reverse, .point(PointSetting(point: point(50), direction: .single)))

        block("A2").setExit(.forward, .point(PointSetting(point: point(51), direction: .single)))
        block("A2").setExit(.reverse, .block(block("A1")))

        block("B1").setExit(.forward, .block(block("B2")))
        block("B1").setExit(.reverse, .point(PointSetting(point: point(51), direction: .splitStraight)))
        
        block("B2").setExit(.forward, .point(PointSetting(point: point(50), direction: .splitStraight)))
        block("B2").setExit(.reverse, .block(block("B1")))
        
        block("C").setExit(.forward, .point(PointSetting(point: point(50), direction: .splitBranch)))
        block("C").setExit(.reverse, .point(PointSetting(point: point(52), direction: .single)))

        block("D").setExit(.forward, .point(PointSetting(point: point(52), direction: .splitStraight)))
        block("D").setExit(.reverse, .noExit)

        signals = [
            Signal(id: 1, address: 0, location: block("A2"), indication: .point(point(51), .single), direction: .forward),
            Signal(id: 2, address: 0, location: block("B2"), indication: .point(point(50), .splitStraight), direction: .forward),
            Signal(id: 3, address: 0, location: block("C"), indication: .point(point(50), .splitBranch), direction: .forward),
            Signal(id: 4, address: 0, location: block("D"), indication: .point(point(52), .splitStraight), direction: .forward),
            Signal(id: 5, address: 0, location: block("C"), indication: .point(point(52), .single), direction: .reverse),
            Signal(id: 6, address: 0, location: block("A1"), indication: .block(block("A2")), direction: .forward),
            Signal(id: 7, address: 0, location: block("B1"), indication: .block(block("B2")), direction: .forward),
        ]
            
        // Sensor location start/end relative to the forward direction
        sensors = [
            Sensor(id: 1, location: .start(block("A1"), 10)),
            Sensor(id: 2, location: .end(block("A2"), 10), signals: [.forward : signal(1)]),
            Sensor(id: 3, location: .start(block("B1"), 10)),
            Sensor(id: 4, location: .end(block("B2"), 10), signals: [.forward : signal(2)]),
            Sensor(id: 5, location: .start(block("C"), 10), signals: [.reverse : signal(5)]),
            Sensor(id: 6, location: .end(block("C"), 10), signals: [.forward : signal(3)]),
            Sensor(id: 7, location: .single(block("D"))),
            Sensor(id: 8, location: .end(block("A1"), 10), signals: [.forward : signal(6)]),
            Sensor(id: 9, location: .end(block("B1"), 10), signals: [.forward : signal(7)]),
            Sensor(id: 10, location: .start(block("A2"), 10)),
        ]
        buildLayout()
    }
}

