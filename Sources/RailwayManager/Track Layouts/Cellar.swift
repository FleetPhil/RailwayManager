//
//  TestTrack2.swift
//
//
//  Created by Phil Diggens on 23/10/2024.
//

import Foundation

// Sendable is safe as no changes are made to the layout topology once init is complete
class Cellar: Layout, @unchecked Sendable {
    override init() {
        super.init()
        
        // Define the track layout
        // Simple oval with points for inner half loop and siding
        blocks = [
            Block(id: "A"),
            Block(id: "B"),
            Block(id: "C"),
            Block(id: "D"),
            Block(id: "E"),
            Block(id: "G"),
            Block(id: "H"),
            Block(id: "J"),
            Block(id: "K"),
            Block(id: "L"),
            Block(id: "M"),
            Block(id: "N")
        ]
        points = [
            Point(id: 1, address: 55, orientation: .left, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 2, address: 52, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 3, address: 56, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 4, address: 54, orientation: .right, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 5, address: 59, orientation: .right),
            Point(id: 6, address: 58, orientation: .left),
            Point(id: 7, address: 51, orientation: .right, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 8, address: 53, orientation: .right, defaultPosition: .splitStraight, reversedConnection: true),
            Point(id: 9, address: 50, orientation: .right),
        ]
        
        point(1).setConnection(from: .single, to: .point(point(2), .single))
        point(1).setConnection(from: .splitStraight, to: .block(block("B")))
        point(1).setConnection(from: .splitBranch, to: .block(block("C")))

        point(2).setConnection(from: .single, to: .point(point(1), .single))
        point(2).setConnection(from: .splitStraight, to: .block(block("E")))
        point(2).setConnection(from: .splitBranch, to: .point(point(3), .splitBranch))

        point(3).setConnection(from: .single, to: .block(block("D")))
        point(3).setConnection(from: .splitStraight, to: .block(block("A")))
        point(3).setConnection(from: .splitBranch, to: .point(point(2), .splitBranch))

        point(4).setConnection(from: .single, to: .block(block("D")))
        point(4).setConnection(from: .splitStraight, to: .point(point(5), .single))
        point(4).setConnection(from: .splitBranch, to: .block(block("L")))

        point(5).setConnection(from: .single, to: .point(point(4), .splitStraight))
        point(5).setConnection(from: .splitStraight, to: .block(block("H")))
        point(5).setConnection(from: .splitBranch, to: .block(block("J")))

        point(6).setConnection(from: .single, to: .block(block("K")))
        point(6).setConnection(from: .splitStraight, to: .block(block("H")))
        point(6).setConnection(from: .splitBranch, to: .block(block("J")))

        point(7).setConnection(from: .single, to: .block(block("K")))
        point(7).setConnection(from: .splitStraight, to: .block(block("A")))
        point(7).setConnection(from: .splitBranch, to: .point(point(8), .splitBranch))

        point(8).setConnection(from: .single, to: .block(block("B")))
        point(8).setConnection(from: .splitStraight, to: .block(block("G")))
        point(8).setConnection(from: .splitBranch, to: .point(point(7), .splitBranch))

        point(9).setConnection(from: .single, to: .block(block("L")))
        point(9).setConnection(from: .splitStraight, to: .block(block("M")))
        point(9).setConnection(from: .splitBranch, to: .block(block("N")))

        block("A").setExit(.forward, .point(PointSetting(point: point(3), direction: .splitStraight)))
        block("B").setExit(.forward, .point(PointSetting(point: point(1), direction: .splitStraight)))
        block("C").setExit(.forward, .point(PointSetting(point: point(1), direction: .splitBranch)))
        block("D").setExit(.forward, .point(PointSetting(point: point(4), direction: .single)))
        block("E").setExit(.forward, .block(block("G")))
        block("G").setExit(.forward, .point(PointSetting(point: point(8), direction: .splitStraight)))
        block("H").setExit(.forward, .point(PointSetting(point: point(6), direction: .splitStraight)))
        block("J").setExit(.forward, .point(PointSetting(point: point(6), direction: .splitBranch)))
        block("K").setExit(.forward, .point(PointSetting(point: point(7), direction: .single)))
        block("L").setExit(.forward, .point(PointSetting(point: point(9), direction: .single)))
        block("M").setExit(.forward, .noExit)
        block("N").setExit(.forward, .noExit)

        block("A").setExit(.reverse, .point(PointSetting(point: point(7), direction: .splitStraight)))
        block("B").setExit(.reverse, .point(PointSetting(point: point(8), direction: .single)))
        block("C").setExit(.reverse, .noExit)
        block("D").setExit(.reverse, .point(PointSetting(point: point(3), direction: .single)))
        block("E").setExit(.reverse, .point(PointSetting(point: point(2), direction: .splitStraight)))
        block("G").setExit(.reverse, .block(block("E")))
        block("H").setExit(.reverse, .point(PointSetting(point: point(5), direction: .splitStraight)))
        block("J").setExit(.reverse, .point(PointSetting(point: point(5), direction: .splitBranch)))
        block("K").setExit(.reverse, .point(PointSetting(point: point(6), direction: .single)))
        block("L").setExit(.reverse, .point(PointSetting(point: point(4), direction: .splitBranch)))
        block("M").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitStraight)))
        block("N").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitBranch)))

        signals = [
            Signal(id: 1, address: 0, location: block("A"), indication: .point(point(7), .splitStraight), direction: .reverse),
            Signal(id: 2, address: 215, location: block("A"), indication: .point(point(3), .splitStraight), direction: .forward),
//            Signal(id: 3, address: 0, location: block("B"), indication: .point(point(8), .single), direction: .reverse),
            Signal(id: 4, address: 217, location: block("B"), indication: .point(point(1), .splitStraight), direction: .forward),
            Signal(id: 6, address: 211, location: block("C"), indication: .point(point(1), .splitBranch), direction: .forward),
            Signal(id: 7, address: 0, location: block("D"), indication: .point(point(3), .single), direction: .reverse),
            Signal(id: 8, address: 212, location: block("D"), indication: .point(point(4), .single), direction: .forward),
            Signal(id: 9, address: 0, location: block("E"), indication: .point(point(2), .splitStraight), direction: .reverse),
            Signal(id: 10, address: 0, location: block("E"), indication: .block(block("G")), direction: .forward),
            Signal(id: 11, address: 0, location: block("G"), indication: .block(block("E")), direction: .reverse),
            Signal(id: 12, address: 218, location: block("G"), indication: .point(point(8), .splitStraight), direction: .forward),
            Signal(id: 13, address: 0, location: block("H"), indication: .point(point(5), .splitStraight), direction: .reverse),
            Signal(id: 14, address: 213, location: block("H"), indication: .point(point(6), .splitStraight), direction: .forward),
            Signal(id: 15, address: 0, location: block("J"), indication: .point(point(5), .splitBranch), direction: .reverse),
            Signal(id: 16, address: 0, location: block("J"), indication: .point(point(6), .splitBranch), direction: .forward),
            Signal(id: 17, address: 0, location: block("K"), indication: .point(point(6), .single), direction: .reverse),
            Signal(id: 18, address: 214, location: block("K"), indication: .point(point(7), .single), direction: .forward),
            Signal(id: 19, address: 0, location: block("L"), indication: .point(point(4), .splitBranch), direction: .reverse),
            Signal(id: 20, address: 0, location: block("L"), indication: .point(point(9), .single), direction: .forward),
            Signal(id: 21, address: 0, location: block("M"), indication: .point(point(9), .splitStraight), direction: .reverse),
            Signal(id: 23, address: 0, location: block("N"), indication: .point(point(9), .splitBranch), direction: .reverse),
        ]
            
        // Sensor location start/end relative to the forward direction
        sensors = [
            Sensor(id: 1, address: 182, location: .start(block("A"), 10)),
            Sensor(id: 2, address: 142, location: .end(block("A"), 10)),

            Sensor(id: 3, address: 184, location: .start(block("B"), 10)),
            Sensor(id: 4, address: 144, location: .end(block("B"), 10)),

            Sensor(id: 5, address: 183, location: .start(block("C"), 10)),
            Sensor(id: 6, address: 141, location: .end(block("C"), 10)),

            Sensor(id: 7, address: 143, location: .start(block("D"), 10)),
            Sensor(id: 8, address: 162, location: .end(block("D"), 10)),

            Sensor(id: 9, address: 0, location: .start(block("E"), 10)),
            Sensor(id: 10, address: 0, location: .end(block("E"), 10)),

            Sensor(id: 11, address: 0, location: .start(block("G"), 10)),
            Sensor(id: 12, address: 0,location: .end(block("G"), 10)),

            Sensor(id: 13, address: 161, location: .start(block("H"), 10)),
            Sensor(id: 14, address: 202, location: .end(block("H"), 10)),

            Sensor(id: 15, address: 0, location: .start(block("J"), 10)),
            Sensor(id: 16, address: 0, location: .end(block("J"), 10)),

            Sensor(id: 17, address: 201, location: .start(block("K"), 10)),
            Sensor(id: 18, address: 181,location: .end(block("K"), 10)),

            Sensor(id: 19, address: 163, location: .start(block("L"), 10)),
            Sensor(id: 20, address: 164, location: .end(block("L"), 10)),

            Sensor(id: 21, address: 185, location: .start(block("M"), 10)),
            Sensor(id: 22, address: 203, location: .end(block("M"), 10)),

            Sensor(id: 23, address: 0, location: .start(block("N"), 10)),
            Sensor(id: 24, address: 0, location: .end(block("N"), 10)),
            
            Sensor(id: 25, address: 187, location: .station(block("C"))),
            Sensor(id: 26, address: 186, location: .station(block("B"))),

            Sensor(id: 27, address: 0, location: .station(block("H"))),
            Sensor(id: 28, address: 0, location: .station(block("J"))),
        ]
        buildLayout()
    }
}

