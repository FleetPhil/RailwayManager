//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 04/08/2026.
//

import Foundation

extension RailwayManager {
    // The named routines available on the layout, started with -routine <name>:<trainID>
    static func routines(for layout: Layout) -> [String: Routine] {
        switch layout {
        case is Final26:
            guard let route = try? finalRoute(layout: layout) else { return [:] }
            return ["lm": Routine(name: "lm", routes: [route], repeatCount: 2, interval: 30)]
        default:
            return [:]
        }
    }

    // Seconds between the test commands run by -test
    static let testCommandInterval = 10
    
    // Console commands ('sn1', 'ss2', 'st' ...) run in order, testCommandInterval seconds apart, by -test <routine>
    static func testCommands(for routineName: String) -> [String] {
        switch routineName {
        case "lm":  return ["sn19", "sn20", "sn21", "ss24", "ss23", "sn24", "sn21", "sn22", "sn1", "sn2"]
        default:    return []
        }
    }
    
    // From A (where train 1 starts) to L forward, halting once wholly in L, then reverse into M
    private static func finalRoute(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("L"), direction: .forward, waitTime: .halt, stopAt: .entered)
        let segment2 = Segment(toBlock: layout.block("M"), direction: .reverse, waitTime: .halt)
        let segment3 = Segment(toBlock: layout.block("A"), direction: .forward, waitTime: .halt)
        let route1 = Route(id: 1, segments: [segment1, segment2, segment3])
        
        log.info("Route is \(route1)")
        
        return route1
    }
}
