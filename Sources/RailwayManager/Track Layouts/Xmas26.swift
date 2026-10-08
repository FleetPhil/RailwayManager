//
//  Xmas26.swift
//
//
//  Created by Phil Diggens on 23/10/2024.
//

import Foundation

// Sendable is safe as no changes are made to the layout topology once init is complete
class Xmas26: Layout, @unchecked Sendable {
    override init() {
        super.init()
        
        // Define the track layout
        blocks = [
            Block(id: "A"),
            Block(id: "B"),
            Block(id: "C"),
            Block(id: "D"),
            Block(id: "E"),
            Block(id: "F"),
            Block(id: "G"),
            Block(id: "H"),
            Block(id: "J"),
            Block(id: "K"),
            Block(id: "L"),
            Block(id: "M"),
            Block(id: "N")
        ]
        points = [
            Point(id: 1, address: 55, orientation: .right, reversedConnection: true),
            Point(id: 2, address: 52, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 3, address: 56, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 4, address: 54, orientation: .left, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 5, address: 59, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 6, address: 58, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 7, address: 51, orientation: .left, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 8, address: 53, orientation: .right, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 9, address: 57, orientation: .right),
            Point(id: 10, address: 60, orientation: .right),
        ]
        
        point(1).setConnection(from: .single, to: .point(point(2), .splitBranch))
        point(1).setConnection(from: .splitStraight, to: .block(block("D")))
        point(1).setConnection(from: .splitBranch, to: .block(block("C")))

        point(2).setConnection(from: .single, to: .point(point(3), .single))
        point(2).setConnection(from: .splitStraight, to: .block(block("B")))
        point(2).setConnection(from: .splitBranch, to: .point(point(1), .single))

        point(3).setConnection(from: .single, to: .point(point(2), .single))
        point(3).setConnection(from: .splitStraight, to: .block(block("J")))
        point(3).setConnection(from: .splitBranch, to: .point(point(4), .splitBranch))

        point(4).setConnection(from: .single, to: .block(block("E")))
        point(4).setConnection(from: .splitStraight, to: .block(block("A")))
        point(4).setConnection(from: .splitBranch, to: .point(point(3), .splitBranch))

        point(5).setConnection(from: .single, to: .block(block("E")))
        point(5).setConnection(from: .splitStraight, to: .point(point(6), .single))
        point(5).setConnection(from: .splitBranch, to: .block(block("L")))

        point(6).setConnection(from: .single, to: .point(point(5), .splitStraight))
        point(6).setConnection(from: .splitStraight, to: .block(block("F")))
        point(6).setConnection(from: .splitBranch, to: .block(block("G")))

        point(7).setConnection(from: .single, to: .block(block("H")))
        point(7).setConnection(from: .splitStraight, to: .block(block("F")))
        point(7).setConnection(from: .splitBranch, to: .block(block("G")))

        point(8).setConnection(from: .single, to: .block(block("H")))
        point(8).setConnection(from: .splitStraight, to: .block(block("A")))
        point(8).setConnection(from: .splitBranch, to: .block(block("B")))

        point(9).setConnection(from: .single, to: .block(block("K")))
        point(9).setConnection(from: .splitStraight, to: .block(block("C")))
        point(9).setConnection(from: .splitBranch, to: .block(block("D")))

        point(10).setConnection(from: .single, to: .block(block("L")))
        point(10).setConnection(from: .splitStraight, to: .block(block("M")))
        point(10).setConnection(from: .splitBranch, to: .block(block("N")))

        block("A").setExit(.forward, .point(PointSetting(point: point(4), direction: .splitStraight)))
        block("B").setExit(.forward, .point(PointSetting(point: point(2), direction: .splitStraight)))
        block("C").setExit(.forward, .point(PointSetting(point: point(1), direction: .splitBranch)))
        block("D").setExit(.forward, .point(PointSetting(point: point(1), direction: .splitStraight)))
        block("E").setExit(.forward, .point(PointSetting(point: point(5), direction: .single)))
        block("F").setExit(.forward, .point(PointSetting(point: point(7), direction: .splitStraight)))
        block("G").setExit(.forward, .point(PointSetting(point: point(7), direction: .splitBranch)))
        block("H").setExit(.forward, .point(PointSetting(point: point(8), direction: .single)))
        block("J").setExit(.forward, .block(block("K")))
        block("K").setExit(.forward, .point(PointSetting(point: point(9), direction: .single)))
        block("L").setExit(.forward, .point(PointSetting(point: point(10), direction: .single)))
        block("M").setExit(.forward, .noExit)
        block("N").setExit(.forward, .noExit)

        block("A").setExit(.reverse, .point(PointSetting(point: point(8), direction: .splitStraight)))
        block("B").setExit(.reverse, .point(PointSetting(point: point(8), direction: .splitBranch)))
        block("C").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitStraight)))
        block("D").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitBranch)))
        block("E").setExit(.reverse, .point(PointSetting(point: point(4), direction: .single)))
        block("F").setExit(.reverse, .point(PointSetting(point: point(6), direction: .splitStraight)))
        block("G").setExit(.reverse, .point(PointSetting(point: point(6), direction: .splitBranch)))
        block("H").setExit(.reverse, .point(PointSetting(point: point(7), direction: .single)))
        block("J").setExit(.reverse, .point(PointSetting(point: point(3), direction: .splitStraight)))
        block("K").setExit(.reverse, .block(block("J")))
        block("L").setExit(.reverse, .point(PointSetting(point: point(5), direction: .splitBranch)))
        block("M").setExit(.reverse, .point(PointSetting(point: point(10), direction: .splitStraight)))
        block("N").setExit(.reverse, .point(PointSetting(point: point(10), direction: .splitBranch)))

        signals = [
            Signal(id: 1, address: 0, location: block("A"), indication: .point(point(8), .splitStraight), direction: .reverse),
            Signal(id: 2, address: 0, location: block("A"), indication: .point(point(4), .splitStraight), direction: .forward),
            Signal(id: 3, address: 0, location: block("B"), indication: .point(point(8), .splitBranch), direction: .reverse),
            Signal(id: 4, address: 0, location: block("B"), indication: .point(point(2), .splitStraight), direction: .forward),
            Signal(id: 5, address: 0, location: block("C"), indication: .point(point(9), .splitStraight), direction: .reverse),
            Signal(id: 6, address: 0, location: block("C"), indication: .point(point(1), .splitBranch), direction: .forward),
            Signal(id: 7, address: 0, location: block("D"), indication: .point(point(9), .splitBranch), direction: .reverse),
            Signal(id: 8, address: 0, location: block("D"), indication: .point(point(1), .splitStraight), direction: .forward),
            Signal(id: 9, address: 0, location: block("E"), indication: .point(point(4), .single), direction: .reverse),
            Signal(id: 10, address: 0, location: block("E"), indication: .point(point(5), .single), direction: .forward),
            Signal(id: 11, address: 0, location: block("F"), indication: .point(point(6), .splitStraight), direction: .reverse),
            Signal(id: 12, address: 0, location: block("F"), indication: .point(point(7), .splitStraight), direction: .forward),
            Signal(id: 13, address: 0, location: block("G"), indication: .point(point(6), .splitBranch), direction: .reverse),
            Signal(id: 14, address: 0, location: block("G"), indication: .point(point(7), .splitBranch), direction: .forward),
            Signal(id: 15, address: 0, location: block("H"), indication: .point(point(7), .single), direction: .reverse),
            Signal(id: 16, address: 0, location: block("H"), indication: .point(point(8), .single), direction: .forward),
            Signal(id: 17, address: 0, location: block("J"), indication: .point(point(3), .splitStraight), direction: .reverse),
            Signal(id: 18, address: 0, location: block("J"), indication: .block(block("K")), direction: .forward),
            Signal(id: 19, address: 0, location: block("K"), indication: .block(block("J")), direction: .reverse),
            Signal(id: 20, address: 0, location: block("K"), indication: .point(point(9), .single), direction: .forward),
            Signal(id: 21, address: 0, location: block("L"), indication: .point(point(5), .splitBranch), direction: .reverse),
            Signal(id: 22, address: 0, location: block("L"), indication: .point(point(10), .single), direction: .forward),
            Signal(id: 23, address: 0, location: block("M"), indication: .point(point(10), .splitStraight), direction: .reverse),
            Signal(id: 25, address: 0, location: block("N"), indication: .point(point(10), .splitBranch), direction: .reverse),
        ]
            
        // Sensor location start/end relative to the forward direction
        sensors = [
            Sensor(id: 1, address: 0, location: .start(block("A"), 10)),
            Sensor(id: 2, address: 0, location: .end(block("A"), 10)),

            Sensor(id: 3, address: 0, location: .start(block("B"), 10)),
            Sensor(id: 4, address: 0, location: .end(block("B"), 10)),

            Sensor(id: 5, address: 0, location: .start(block("C"), 10)),
            Sensor(id: 6, address: 0, location: .end(block("C"), 10)),

            Sensor(id: 7, address: 0, location: .start(block("D"), 10)),
            Sensor(id: 8, address: 0, location: .end(block("D"), 10)),

            Sensor(id: 9, address: 0, location: .start(block("E"), 10)),
            Sensor(id: 10, address: 0, location: .end(block("E"), 10)),

            Sensor(id: 11, address: 0, location: .start(block("F"), 10)),
            Sensor(id: 12, address: 0,location: .end(block("F"), 10)),

            Sensor(id: 13, address: 0, location: .start(block("G"), 10)),
            Sensor(id: 14, address: 0, location: .end(block("G"), 10)),

            Sensor(id: 15, address: 0, location: .start(block("H"), 10)),
            Sensor(id: 16, address: 0, location: .end(block("H"), 10)),

            Sensor(id: 17, address: 0, location: .start(block("J"), 10)),
            Sensor(id: 18, address: 0,location: .end(block("J"), 10)),

            Sensor(id: 19, address: 0, location: .start(block("K"), 10)),
            Sensor(id: 20, address: 0, location: .end(block("K"), 10)),

            Sensor(id: 21, address: 0, location: .start(block("L"), 10)),
            Sensor(id: 22, address: 0, location: .end(block("L"), 10)),

            Sensor(id: 23, address: 0, location: .start(block("M"), 10)),
            Sensor(id: 24, address: 0, location: .end(block("M"), 10)),
            
            Sensor(id: 25, address: 0, location: .start(block("N"), 10)),
            Sensor(id: 26, address: 0, location: .end(block("N"), 10)),
        ]
        buildLayout()
    }
}

