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
            guard let route1 = try? finalRoute1(layout: layout) else { return [:] }
            guard let route2 = try? finalRoute2(layout: layout) else { return [:] }
            return [
                "r1": Routine(name: "r1", routes: [route1], repeatCount: 2, interval: 30),
                "r2": Routine(name: "r2", routes: [route2], repeatCount: 2, interval: 30),
            ]
        case is Final26v2:
            guard let route3 = try? finalRoute3(layout: layout) else { return [:] }
            return [
                "r3": Routine(name: "r3", routes: [route3], repeatCount: 1, interval: 30),
            ]

        case is Final26v4:
            guard let route4 = try? finalRoute4(layout: layout) else { return [:] }
            return [
                "r4": Routine(name: "r4", routes: [route4], repeatCount: 1, interval: 30),
            ]

        case is Window:
            guard let windowRoute = try? windowRoute(layout: layout) else { return [:] }
            return [
                "window": Routine(name: "window", routes: [windowRoute], repeatCount: 1, interval: 30),
            ]

            
        default:
            return [:]
        }
    }

    // MARK: Final26 routes
    
    // From A (where train 1 starts) to L forward, halting once wholly in L, then reverse into M, and back to A
    private static func finalRoute1(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("L"), direction: .forward, waitTime: .halt, stopAt: .entered)
        let segment2 = Segment(toBlock: layout.block("M"), direction: .reverse, waitTime: .halt)
        let segment3 = Segment(toBlock: layout.block("A"), direction: .forward, waitTime: .halt)
        let route1 = Route(id: 1, segments: [segment1, segment2, segment3])
        
        log.info("Route is \(route1)")
        
        return route1
    }

    // From G (where train 2 starts) to A reverse, then on to G
    private static func finalRoute2(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("A"), direction: .reverse, waitTime: .none)
        let segment2 = Segment(toBlock: layout.block("G"), direction: .reverse, waitTime: .halt)
        let route2 = Route(id: 2, segments: [segment1, segment2])
        
        log.info("Route is \(route2)")
        
        return route2
    }

    // MARK: Final26v2 routes
    // From A (where train 1 starts) to E forward, halting once wholly in E, then reverse into J
    private static func finalRoute3(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("E"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(toBlock: layout.block("J"), direction: .reverse, waitTime: .halt)
        let segment3 = Segment(toBlock: layout.block("A"), direction: .forward, waitTime: .halt)
        let route3 = Route(id: 3, segments: [segment1, segment2, segment3])
        
        log.info("Route is \(route3)")
        
        return route3
    }
    
    // MARK: Final26v4 routes
    // From J (where train 1 starts) to A forward, halting once wholly in A, then reverse into J
    private static func finalRoute4(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("A"), direction: .forward, waitTime: .halt)
        let segment2 = Segment(toBlock: layout.block("J"), direction: .reverse, waitTime: .halt)
        let route4 = Route(id: 4, segments: [segment1, segment2])
        
        log.info("Route is \(route4)")
        
        return route4
    }
    
    // MARK: Window routes
    
    // From A (where train 1 starts) to B, then back to A
    private static func windowRoute(layout: Layout) throws -> Route {
        let segment1 = Segment(toBlock: layout.block("B"), direction: .forward, waitTime: .station)
        let segment2 = Segment(toBlock: layout.block("A"), direction: .reverse, waitTime: .station)
        let windowRoute = Route(id: 1, segments: [segment1, segment2])
        
        log.info("Route is \(windowRoute)")
        return windowRoute
    }


}
