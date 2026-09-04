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
    // Return the Path between a pair of blocks (nil if no route)
    func path(fromBlock: Block, toBlock: Block, direction: Direction) throws -> Path {
        let layoutGraph = direction == .forward ? forwardLayoutGraph : reverseLayoutGraph
        let blocks = layoutGraph.edgesToVertices(edges: layoutGraph.bfs(from: fromBlock.id, to: toBlock.id))
        
        // Check for no route
        if blocks.isEmpty { throw TrainError.invalidPath("No route for \(fromBlock) to \(toBlock) (\(direction)") }
        
        // If not empty the array must contain at least 2 blocks (from & to)

        // Check a route exists in this direction
        if blockRoutes.first(where: {
            $0.fromBlock.id == blocks[0] &&
            $0.toBlock.id == blocks[1] &&
            $0.direction == direction
        }) == nil {
            if blocks.isEmpty { throw TrainError.invalidPath("No route for \(fromBlock) to \(toBlock) (\(direction)") }
        }
        
        var pathItems: [PathItem] = []
        var index: Int = 0
        
        while blocks.count > index + 1 {
            var role: PathItemRole {
                if blocks.count == 2 { return .only }       // Start and end only
                if index == 0 { return .first }
                if index + 2 == blocks.count { return .last }
                return .intermediate
            }
            
            pathItems.append(try pathItemForTransition(fromBlock: block(blocks[index]),
                                                       toBlock: block(blocks[index+1]),
                                                       direction: direction,
                                                       role: role))
            index += 1
        }
        
        log.verbose("Path is \(pathItems)")
        return Path(direction: direction, pathItems: pathItems)
    }
    
    private func pathItemForTransition(fromBlock: Block, toBlock: Block, direction: Direction, role: PathItemRole) throws -> PathItem {
        if let blockRoute = blockRoutes.first(where: {
            $0.fromBlock == fromBlock &&
            $0.toBlock == toBlock &&
            $0.direction == direction
        }) {
            return PathItem(fromBlock: fromBlock,
                            toBlock: toBlock,
                            role: role,
                            pointSettings: blockRoute.pointSettings)
        } else {
            throw TrainError.invalidPath("No block route from \(fromBlock) to \(toBlock), \(direction)")
        }
    }
    
    // The layout graph builder.
    // Vertices are blocks, Edges are direct connections, single points or groups of points
    
    func makeLayoutGraph(_ direction: Direction) -> UnweightedGraph<String> {
        let layoutGraph: UnweightedGraph<String> = UnweightedGraph(vertices: blocks.map({ $0.id }))
  
        blockRoutes.filter({ $0.direction == direction }).forEach({ route in
            layoutGraph.addEdge(from: route.fromBlock.id, to: route.toBlock.id, directed: true)
        })
        return layoutGraph
    }
    
    func makeBlockRoutes() -> [BlockRoute] {
        var routes: [BlockRoute] = []

        for block in blocks {
            for direction in Direction.allCases {
                guard let exit = block.blockExit[direction] else { continue }
                switch exit {
                case .unknown, .noExit:
                    break
                case .block(let toBlock):
                    routes.append(BlockRoute(fromBlock: block, toBlock: toBlock,
                                             direction: direction, pointSettings: []))
                case .point(let pointSetting):
                    let paths = traversePointChain(entering: pointSetting.point,
                                                   from: pointSetting.direction,
                                                   accumulated: [],
                                                   visited: [])
                    for (toBlock, settings) in paths {
                        routes.append(BlockRoute(fromBlock: block, toBlock: toBlock,
                                                 direction: direction, pointSettings: settings))
                    }
                }
            }
        }

        return routes
    }

    // Returns all reachable (block, [PointSetting]) pairs from the given point entry.
    // `from` is the leg of the point we enter from.
    // Facing entry (.single) branches into both split options; trailing entry exits to .single.
    private func traversePointChain(entering point: Point, from entryDirection: PointDirection,
                                    accumulated: [PointSetting], visited: Set<Int>) -> [(Block, [PointSetting])] {
        guard !visited.contains(point.id) else { return [] }
        var visited = visited
        visited.insert(point.id)

        var exits: [(PointDirection, PointConnection)] = []

        if entryDirection == .single {
            // Facing movement — enumerate both branch options
            for branch in [PointDirection.splitStraight, PointDirection.splitBranch] {
                if let connection = point.connections[branch] {
                    exits.append((branch, connection))
                }
            }
        } else {
            // Trailing movement — exit forced to .single
            if let connection = point.connections[.single] {
                exits.append((entryDirection, connection))
            }
        }

        var results: [(Block, [PointSetting])] = []
        for (settingDirection, connection) in exits {
            let settings = accumulated + [PointSetting(point: point, direction: settingDirection)]
            switch connection {
            case .block(let nextBlock):
                results.append((nextBlock, settings))
            case .point(let nextPoint, let nextEntryDirection):
                results += traversePointChain(entering: nextPoint, from: nextEntryDirection,
                                              accumulated: settings, visited: visited)
            }
        }
        return results
    }

    // The direction attributes for a track resource used to identify the next connection
    private enum TrackResourceDirection: CustomStringConvertible {
        case block(Block, Direction?)
        case point(Point, PointDirection)
        
        var description: String {
            switch self {
            case .block(let block, _):
                "Block: \(block)"
            case .point(let point, let pointDirection):
                "Point: \(point), \(pointDirection)"
            }
        }
        
        var block: Block? {
            switch self {
            case .block(let block, _): block
            case .point:               nil
            }
        }
        
        var point: Point? {
            switch self {
            case .point(let point, _): point
            case .block:               nil
            }
        }
        
        var blockDirection: Direction? {
            switch self {
            case .block(_, let direction): direction
            case .point:                nil
            }
        }
        var pointDirection: PointDirection? {
            switch self {
            case .block:                nil
            case .point(_, let direction): direction
            }
        }
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
            for direction in Direction.allCases {
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
        
        return true
    }
}



