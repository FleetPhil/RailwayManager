//
//  TestLoop2.swift
//  RailwayManager
//
//  Created by Phil Diggens on 01/10/2026.
//

import Foundation

// Window layout with a straight run
//

// Sendable is safe as no changes are made to the layout topology once init is complete
class Window: Layout, @unchecked Sendable {
    override init() {
        super.init()

        // Lengths in cm: the loop (B + C) holds a train up to 120 cm
        blocks = [
            Block(id: "A", length: 80),
            Block(id: "B", length: 60),
        ]
        points = [
        ]

        block("A").setExit(.forward, .block(block("B")))
        block("B").setExit(.forward, .noExit)

        block("A").setExit(.reverse, .noExit)
        block("B").setExit(.reverse, .block(block("A")))

        signals = [
        ]

        // Sensor location start/end relative to the forward direction
        sensors = [
            Sensor(id: 1, address: 1, location: .single(block("A"))),
            Sensor(id: 2, address: 2, location: .single(block("B"))),
        ]
        initialTrainBlocks = [1: block("A")]

        buildLayout()
    }
}
