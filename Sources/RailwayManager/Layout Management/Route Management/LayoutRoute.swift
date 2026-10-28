//
//  LayoutRoute.swift
//  RailwayManager
//
//  Created by Phil Diggens on 26/07/2026.
//

import Foundation


// Create a route on the layout consisting of a single block -> block path

// MARK: Graph and path functions
extension Layout {
    // Return the Path between a pair of blocks, starting in the given direction in fromBlock.
    // toBlock may be reached in either direction (they differ only if the path crosses a loop closure).
    func path(fromBlock: Block, toBlock: Block, direction: BlockDirection) throws -> Path {
        try path(fromBlock: fromBlock, toBlock: toBlock, direction: direction, isBlocked: { _ in false })
    }

    // As path(fromBlock:toBlock:direction:), not using any block route for which isBlocked returns true.
    // Breadth-first search over (block, travel direction) vertices, with the block routes as edges
    // (direct connections, single points or groups of points; an edge changes direction only across
    // a loop closure). Edges are tried in blockRoutes order, so ties give the same path every time.
    func path(fromBlock: Block, toBlock: Block, direction: BlockDirection,
              isBlocked: (BlockRoute) -> Bool) throws -> Path {
        struct Vertex: Hashable {
            let block: Block
            let direction: BlockDirection
        }

        let start = Vertex(block: fromBlock, direction: direction)
        var visited: Set<Vertex> = []
        var arrivedBy: [Vertex : BlockRoute] = [:]     // The block route used to reach each vertex
        var queue: [Vertex] = [start]
        var goal: Vertex?

        while queue.isEmpty == false {
            let vertex = queue.removeFirst()
            if vertex.block == toBlock {
                goal = vertex
                break
            }
            for blockRoute in blockRoutes where blockRoute.fromBlock == vertex.block
                && blockRoute.direction == vertex.direction && isBlocked(blockRoute) == false {
                let next = Vertex(block: blockRoute.toBlock, direction: blockRoute.toDirection)
                if visited.insert(next).inserted {
                    arrivedBy[next] = blockRoute
                    queue.append(next)
                }
            }
        }

        // No route if toBlock is not reachable, or is fromBlock
        guard let goal, goal.block != fromBlock else {
            throw TrainError.invalidPath("No route for \(fromBlock) to \(toBlock) (\(direction)")
        }

        // Walk back from the goal to the start
        var blockRoutesOnPath: [BlockRoute] = []
        var vertex = goal
        while vertex != start, let blockRoute = arrivedBy[vertex] {
            blockRoutesOnPath.insert(blockRoute, at: 0)
            vertex = Vertex(block: blockRoute.fromBlock, direction: blockRoute.direction)
        }

        let pathItems = blockRoutesOnPath.enumerated().map({ index, blockRoute in
            var role: PathItemRole {
                if blockRoutesOnPath.count == 1 { return .only }       // Start and end only
                if index == 0 { return .first }
                if index + 1 == blockRoutesOnPath.count { return .last }
                return .intermediate
            }
            return PathItem(fromBlock: blockRoute.fromBlock,
                            toBlock: blockRoute.toBlock,
                            fromDirection: blockRoute.direction,
                            toDirection: blockRoute.toDirection,
                            role: role,
                            pointSettings: blockRoute.pointSettings)
        })

//        log.verbose("Path is \(pathItems)")
        return Path(direction: direction, pathItems: pathItems)
    }

    func makeBlockRoutes() -> [BlockRoute] {
        var routes: [BlockRoute] = []

        for block in blocks {
            for direction in BlockDirection.allCases {
                guard let exit = block.blockExit[direction] else { continue }
                switch exit {
                case .unknown, .noExit:
                    break
                case .block(let toBlock):
                    // An unmatched link is reported by layoutIsValid(); keep the direction meanwhile
                    let toDirection = toBlock.entryDirection(through: .block(block)) ?? direction
                    routes.append(BlockRoute(fromBlock: block, toBlock: toBlock, direction: direction,
                                             toDirection: toDirection, pointSettings: []))
                case .point(let pointSetting):
                    let paths = traversePointChain(entering: pointSetting.point,
                                                   from: pointSetting.direction,
                                                   accumulated: [],
                                                   visited: [])
                    for (toBlock, settings, exitLeg) in paths {
                        // An unmatched link is reported by layoutIsValid(); keep the direction meanwhile
                        let toDirection = toBlock.entryDirection(through: .point(exitLeg)) ?? direction
                        routes.append(BlockRoute(fromBlock: block, toBlock: toBlock, direction: direction,
                                                 toDirection: toDirection, pointSettings: settings))
                    }
                }
            }
        }

        return routes
    }

    // Returns all reachable (block, [PointSetting], exit leg) from the given point entry.
    // `from` is the leg of the point we enter from; the exit leg is the point and leg that connects to the block.
    // Facing entry (.single) branches into both split options; trailing entry exits to .single.
    private func traversePointChain(entering point: Point, from entryDirection: PointDirection,
                                    accumulated: [PointSetting], visited: Set<Int>) -> [(Block, [PointSetting], PointSetting)] {
        guard !visited.contains(point.id) else { return [] }
        var visited = visited
        visited.insert(point.id)

        // (point setting, leg we leave by, connection from that leg)
        var exits: [(PointDirection, PointDirection, PointConnection)] = []

        if entryDirection == .single {
            // Facing movement — enumerate both branch options
            for branch in [PointDirection.splitStraight, PointDirection.splitBranch] {
                if let connection = point.connections[branch] {
                    exits.append((branch, branch, connection))
                }
            }
        } else {
            // Trailing movement — exit forced to .single
            if let connection = point.connections[.single] {
                exits.append((entryDirection, .single, connection))
            }
        }

        var results: [(Block, [PointSetting], PointSetting)] = []
        for (settingDirection, exitLeg, connection) in exits {
            let settings = accumulated + [PointSetting(point: point, direction: settingDirection)]
            switch connection {
            case .block(let nextBlock):
                results.append((nextBlock, settings, PointSetting(point: point, direction: exitLeg)))
            case .point(let nextPoint, let nextEntryDirection):
                results += traversePointChain(entering: nextPoint, from: nextEntryDirection,
                                              accumulated: settings, visited: visited)
            }
        }
        return results
    }


    
}

// MARK: Diagnostics
extension Layout {
    // Text listing of every block route and every path between all block pairs in both directions.
    // Output is sorted so that listings taken before and after a topology change can be diffed.
    func topologyDump() -> String {
        var lines: [String] = ["Layout \(type(of: self))", "", "Block routes:"]
        lines += blockRoutes.map({ $0.description }).sorted()

        lines += ["", "Paths:"]
        let sortedBlocks = blocks.sorted(by: { $0.id < $1.id })
        for fromBlock in sortedBlocks {
            for toBlock in sortedBlocks where toBlock != fromBlock {
                for direction in BlockDirection.allCases {
                    let heading = "\(fromBlock)-\(toBlock) \(direction):"
                    if let path = try? path(fromBlock: fromBlock, toBlock: toBlock, direction: direction) {
                        lines.append("\(heading) \(path.direction) \(path.pathItems)")
                    } else {
                        lines.append("\(heading) no route")
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // Write topologyDump() to a timestamped file in the home directory and return its URL
    func writeTopologyDump() throws -> URL {
        let timestamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted))
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("RailwayManager-topology-\(type(of: self))-\(timestamp).txt")
        try topologyDump().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: Validation
extension Layout {
    
    // Check for valid layout
    func layoutIsValid() throws {
        
        // Check block exits
        for block in self.blocks {
            for blockExit in block.blockExit.values {
                switch blockExit {
                case .block(let exitBlock):
                    if blocks.contains(exitBlock) == false {
                        throw TrainError.layoutError("Block \(block.id) exits to unknown block \(exitBlock.id)")
                    }
                    // Block -> block links must be defined on both blocks, so the entry direction can be derived
                    if exitBlock.entryDirection(through: .block(block)) == nil {
                        throw TrainError.layoutError("Block \(block.id) exits to block \(exitBlock.id), which needs exactly one exit back to \(block.id)")
                    }
                case .point(let pointSetting):
                    guard let pointConnection = pointSetting.point.connections[pointSetting.direction] else {
                        throw TrainError.layoutError("Block \(block.id) exit to point \(pointSetting.point) not consistent with point connection")
                    }
                    switch pointConnection {
                    case .block(let connectionBlock):
                        if connectionBlock != block {
                            throw TrainError.layoutError("Block \(block.id) exit to point \(pointSetting.point) but point setting indicates block \(connectionBlock)")
                        }
                    case .point:
                        throw TrainError.layoutError("Block \(block.id) exit to point \(pointSetting.point) but point setting points to another point")
                    }
                    
                case .noExit:
                    break
                    
                case .unknown:
                    throw TrainError.layoutError("Block \(block.id) has undefined exits")
                }
            }
            
            for light in block.associatedLights {
                if lights.contains(light) == false {
                    throw TrainError.layoutError("Block \(block.id) has unknown associated light \(light.id)")
                }
            }
        }
        
        for signal in self.signals {
            if blocks.contains(signal.location) == false {
                throw TrainError.layoutError("Signal \(signal.id) located in unknown block \(signal.location.id)")
            }
            switch signal.indication {
            case .block(let indicatedBlock):
                if blocks.contains(indicatedBlock) == false {
                    throw TrainError.layoutError("Signal \(signal.id) indicates unknown block \(indicatedBlock.id)")
                }
            case .point(let indicatedPoint, _):
                if points.contains(indicatedPoint) == false {
                    throw TrainError.layoutError("Signal \(signal.id) indicates unknown point \(indicatedPoint.id)")
                }
            }
            // The indication must be the location block's exit in the signal's direction,
            // as the direction beyond the signal is derived from it
            let expectedExit: BlockExit = switch signal.indication {
            case .block(let indicatedBlock):                    .block(indicatedBlock)
            case .point(let indicatedPoint, let pointDirection): .point(PointSetting(point: indicatedPoint, direction: pointDirection))
            }
            if signal.location.blockExit[signal.direction] != expectedExit {
                throw TrainError.layoutError("Signal \(signal.id) indication does not match block \(signal.location.id) \(signal.direction) exit")
            }
        }
        
        for sensor in self.sensors {
            switch sensor.location {
            case    .start(let sensorBlock, _),
                    .single(let sensorBlock),
                    .station(let sensorBlock),
                    .end(let sensorBlock, _):
                if blocks.contains(sensorBlock) == false {
                    throw TrainError.layoutError("Sensor \(sensor.id) located in unknown block \(sensorBlock.id)")
                }
            }
            
            for sensorSignal in sensor.signals.values {
                if signals.contains(sensorSignal) == false {
                    throw TrainError.layoutError("Sensor \(sensor.id) located with unknown signal \(sensorSignal.id)")
                }
            }
        }
        
        // Hardware addresses must be unique among the sensors, among the signals and among the points
        // Address 0 is a placeholder for an item with no hardware, so may be repeated
        for (address, duplicates) in Dictionary(grouping: sensors.filter({ $0.address != 0 }), by: \.address).sorted(by: { $0.key < $1.key }) where duplicates.count > 1 {
            throw TrainError.layoutError("Sensors \(duplicates.map(\.id)) share hardware address \(address)")
        }
        for (address, duplicates) in Dictionary(grouping: signals.filter({ $0.address != 0 }), by: \.address).sorted(by: { $0.key < $1.key }) where duplicates.count > 1 {
            throw TrainError.layoutError("Signals \(duplicates.map(\.id)) share hardware address \(address)")
        }
        for (address, duplicates) in Dictionary(grouping: points.filter({ $0.address != 0 }), by: \.address).sorted(by: { $0.key < $1.key }) where duplicates.count > 1 {
            throw TrainError.layoutError("Points \(duplicates.map(\.id)) share hardware address \(address)")
        }
        
        // Look for duplicated point settings from block exits
        var allPointSettings: [PointSetting] = []
        for block in self.blocks {
            for direction in BlockDirection.allCases {
                if let blockExit = block.blockExit[direction] {
                    switch blockExit {
                    case .point(let pointSetting):
                        allPointSettings.append(pointSetting)
                    default:
                        break
                    }
                }
            }
        }
        if allPointSettings.isUnique == false {
            let mappedItems = allPointSettings.map { ($0, 1) }
            let duplicated = Dictionary(mappedItems, uniquingKeysWith: +).filter({ $0.value > 1 })
            if duplicated.isEmpty == false {
                for duplicate in duplicated {
                    throw TrainError.layoutError("Duplicate block exit: \(duplicate.key)")
                }
            }
        }

        for point in self.points {
            for pointSetting in PointDirection.allCases {
                if let pointConnection = point.connections[pointSetting] {
                    switch pointConnection {
                    case .block(let connectionBlock):
                        if blocks.contains(connectionBlock) == false {
                            throw TrainError.layoutError("Point \(point.id) connection \(pointSetting) exits to unknown block \(connectionBlock.id)")
                        }
                        // The block must list this point leg as one of its exits, so the entry direction can be derived
                        if connectionBlock.entryDirection(through: .point(PointSetting(point: point, direction: pointSetting))) == nil {
                            throw TrainError.layoutError("Point \(point.id) connection \(pointSetting) exits to block \(connectionBlock.id), which has no exit to that point leg")
                        }
                    case .point(let connectionPoint, let connectionPointDirection):
                        let thisPointConnection: PointConnection = .point(point, pointSetting)
                        
                        guard let connectedPointConnection = connectionPoint.connections[connectionPointDirection] else {
                            throw TrainError.layoutError("No connection for \(connectionPoint), \(connectionPointDirection)")
                        }
                        
                        if connectedPointConnection != thisPointConnection {
                            throw TrainError.layoutError("Point \(point.id) \(pointSetting) does not match connected point \(connectionPoint.id): Expected \(thisPointConnection), got \(connectedPointConnection)")
                        }
                    }
                } else {
                    throw TrainError.layoutError("Point \(point.id) connection not defined for \(pointSetting)")
                }
            }
        }
        
        // Check that no block route sets the same point more than once
        for blockRoute in blockRoutes {
            let duplicatedPoints = Dictionary(grouping: blockRoute.pointSettings, by: \.point)
                .filter { $0.value.count > 1 }
            
            if duplicatedPoints.isEmpty == false {
                for point in duplicatedPoints.keys {
                    throw TrainError.layoutError("Block route \(blockRoute.fromBlock)-\(blockRoute.toBlock) (\(blockRoute.direction)) sets point \(point.id) more than once")
                }
            }
        }
        
        // Warn (not an error) for block exits that lead on but have no signal: trains run at normal speed there
        for block in blocks {
            for direction in BlockDirection.allCases {
                switch block.blockExit[direction] {
                case .block?, .point?:
                    if endSignalForBlock(block, direction: direction) == nil {
                        log.warning("Block \(block.id) has no signal at its \(direction) exit")
                    }
                default:
                    break
                }
            }
        }
        
        log.info("Layout \(type(of: self)) is valid")
    }
}



