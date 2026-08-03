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
            Point(id: 51, orientation: .left),
            Point(id: 52, orientation: .left),
            Point(id: 53, orientation: .left),
            Point(id: 54, orientation: .right),
            Point(id: 55, orientation: .right),
            Point(id: 56, orientation: .left),
            Point(id: 57, orientation: .right),
            Point(id: 58, orientation: .right),
            Point(id: 59, orientation: .right),
        ]
        
        point(51).setConnection(from: .single, to: .point(point(52), .single))
        point(51).setConnection(from: .splitStraight, to: .block(block("B")))
        point(51).setConnection(from: .splitBranch, to: .block(block("C")))

        point(52).setConnection(from: .single, to: .point(point(51), .single))
        point(52).setConnection(from: .splitStraight, to: .block(block("E")))
        point(52).setConnection(from: .splitBranch, to: .point(point(53), .splitBranch))

        point(53).setConnection(from: .single, to: .block(block("D")))
        point(53).setConnection(from: .splitStraight, to: .block(block("A")))
        point(53).setConnection(from: .splitBranch, to: .point(point(52), .splitBranch))

        point(54).setConnection(from: .single, to: .block(block("D")))
        point(54).setConnection(from: .splitStraight, to: .point(point(55), .single))
        point(54).setConnection(from: .splitBranch, to: .block(block("L")))

        point(55).setConnection(from: .single, to: .point(point(54), .splitStraight))
        point(55).setConnection(from: .splitStraight, to: .block(block("H")))
        point(55).setConnection(from: .splitBranch, to: .block(block("J")))

        point(56).setConnection(from: .single, to: .block(block("K")))
        point(56).setConnection(from: .splitStraight, to: .block(block("H")))
        point(56).setConnection(from: .splitBranch, to: .block(block("J")))

        point(57).setConnection(from: .single, to: .block(block("K")))
        point(57).setConnection(from: .splitStraight, to: .block(block("A")))
        point(57).setConnection(from: .splitBranch, to: .point(point(58), .splitBranch))

        point(58).setConnection(from: .single, to: .block(block("B")))
        point(58).setConnection(from: .splitStraight, to: .block(block("G")))
        point(58).setConnection(from: .splitBranch, to: .point(point(57), .splitBranch))

        point(59).setConnection(from: .single, to: .block(block("L")))
        point(59).setConnection(from: .splitStraight, to: .block(block("M")))
        point(59).setConnection(from: .splitBranch, to: .block(block("N")))

        block("A").setExit(.forward, .point(PointSetting(point: point(53), direction: .splitStraight)))
        block("B").setExit(.forward, .point(PointSetting(point: point(51), direction: .splitStraight)))
        block("C").setExit(.forward, .point(PointSetting(point: point(51), direction: .splitBranch)))
        block("D").setExit(.forward, .point(PointSetting(point: point(54), direction: .single)))
        block("E").setExit(.forward, .block(block("G")))
        block("G").setExit(.forward, .point(PointSetting(point: point(58), direction: .splitStraight)))
        block("H").setExit(.forward, .point(PointSetting(point: point(56), direction: .splitStraight)))
        block("J").setExit(.forward, .point(PointSetting(point: point(56), direction: .splitBranch)))
        block("K").setExit(.forward, .point(PointSetting(point: point(57), direction: .single)))
        block("L").setExit(.forward, .point(PointSetting(point: point(59), direction: .single)))
        block("M").setExit(.forward, .noExit)
        block("N").setExit(.forward, .noExit)

        block("A").setExit(.reverse, .point(PointSetting(point: point(57), direction: .splitStraight)))
        block("B").setExit(.reverse, .point(PointSetting(point: point(58), direction: .single)))
        block("C").setExit(.reverse, .noExit)
        block("D").setExit(.reverse, .point(PointSetting(point: point(53), direction: .single)))
        block("E").setExit(.reverse, .point(PointSetting(point: point(52), direction: .splitStraight)))
        block("G").setExit(.reverse, .block(block("E")))
        block("H").setExit(.reverse, .point(PointSetting(point: point(55), direction: .splitStraight)))
        block("J").setExit(.reverse, .point(PointSetting(point: point(55), direction: .splitBranch)))
        block("K").setExit(.reverse, .point(PointSetting(point: point(56), direction: .single)))
        block("L").setExit(.reverse, .point(PointSetting(point: point(54), direction: .splitBranch)))
        block("M").setExit(.reverse, .point(PointSetting(point: point(59), direction: .splitStraight)))
        block("N").setExit(.reverse, .point(PointSetting(point: point(59), direction: .splitBranch)))

        signals = [
        ]
            
        // Sensor location start/end relative to the forward direction
        sensors = [
            
            
            Sensor(id: 1, location: .start(block("A"), 10)),
            Sensor(id: 2, location: .end(block("A"), 10)),

            Sensor(id: 3, location: .start(block("B"), 10)),
            Sensor(id: 4, location: .end(block("B"), 10)),

            Sensor(id: 5, location: .start(block("C"), 10)),
            Sensor(id: 6, location: .end(block("C"), 10)),

            Sensor(id: 7, location: .start(block("D"), 10)),
            Sensor(id: 8, location: .end(block("D"), 10)),

            Sensor(id: 9, location: .start(block("E"), 10)),
            Sensor(id: 10, location: .end(block("E"), 10)),

            Sensor(id: 11, location: .start(block("G"), 10)),
            Sensor(id: 12,location: .end(block("G"), 10)),

            Sensor(id: 13, location: .start(block("H"), 10)),
            Sensor(id: 14, location: .end(block("H"), 10)),

            Sensor(id: 15, location: .start(block("J"), 10)),
            Sensor(id: 16, location: .end(block("J"), 10)),

            Sensor(id: 17, location: .start(block("K"), 10)),
            Sensor(id: 18,location: .end(block("K"), 10)),

            Sensor(id: 19, location: .start(block("L"), 10)),
            Sensor(id: 20, location: .end(block("L"), 10)),

            Sensor(id: 21, location: .start(block("M"), 10)),
            Sensor(id: 22, location: .end(block("M"), 10)),

            Sensor(id: 23, location: .start(block("N"), 10)),
            Sensor(id: 24, location: .end(block("N"), 10)),
        ]
        buildLayout()
    }
}

