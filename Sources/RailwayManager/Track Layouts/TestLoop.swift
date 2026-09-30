//
//  TestLoop.swift
//  RailwayManager
//
//  Created by Phil Diggens on 30/09/2026.
//

import Foundation

// Test layout with a reversing loop, for running without hardware (-noCBUS).
//
//  S ──── A ──── p1 ─── straight ─── B ─── C
//                  └─── branch ───────────┘
//
// S is a stub (buffer stop at its reverse end). A joins the single leg of point 1.
// B and C form the loop: a train running A → B → C forward returns through the branch
// leg of point 1 into A travelling reverse (the loop closure), then on into S.
// Addresses are dummies: this layout is not wired to hardware.

// Sendable is safe as no changes are made to the layout topology once init is complete
class TestLoop: Layout, @unchecked Sendable {
    override init() {
        super.init()

        // Lengths in cm: the loop (B + C) holds a train up to 120 cm
        blocks = [
            Block(id: "S", length: 80),
            Block(id: "A", length: 80),
            Block(id: "B", length: 60),
            Block(id: "C", length: 60),
        ]
        points = [
            Point(id: 1, address: 1, orientation: .left),
        ]

        point(1).setConnection(from: .single, to: .block(block("A")))
        point(1).setConnection(from: .splitStraight, to: .block(block("B")))
        point(1).setConnection(from: .splitBranch, to: .block(block("C")))

        block("S").setExit(.forward, .block(block("A")))
        block("A").setExit(.forward, .point(PointSetting(point: point(1), direction: .single)))
        block("B").setExit(.forward, .block(block("C")))
        block("C").setExit(.forward, .point(PointSetting(point: point(1), direction: .splitBranch)))

        block("S").setExit(.reverse, .noExit)
        block("A").setExit(.reverse, .block(block("S")))
        block("B").setExit(.reverse, .point(PointSetting(point: point(1), direction: .splitStraight)))
        block("C").setExit(.reverse, .block(block("B")))

        signals = [
            Signal(id: 1, address: 0, location: block("S"), indication: .block(block("A")), direction: .forward),
            Signal(id: 2, address: 0, location: block("A"), indication: .block(block("S")), direction: .reverse),
            Signal(id: 3, address: 0, location: block("A"), indication: .point(point(1), .single), direction: .forward),
            Signal(id: 4, address: 0, location: block("B"), indication: .point(point(1), .splitStraight), direction: .reverse),
            Signal(id: 5, address: 0, location: block("C"), indication: .point(point(1), .splitBranch), direction: .forward),
        ]

        // Sensor location start/end relative to the forward direction
        sensors = [
            Sensor(id: 1, address: 1, location: .start(block("S"), 10)),
            Sensor(id: 2, address: 2, location: .end(block("S"), 10)),

            Sensor(id: 3, address: 3, location: .start(block("A"), 10)),
            Sensor(id: 4, address: 4, location: .end(block("A"), 10)),

            Sensor(id: 5, address: 5, location: .start(block("B"), 10)),
            Sensor(id: 6, address: 6, location: .end(block("B"), 10)),

            Sensor(id: 7, address: 7, location: .start(block("C"), 10)),
            Sensor(id: 8, address: 8, location: .end(block("C"), 10)),
        ]
        buildLayout()
    }
}
