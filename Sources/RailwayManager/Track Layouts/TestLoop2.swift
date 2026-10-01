//
//  TestLoop2.swift
//  RailwayManager
//
//  Created by Phil Diggens on 01/10/2026.
//

import Foundation

// Test layout with a reversing loop, for running without hardware (-noCBUS).
//
//  S1 ────  straight ──── p2 ───  A ──── p1 ─── straight ─║── B ─── C
//                                          └─── branch ───║────────┘
//  S2 ────  branch ────
//
// S1/S2 are stubs (buffer stop at reverse end). A joins the single leg of point 1.
// B and C form the loop: a train running A → B → C forward returns through the branch
// leg of point 1 into A travelling reverse (the loop closure), then on into S1/S2.
//
// Track breaks: insulated gaps in both rails on both legs of point 1, on the loop side of the
// point (where the straight leg meets B and the branch leg meets C). B + C form the reversing
// section, fed from the auto-reverser, with no gap between B and C. S, A and point 1 are on the
// normal DCC feed. The section must be longer than the longest train (checkLoopLengths checks
// the train against B + C), and no train should stop straddling a gap.
//
// Addresses are dummies: this layout is not wired to hardware.

// Sendable is safe as no changes are made to the layout topology once init is complete
class TestLoop2: Layout, @unchecked Sendable {
    override init() {
        super.init()

        // Lengths in cm: the loop (B + C) holds a train up to 120 cm
        blocks = [
            Block(id: "S1", length: 80),
            Block(id: "S2", length: 80),
            Block(id: "A", length: 80),
            Block(id: "B", length: 60),
            Block(id: "C", length: 60),
        ]
        points = [
            Point(id: 1, address: 1, orientation: .left),
            Point(id: 2, address: 2, orientation: .left),
        ]

        point(1).setConnection(from: .single, to: .block(block("A")))
        point(1).setConnection(from: .splitStraight, to: .block(block("B")))
        point(1).setConnection(from: .splitBranch, to: .block(block("C")))

        point(2).setConnection(from: .single, to: .block(block("A")))
        point(2).setConnection(from: .splitStraight, to: .block(block("S1")))
        point(2).setConnection(from: .splitBranch, to: .block(block("S2")))

        block("S1").setExit(.forward, .point(PointSetting(point: point(2), direction: .splitStraight)))
        block("S2").setExit(.forward, .point(PointSetting(point: point(2), direction: .splitBranch)))
        block("A").setExit(.forward, .point(PointSetting(point: point(1), direction: .single)))
        block("B").setExit(.forward, .block(block("C")))
        block("C").setExit(.forward, .point(PointSetting(point: point(1), direction: .splitBranch)))

        block("S1").setExit(.reverse, .noExit)
        block("S2").setExit(.reverse, .noExit)
        block("A").setExit(.reverse, .point(PointSetting(point: point(2), direction: .single)))
        block("B").setExit(.reverse, .point(PointSetting(point: point(1), direction: .splitStraight)))
        block("C").setExit(.reverse, .block(block("B")))

        signals = [
            Signal(id: 1, address: 0, location: block("S1"), indication: .point(point(2), .splitStraight), direction: .forward),
            Signal(id: 2, address: 0, location: block("S2"), indication: .point(point(2), .splitBranch), direction: .forward),
            Signal(id: 3, address: 0, location: block("A"), indication: .point(point(2), .single), direction: .reverse),
            Signal(id: 4, address: 0, location: block("A"), indication: .point(point(1), .single), direction: .forward),
            Signal(id: 5, address: 0, location: block("B"), indication: .point(point(1), .splitStraight), direction: .reverse),
            Signal(id: 6, address: 0, location: block("C"), indication: .point(point(1), .splitBranch), direction: .forward),
        ]

        // Sensor location start/end relative to the forward direction
        sensors = [
            Sensor(id: 1, address: 1, location: .start(block("S1"), 10)),
            Sensor(id: 2, address: 2, location: .end(block("S1"), 10)),

            Sensor(id: 3, address: 3, location: .start(block("S2"), 10)),
            Sensor(id: 4, address: 4, location: .end(block("S2"), 10)),

            Sensor(id: 5, address: 5, location: .start(block("A"), 10)),
            Sensor(id: 6, address: 6, location: .end(block("A"), 10)),

            Sensor(id: 7, address: 7, location: .start(block("B"), 10)),
            Sensor(id: 8, address: 8, location: .end(block("B"), 10)),

            Sensor(id: 9, address: 9, location: .start(block("C"), 10)),
            Sensor(id: 10, address: 10, location: .end(block("C"), 10)),
        ]
        buildLayout()
    }
}
