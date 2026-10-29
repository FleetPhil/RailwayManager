//
//  Xmas26.swift
//
//
//  Created by Phil Diggens on 23/10/2024.
//

import Foundation

// Sendable is safe as no changes are made to the layout topology once init is complete
class Xmas26Flat: Layout, @unchecked Sendable {
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
            Block(id: "N"),
            Block(id: "P"),
        ]
        points = [
            Point(id: 1, address: 50, orientation: .left, reversedConnection: true),
            Point(id: 2, address: 57, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 3, address: 52, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 4, address: 55, orientation: .right, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 5, address: 51, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 6, address: 56, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 7, address: 58, orientation: .left, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 8, address: 53, orientation: .right, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 9, address: 54, orientation: .right),
            Point(id: 10, address: 59, orientation: .right),
            Point(id: 11, address: 60, orientation: .right),
        ]
        
        point(1).setConnection(from: .single, to: .block(block("A")))
        point(1).setConnection(from: .splitStraight, to: .block(block("K")))
        point(1).setConnection(from: .splitBranch, to: .point(point(2), .splitBranch))

        point(2).setConnection(from: .single, to: .block(block("J")))
        point(2).setConnection(from: .splitStraight, to: .block(block("B")))
        point(2).setConnection(from: .splitBranch, to: .point(point(1), .splitBranch))

        point(3).setConnection(from: .single, to: .block(block("E")))
        point(3).setConnection(from: .splitStraight, to: .block(block("D")))
        point(3).setConnection(from: .splitBranch, to: .block(block("C")))

        point(4).setConnection(from: .single, to: .block(block("E")))
        point(4).setConnection(from: .splitStraight, to: .point(point(5), .single))
        point(4).setConnection(from: .splitBranch, to: .block(block("N")))

        point(5).setConnection(from: .single, to: .point(point(4), .splitStraight))
        point(5).setConnection(from: .splitStraight, to: .block(block("F")))
        point(5).setConnection(from: .splitBranch, to: .block(block("G")))

        point(6).setConnection(from: .single, to: .block(block("H")))
        point(6).setConnection(from: .splitStraight, to: .block(block("F")))
        point(6).setConnection(from: .splitBranch, to: .block(block("G")))

        point(7).setConnection(from: .single, to: .block(block("P")))
        point(7).setConnection(from: .splitStraight, to: .block(block("N")))
        point(7).setConnection(from: .splitBranch, to: .block(block("J")))

        point(8).setConnection(from: .single, to: .block(block("H")))
        point(8).setConnection(from: .splitStraight, to: .block(block("D")))
        point(8).setConnection(from: .splitBranch, to: .block(block("C")))

        point(9).setConnection(from: .single, to: .block(block("K")))
        point(9).setConnection(from: .splitStraight, to: .block(block("L")))
        point(9).setConnection(from: .splitBranch, to: .block(block("M")))

        point(10).setConnection(from: .single, to: .block(block("P")))
        point(10).setConnection(from: .splitStraight, to: .block(block("B")))
        point(10).setConnection(from: .splitBranch, to: .point(point(11), .splitBranch))

        point(11).setConnection(from: .single, to: .block(block("A")))
        point(11).setConnection(from: .splitStraight, to: .block(block("L")))
        point(11).setConnection(from: .splitBranch, to: .point(point(10), .splitBranch))

        block("A").setExit(.forward, .point(PointSetting(point: point(1), direction: .single)))
        block("B").setExit(.forward, .point(PointSetting(point: point(2), direction: .splitStraight)))
        block("C").setExit(.forward, .point(PointSetting(point: point(3), direction: .splitBranch)))
        block("D").setExit(.forward, .point(PointSetting(point: point(3), direction: .splitStraight)))
        block("E").setExit(.forward, .point(PointSetting(point: point(4), direction: .single)))
        block("F").setExit(.forward, .point(PointSetting(point: point(6), direction: .splitStraight)))
        block("G").setExit(.forward, .point(PointSetting(point: point(6), direction: .splitBranch)))
        block("H").setExit(.forward, .point(PointSetting(point: point(8), direction: .single)))
        block("J").setExit(.forward, .point(PointSetting(point: point(7), direction: .splitBranch)))
        block("K").setExit(.forward, .point(PointSetting(point: point(9), direction: .single)))
        block("L").setExit(.forward, .point(PointSetting(point: point(11), direction: .splitStraight)))
        block("M").setExit(.forward, .noExit)
        block("N").setExit(.forward, .point(PointSetting(point: point(7), direction: .splitStraight)))
        block("P").setExit(.forward, .point(PointSetting(point: point(10), direction: .single)))

        block("A").setExit(.reverse, .point(PointSetting(point: point(11), direction: .single)))
        block("B").setExit(.reverse, .point(PointSetting(point: point(10), direction: .splitStraight)))
        block("C").setExit(.reverse, .point(PointSetting(point: point(8), direction: .splitBranch)))
        block("D").setExit(.reverse, .point(PointSetting(point: point(8), direction: .splitStraight)))
        block("E").setExit(.reverse, .point(PointSetting(point: point(3), direction: .single)))
        block("F").setExit(.reverse, .point(PointSetting(point: point(5), direction: .splitStraight)))
        block("G").setExit(.reverse, .point(PointSetting(point: point(5), direction: .splitBranch)))
        block("H").setExit(.reverse, .point(PointSetting(point: point(6), direction: .single)))
        block("J").setExit(.reverse, .point(PointSetting(point: point(2), direction: .single)))
        block("K").setExit(.reverse, .point(PointSetting(point: point(1), direction: .splitStraight)))
        block("L").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitStraight)))
        block("M").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitBranch)))
        block("N").setExit(.reverse, .point(PointSetting(point: point(4), direction: .splitBranch)))
        block("P").setExit(.reverse, .point(PointSetting(point: point(7), direction: .single)))

        signals = [
            Signal(id: 1, address: 0, location: block("A"), indication: .point(point(11), .single), direction: .reverse),
            Signal(id: 2, address: 0, location: block("A"), indication: .point(point(1), .single), direction: .forward),
            Signal(id: 3, address: 0, location: block("B"), indication: .point(point(10), .splitStraight), direction: .reverse),
            Signal(id: 4, address: 0, location: block("B"), indication: .point(point(2), .splitStraight), direction: .forward),
            Signal(id: 5, address: 0, location: block("C"), indication: .point(point(8), .splitBranch), direction: .reverse),
            Signal(id: 6, address: 0, location: block("C"), indication: .point(point(3), .splitBranch), direction: .forward),
            Signal(id: 7, address: 0, location: block("D"), indication: .point(point(8), .splitStraight), direction: .reverse),
            Signal(id: 8, address: 0, location: block("D"), indication: .point(point(3), .splitStraight), direction: .forward),
            Signal(id: 9, address: 0, location: block("E"), indication: .point(point(3), .single), direction: .reverse),
            Signal(id: 10, address: 0, location: block("E"), indication: .point(point(4), .single), direction: .forward),
            Signal(id: 11, address: 0, location: block("F"), indication: .point(point(5), .splitStraight), direction: .reverse),
            Signal(id: 12, address: 0, location: block("F"), indication: .point(point(6), .splitStraight), direction: .forward),
            Signal(id: 13, address: 0, location: block("G"), indication: .point(point(5), .splitBranch), direction: .reverse),
            Signal(id: 14, address: 0, location: block("G"), indication: .point(point(6), .splitBranch), direction: .forward),
            Signal(id: 15, address: 0, location: block("H"), indication: .point(point(6), .single), direction: .reverse),
            Signal(id: 16, address: 0, location: block("H"), indication: .point(point(8), .single), direction: .forward),
            Signal(id: 17, address: 0, location: block("J"), indication: .point(point(2), .single), direction: .reverse),
            Signal(id: 18, address: 0, location: block("J"), indication: .point(point(7), .splitBranch), direction: .forward),
            Signal(id: 19, address: 0, location: block("K"), indication: .point(point(1), .splitStraight), direction: .reverse),
            Signal(id: 20, address: 0, location: block("K"), indication: .point(point(9), .single), direction: .forward),
            Signal(id: 21, address: 0, location: block("L"), indication: .point(point(9), .splitStraight), direction: .reverse),
            Signal(id: 22, address: 0, location: block("L"), indication: .point(point(11), .splitStraight), direction: .forward),
            Signal(id: 23, address: 0, location: block("M"), indication: .point(point(9), .splitBranch), direction: .reverse),
            Signal(id: 25, address: 0, location: block("N"), indication: .point(point(4), .splitBranch), direction: .reverse),
            Signal(id: 26, address: 0, location: block("N"), indication: .point(point(7), .splitStraight), direction: .forward),
            Signal(id: 27, address: 0, location: block("P"), indication: .point(point(7), .single), direction: .reverse),
            Signal(id: 28, address: 0, location: block("P"), indication: .point(point(10), .single), direction: .forward),
        ]
            
        // Sensor location start/end relative to the forward direction
        sensors = [
            Sensor(id: 1, address: 1, location: .start(block("A"), 10)),
            Sensor(id: 2, address: 2, location: .end(block("A"), 10)),

            Sensor(id: 3, address: 3, location: .start(block("B"), 10)),
            Sensor(id: 4, address: 4, location: .end(block("B"), 10)),

            Sensor(id: 5, address: 5, location: .start(block("C"), 10)),
            Sensor(id: 6, address: 6, location: .end(block("C"), 10)),

            Sensor(id: 7, address: 7, location: .start(block("D"), 10)),
            Sensor(id: 8, address: 8, location: .end(block("D"), 10)),

            Sensor(id: 9, address: 9, location: .start(block("E"), 10)),
            Sensor(id: 10, address: 10, location: .end(block("E"), 10)),

            Sensor(id: 11, address: 11, location: .start(block("F"), 10)),
            Sensor(id: 12, address: 12,location: .end(block("F"), 10)),

            Sensor(id: 13, address: 13, location: .start(block("G"), 10)),
            Sensor(id: 14, address: 14, location: .end(block("G"), 10)),

            Sensor(id: 15, address: 15, location: .start(block("H"), 10)),
            Sensor(id: 16, address: 16, location: .end(block("H"), 10)),

            Sensor(id: 17, address: 17, location: .start(block("J"), 10)),
            Sensor(id: 18, address: 18,location: .end(block("J"), 10)),

            Sensor(id: 19, address: 19, location: .start(block("K"), 10)),
            Sensor(id: 20, address: 20, location: .end(block("K"), 10)),

            Sensor(id: 21, address: 21, location: .start(block("L"), 10)),
            Sensor(id: 22, address: 22, location: .end(block("L"), 10)),

            Sensor(id: 23, address: 23, location: .start(block("M"), 10)),
            Sensor(id: 24, address: 24, location: .end(block("M"), 10)),
            
            Sensor(id: 25, address: 25, location: .start(block("N"), 10)),
            Sensor(id: 26, address: 26, location: .end(block("N"), 10)),

            Sensor(id: 27, address: 27, location: .start(block("P"), 10)),
            Sensor(id: 28, address: 28, location: .end(block("P"), 10)),

        ]
        initialTrainBlocks = [1: block("D")]

        buildLayout()
    }
}

