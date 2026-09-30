//
//  LayoutRoute.swift
//  RailwayManager
//
//  Created by Phil Diggens on 26/07/2026.
//

import Foundation
import SwiftGraph


// Create a route on the layout consisting of a single block -> block path

// MARK: Graph and path functions
extension Layout {
    // Return the Path between a pair of blocks, starting in the given direction in fromBlock.
    // toBlock may be reached in either direction (they differ only if the path crosses a loop closure).
    func path(fromBlock: Block, toBlock: Block, direction: BlockDirection) throws -> Path {
        let edges = layoutGraph.bfs(from: graphVertex(fromBlock, direction), goalTest: { graphBlockID($0) == toBlock.id })
        let vertices = layoutGraph.edgesToVertices(edges: edges)
        
        // Check for no route
        if vertices.isEmpty { throw TrainError.invalidPath("No route for \(fromBlock) to \(toBlock) (\(direction)") }
        
        // If not empty the array must contain at least 2 vertices (from & to).
        // Each transition is checked against blockRoutes by pathItemForTransition(), which throws if missing
        
        var pathItems: [PathItem] = []
        var index: Int = 0
        
        while vertices.count > index + 1 {
            var role: PathItemRole {
                if vertices.count == 2 { return .only }       // Start and end only
                if index == 0 { return .first }
                if index + 2 == vertices.count { return .last }
                return .intermediate
            }
            
            pathItems.append(try pathItemForTransition(fromBlock: block(graphBlockID(vertices[index])),
                                                       fromDirection: graphDirection(vertices[index]),
                                                       toBlock: block(graphBlockID(vertices[index+1])),
                                                       toDirection: graphDirection(vertices[index+1]),
                                                       role: role))
            index += 1
        }
        
        log.verbose("Path is \(pathItems)")
        return Path(direction: direction, pathItems: pathItems)
    }
    
    private func pathItemForTransition(fromBlock: Block, fromDirection: BlockDirection,
                                       toBlock: Block, toDirection: BlockDirection,
                                       role: PathItemRole) throws -> PathItem {
        if let blockRoute = blockRoutes.first(where: {
            $0.fromBlock == fromBlock &&
            $0.toBlock == toBlock &&
            $0.direction == fromDirection &&
            $0.toDirection == toDirection
        }) {
            return PathItem(fromBlock: fromBlock,
                            toBlock: toBlock,
                            fromDirection: fromDirection,
                            toDirection: toDirection,
                            role: role,
                            pointSettings: blockRoute.pointSettings)
        } else {
            throw TrainError.invalidPath("No block route from \(fromBlock) to \(toBlock), \(fromDirection) -> \(toDirection)")
        }
    }
    
    // Layout graph vertex for a block and travel direction, e.g. "A+" (forward) or "A-" (reverse)
    func graphVertex(_ block: Block, _ direction: BlockDirection) -> String {
        block.id + (direction == .forward ? "+" : "-")
    }
    
    private func graphBlockID(_ vertex: String) -> String {
        String(vertex.dropLast())
    }
    
    private func graphDirection(_ vertex: String) -> BlockDirection {
        vertex.last == "+" ? .forward : .reverse
    }
    
    // The layout graph builder.
    // Vertices are (block, travel direction) pairs, Edges are block routes: direct connections,
    // single points or groups of points. An edge changes direction only across a loop closure.
    
    func makeLayoutGraph() -> UnweightedGraph<String> {
        let vertices = blocks.flatMap({ block in BlockDirection.allCases.map({ graphVertex(block, $0) }) })
        let layoutGraph: UnweightedGraph<String> = UnweightedGraph(vertices: vertices)
  
        blockRoutes.forEach({ route in
            layoutGraph.addEdge(from: graphVertex(route.fromBlock, route.direction),
                                to: graphVertex(route.toBlock, route.toDirection), directed: true)
        })
        return layoutGraph
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
    func layoutIsValid() -> Bool {
        
        // Check block exits
        for block in self.blocks {
            for blockExit in block.blockExit.values {
                switch blockExit {
                case .block(let exitBlock):
                    if blocks.contains(exitBlock) == false {
                        log.error("Block \(block.id) exits to unknown block \(exitBlock.id)")
                        return false
                    }
                    // Block -> block links must be defined on both blocks, so the entry direction can be derived
                    if exitBlock.entryDirection(through: .block(block)) == nil {
                        log.error("Block \(block.id) exits to block \(exitBlock.id), which needs exactly one exit back to \(block.id)")
                        return false
                    }
                case .point(let pointSetting):
                    guard let pointConnection = pointSetting.point.connections[pointSetting.direction] else {
                        log.error("Block \(block.id) exit to point \(pointSetting.point) not consistent with point connection")
                        return false
                    }
                    switch pointConnection {
                    case .block(let connectionBlock):
                        if connectionBlock != block {
                            log.error("Block \(block.id) exit to point \(pointSetting.point) but point setting indicates block \(connectionBlock)")
                            return false
                        }
                    case .point:
                        log.error("Block \(block.id) exit to point \(pointSetting.point) but point setting points to another point")
                        return false
                    }
                    
                case .noExit:
                    break
                    
                case .unknown:
                    log.error("Block \(block.id) has undefined exits")
                    return false
                }
            }
            
            for light in block.associatedLights {
                if lights.contains(light) == false {
                    log.error("Block \(block.id) has unknown associated light \(light.id)")
                }
            }
        }
        
        for signal in self.signals {
            if blocks.contains(signal.location) == false {
                log.error("Signal \(signal.id) located in unknown block \(signal.location.id)")
                return false
            }
            switch signal.indication {
            case .block(let indicatedBlock):
                if blocks.contains(indicatedBlock) == false {
                    log.error("Signal \(signal.id) indicates unknown block \(indicatedBlock.id)")
                    return false
                }
            case .point(let indicatedPoint, _):
                if points.contains(indicatedPoint) == false {
                    log.error("Signal \(signal.id) indicates unknown point \(indicatedPoint.id)")
                    return false
                }
            }
            // The indication must be the location block's exit in the signal's direction,
            // as the direction beyond the signal is derived from it
            let expectedExit: BlockExit = switch signal.indication {
            case .block(let indicatedBlock):                    .block(indicatedBlock)
            case .point(let indicatedPoint, let pointDirection): .point(PointSetting(point: indicatedPoint, direction: pointDirection))
            }
            if signal.location.blockExit[signal.direction] != expectedExit {
                log.error("Signal \(signal.id) indication does not match block \(signal.location.id) \(signal.direction) exit")
                return false
            }
        }
        
        for sensor in self.sensors {
            switch sensor.location {
            case    .start(let sensorBlock, _),
                    .single(let sensorBlock),
                    .station(let sensorBlock),
                    .end(let sensorBlock, _):
                if blocks.contains(sensorBlock) == false {
                    log.error("Sensor \(sensor.id) located in unknown block \(sensorBlock.id)")
                    return false
                }
            }
            
            for sensorSignal in sensor.signals.values {
                if signals.contains(sensorSignal) == false {
                    log.error("Sensor \(sensor.id) located with unknown signal \(sensorSignal.id)")
                    return false
                }
            }
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
                    log.error("Duplicate block exit: \(duplicate.key)")
                }
                return false
            }
        }

        for point in self.points {
            for pointSetting in PointDirection.allCases {
                if let pointConnection = point.connections[pointSetting] {
                    switch pointConnection {
                    case .block(let connectionBlock):
                        if blocks.contains(connectionBlock) == false {
                            log.error("Point \(point.id) connection \(pointSetting) exits to unknown block \(connectionBlock.id)")
                            return false
                        }
                        // The block must list this point leg as one of its exits, so the entry direction can be derived
                        if connectionBlock.entryDirection(through: .point(PointSetting(point: point, direction: pointSetting))) == nil {
                            log.error("Point \(point.id) connection \(pointSetting) exits to block \(connectionBlock.id), which has no exit to that point leg")
                            return false
                        }
                    case .point(let connectionPoint, let connectionPointDirection):
                        let thisPointConnection: PointConnection = .point(point, pointSetting)
                        
                        guard let connectedPointConnection = connectionPoint.connections[connectionPointDirection] else {
                            log.error("No connection for \(connectionPoint), \(connectionPointDirection)")
                            return false
                        }
                        
                        if connectedPointConnection != thisPointConnection {
                            log.error("Point \(point.id) \(pointSetting) does not match connected point \(connectionPoint.id)")
                            log.error("Expected \(thisPointConnection), got \(connectedPointConnection)")
                            return false
                        }
                    }
                } else {
                    log.error("Point \(point.id) connection not defined for \(pointSetting)")
                    return false
                }
            }
        }
        
        // Check that no block route sets the same point more than once
        for blockRoute in blockRoutes {
            let duplicatedPoints = Dictionary(grouping: blockRoute.pointSettings, by: \.point)
                .filter { $0.value.count > 1 }
            
            if duplicatedPoints.isEmpty == false {
                for point in duplicatedPoints.keys {
                    log.error("Block route \(blockRoute.fromBlock)-\(blockRoute.toBlock) (\(blockRoute.direction)) sets point \(point.id) more than once")
                }
                return false
            }
        }
        
        log.info("Layout \(type(of: self)) is valid")
        return true
    }
}



