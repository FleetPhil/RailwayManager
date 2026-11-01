//
//  Routine.swift
//  RailwayManager
//
//  A named sequence of routes run in order by one train, optionally repeated.
//

import Foundation

struct Routine: Sendable {
    let name: String
    let routes: [Route]
    let repeatCount: Int            // Number of times the sequence is run; 0 means until shutdown
    let interval: TimeInterval      // Seconds to wait after a run ends before the next run starts

    init(name: String, routes: [Route], repeatCount: Int = 1, interval: TimeInterval = 0) {
        self.name = name
        self.routes = routes
        self.repeatCount = repeatCount
        self.interval = interval
    }

    // Run the routes in order, back to back, for each repeat
    // A route that fails to start or ends in error aborts the routine
    func run(train: Train, layoutManager: LayoutManager) async throws {
        var run = 0
        while repeatCount == 0 || run < repeatCount {
            run += 1
            log.info("Routine \(name): train \(train.id) starting run \(run)" + (repeatCount == 0 ? "" : " of \(repeatCount)"))

            for route in routes {
                try Task.checkCancellation()
                log.info("Routine \(name): train \(train.id) starting route \(route.id) of run \(run)")
                try await layoutManager.runRouteAndWait(route: route, train: train)
            }

            let moreRuns = repeatCount == 0 || run < repeatCount
            if moreRuns && interval > 0 {
                log.info("Routine \(name): train \(train.id) waiting \(interval)s before next run")
                try await Task.sleep(for: .seconds(interval))
            }
        }
        log.info("Routine \(name): train \(train.id) complete")
    }
}
