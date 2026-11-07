//
//  Xmas26.swift
//
//
//  Created by Phil Diggens on 23/10/2024.
//

import Foundation

// Sendable is safe as no changes are made to the layout topology once init is complete
class Final26v2: Layout, @unchecked Sendable {
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
            Block(id: "Q"),
            Block(id: "R"),
        ]
        points = [
            Point(id: 1, address: 0, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 2, address: 0, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 3, address: 0, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 4, address: 0, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 5, address: 0, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 6, address: 0, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 7, address: 0, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 8, address: 0, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 9, address: 0, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 10, address: 0, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 11, address: 0, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 12, address: 0, orientation: .left, defaultPosition: .splitBranch),

            // Crossover
            Point(id: 21, address: 21, orientation: .right, defaultPosition: .splitStraight),
            Point(id: 22, address: 21, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 23, address: 21, orientation: .left, defaultPosition: .splitStraight),
            Point(id: 24, address: 21, orientation: .right, defaultPosition: .splitStraight),
        ]
        
        // The crossover's four points share one accessory address (set it on all four when known) and switch together
        let crossover = [point(21), point(22), point(23), point(24)]
        for crossoverPoint in crossover { crossoverPoint.setGroup(crossover) }

        point(1).setConnection(from: .single, to: .block(block("B")))
        point(1).setConnection(from: .splitStraight, to: .block(block("A")))
        point(1).setConnection(from: .splitBranch, to: .point(point(3), .splitBranch))

        point(2).setConnection(from: .single, to: .block(block("D")))
        point(2).setConnection(from: .splitStraight, to: .block(block("A")))
        point(2).setConnection(from: .splitBranch, to: .point(point(7), .splitBranch))

        point(3).setConnection(from: .single, to: .block(block("E")))
        point(3).setConnection(from: .splitStraight, to: .point(point(4), .splitStraight))
        point(3).setConnection(from: .splitBranch, to: .point(point(1), .splitBranch))

        point(4).setConnection(from: .single, to: .block(block("F")))
        point(4).setConnection(from: .splitStraight, to: .point(point(3), .splitStraight))
        point(4).setConnection(from: .splitBranch, to: .point(point(8), .splitBranch))

        point(5).setConnection(from: .single, to: .block(block("H")))
        point(5).setConnection(from: .splitStraight, to: .block(block("G")))
        point(5).setConnection(from: .splitBranch, to: .block(block("J")))

        point(6).setConnection(from: .single, to: .block(block("H")))
        point(6).setConnection(from: .splitStraight, to: .point(point(7), .splitStraight))
        point(6).setConnection(from: .splitBranch, to: .point(point(11), .splitBranch))

        point(7).setConnection(from: .single, to: .block(block("E")))
        point(7).setConnection(from: .splitStraight, to: .point(point(6), .splitStraight))
        point(7).setConnection(from: .splitBranch, to: .point(point(2), .splitBranch))

        point(8).setConnection(from: .single, to: .block(block("K")))
        point(8).setConnection(from: .splitStraight, to: .block(block("L")))
        point(8).setConnection(from: .splitBranch, to: .point(point(4), .splitBranch))

        point(9).setConnection(from: .single, to: .block(block("L")))
        point(9).setConnection(from: .splitStraight, to: .block(block("Q")))
        point(9).setConnection(from: .splitBranch, to: .block(block("M")))

        point(10).setConnection(from: .single, to: .block(block("P")))
        point(10).setConnection(from: .splitStraight, to: .block(block("Q")))
        point(10).setConnection(from: .splitBranch, to: .block(block("N")))

        point(11).setConnection(from: .single, to: .block(block("K")))
        point(11).setConnection(from: .splitStraight, to: .block(block("P")))
        point(11).setConnection(from: .splitBranch, to: .point(point(6), .splitBranch))

        point(12).setConnection(from: .single, to: .block(block("M")))
        point(12).setConnection(from: .splitStraight, to: .block(block("R")))
        point(12).setConnection(from: .splitBranch, to: .block(block("N")))

        point(21).setConnection(from: .single, to: .block(block("B")))
        point(21).setConnection(from: .splitStraight, to: .point(point(22), .splitStraight))
        point(21).setConnection(from: .splitBranch, to: .point(point(24), .splitBranch))

        point(22).setConnection(from: .single, to: .block(block("C")))
        point(22).setConnection(from: .splitStraight, to: .point(point(21), .splitStraight))
        point(22).setConnection(from: .splitBranch, to: .point(point(23), .splitBranch))

        point(23).setConnection(from: .single, to: .block(block("F")))
        point(23).setConnection(from: .splitStraight, to: .point(point(24), .splitStraight))
        point(23).setConnection(from: .splitBranch, to: .point(point(22), .splitBranch))

        point(24).setConnection(from: .single, to: .block(block("G")))
        point(24).setConnection(from: .splitStraight, to: .point(point(23), .splitStraight))
        point(24).setConnection(from: .splitBranch, to: .point(point(21), .splitBranch))

        
        block("A").setExit(.forward, .point(PointSetting(point: point(1), direction: .splitStraight)))
        block("B").setExit(.forward, .point(PointSetting(point: point(21), direction: .single)))
        block("C").setExit(.forward, .block(block("D")))
        block("D").setExit(.forward, .point(PointSetting(point: point(2), direction: .single)))
        block("E").setExit(.forward, .point(PointSetting(point: point(3), direction: .single)))
        block("F").setExit(.forward, .point(PointSetting(point: point(23), direction: .single)))
        block("G").setExit(.forward, .point(PointSetting(point: point(5), direction: .splitStraight)))
        block("H").setExit(.forward, .point(PointSetting(point: point(6), direction: .single)))
        block("J").setExit(.forward, .point(PointSetting(point: point(5), direction: .splitBranch)))
        block("K").setExit(.forward, .point(PointSetting(point: point(8), direction: .single)))
        block("L").setExit(.forward, .point(PointSetting(point: point(9), direction: .single)))
        block("M").setExit(.forward, .point(PointSetting(point: point(12), direction: .single)))
        block("N").setExit(.forward, .point(PointSetting(point: point(10), direction: .splitBranch)))
        block("P").setExit(.forward, .point(PointSetting(point: point(11), direction: .splitStraight)))
        block("Q").setExit(.forward, .point(PointSetting(point: point(10), direction: .splitStraight)))
        block("R").setExit(.forward, .noExit)

        block("A").setExit(.reverse, .point(PointSetting(point: point(2), direction: .splitStraight)))
        block("B").setExit(.reverse, .point(PointSetting(point: point(1), direction: .single)))
        block("C").setExit(.reverse, .point(PointSetting(point: point(22), direction: .single)))
        block("D").setExit(.reverse, .block(block("C")))
        block("E").setExit(.reverse, .point(PointSetting(point: point(7), direction: .single)))
        block("F").setExit(.reverse, .point(PointSetting(point: point(4), direction: .single)))
        block("G").setExit(.reverse, .point(PointSetting(point: point(24), direction: .single)))
        block("H").setExit(.reverse, .point(PointSetting(point: point(5), direction: .single)))
        block("J").setExit(.reverse, .noExit)
        block("K").setExit(.reverse, .point(PointSetting(point: point(11), direction: .single)))
        block("L").setExit(.reverse, .point(PointSetting(point: point(8), direction: .splitStraight)))
        block("M").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitBranch)))
        block("N").setExit(.reverse, .point(PointSetting(point: point(12), direction: .splitBranch)))
        block("P").setExit(.reverse, .point(PointSetting(point: point(10), direction: .single)))
        block("Q").setExit(.reverse, .point(PointSetting(point: point(9), direction: .splitStraight)))
        block("R").setExit(.reverse, .point(PointSetting(point: point(12), direction: .splitStraight)))


        signals = [
            Signal(id: 1, address: 0, location: block("A"), indication: .point(point(2), .splitStraight), direction: .reverse),
            Signal(id: 2, address: 0, location: block("A"), indication: .point(point(1), .splitStraight), direction: .forward),
            Signal(id: 3, address: 0, location: block("B"), indication: .point(point(1), .single), direction: .reverse),
            Signal(id: 4, address: 0, location: block("B"), indication: .point(point(21), .single), direction: .forward),
            Signal(id: 5, address: 0, location: block("C"), indication: .point(point(22), .single), direction: .reverse),
            Signal(id: 6, address: 0, location: block("C"), indication: .block(block("D")), direction: .forward),
            Signal(id: 7, address: 0, location: block("D"), indication: .block(block("C")), direction: .reverse),
            Signal(id: 8, address: 0, location: block("D"), indication: .point(point(2), .single), direction: .forward),
            Signal(id: 9, address: 0, location: block("E"), indication: .point(point(7), .single), direction: .reverse),
            Signal(id: 10, address: 0, location: block("E"), indication: .point(point(3), .single), direction: .forward),
            Signal(id: 11, address: 0, location: block("F"), indication: .point(point(4), .single), direction: .reverse),
            Signal(id: 12, address: 0, location: block("F"), indication: .point(point(23), .single), direction: .forward),
            Signal(id: 13, address: 0, location: block("G"), indication: .point(point(24), .single), direction: .reverse),
            Signal(id: 14, address: 0, location: block("G"), indication: .point(point(5), .splitStraight), direction: .forward),
            Signal(id: 15, address: 0, location: block("H"), indication: .point(point(5), .single), direction: .reverse),
            Signal(id: 16, address: 0, location: block("H"), indication: .point(point(6), .single), direction: .forward),
            // No x17
            Signal(id: 18, address: 0, location: block("J"), indication: .point(point(5), .splitBranch), direction: .forward),
            Signal(id: 19, address: 0, location: block("K"), indication: .point(point(11), .single), direction: .reverse),
            Signal(id: 20, address: 0, location: block("K"), indication: .point(point(8), .single), direction: .forward),
            Signal(id: 21, address: 0, location: block("L"), indication: .point(point(8), .splitStraight), direction: .reverse),
            Signal(id: 22, address: 0, location: block("L"), indication: .point(point(9), .single), direction: .forward),
            Signal(id: 23, address: 0, location: block("M"), indication: .point(point(9), .splitBranch), direction: .reverse),
            Signal(id: 24, address: 0, location: block("M"), indication: .point(point(12), .single), direction: .forward),
            Signal(id: 25, address: 0, location: block("N"), indication: .point(point(12), .splitBranch), direction: .reverse),
            Signal(id: 26, address: 0, location: block("N"), indication: .point(point(10), .splitBranch), direction: .forward),
            Signal(id: 27, address: 0, location: block("P"), indication: .point(point(10), .single), direction: .reverse),
            Signal(id: 28, address: 0, location: block("P"), indication: .point(point(11), .splitStraight), direction: .forward),
            Signal(id: 29, address: 0, location: block("Q"), indication: .point(point(9), .splitStraight), direction: .reverse),
            Signal(id: 30, address: 0, location: block("Q"), indication: .point(point(10), .splitStraight), direction: .forward),
            Signal(id: 31, address: 0, location: block("R"), indication: .point(point(12), .splitStraight), direction: .reverse),
            // No x32
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

            Sensor(id: 29, address: 29, location: .start(block("Q"), 10)),
            Sensor(id: 30, address: 30, location: .end(block("Q"), 10)),

            Sensor(id: 31, address: 31, location: .start(block("R"), 10)),
            Sensor(id: 32, address: 32, location: .end(block("R"), 10)),

        ]
        initialTrainBlocks = [1: block("A"), 2: block("G")]
        
        // Parallel platforms: a train may stop in either
        alternativeEndBlocks = [
            block("A"): [block("E")],
            block("E"): [block("K")],
        ]

        buildLayout()
    }
}

