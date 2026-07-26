//
//  LayoutRoute.swift
//  RailwayManager
//
//  Created by Phil Diggens on 26/07/2026.
//

import Foundation
import SwiftGraph

extension Layout {
    func route(id: Int, fromBlock: Block, toSensor: Sensor, direction: Direction) throws -> Route {
        let segments: [Segment] = [
            Segment(name: "Route \(id)", fromBlock: fromBlock, toBlock: toSensor.block, direction: direction, items: [
                .lockPathToBlock(toSensor.block),
                .moveToSensor(toSensor.id, true)
            ])
        ]
        
        // Validate the path
        if try path(fromBlock: fromBlock, toBlock: toSensor.block, direction: direction) == nil {
            // No path for this route
            log.error("No path for this route")
            throw TrainError.invalidRoute(id)
        }
        
        return Route(id: id, segments: segments)
    }
}

// MARK: Graph and path functions
extension Layout {
    // Return the Path between a pair of blocks (nil if no route)
    func path(fromBlock: Block, toBlock: Block, direction: Direction) throws -> Path? {
        let layoutGraph = direction == .forward ? forwardLayoutGraph : reverseLayoutGraph
        let blocks = layoutGraph.edgesToVertices(edges: layoutGraph.bfs(from: fromBlock.id, to: toBlock.id))
        
        // Check for no route
        if blocks.isEmpty { return nil }
        
        // If not empty the array must contain at least 2 blocks (from & to)

        // Check a route exists in this direction
        if blockRoutes.first(where: {
            $0.fromBlock.id == blocks[0] &&
            $0.toBlock.id == blocks[1] &&
            $0.direction == direction
        }) == nil {
            return nil
        }
        
        var pathItems: [PathItem] = []
        var index: Int = 0
        
        while blocks.count > index + 1 {
            let role: PathItemRole = index == 0 ? .first : index + 2 == blocks.count ? .last : .intermediate
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
                            direction: direction,
                            role: role,
                            pointSettings: blockRoute.pointSettings)
        } else {
            throw TrainError.applicationError(7)      // Not found??
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
    
    // return all of the block to block point settings
    func makeBlockRoutes() -> [BlockRoute] {
        var blockRoutes: [BlockRoute] = []
        
        for direction: Direction in [.forward, .reverse] {
            for block in self.blocks {
                var forwardNextBlocks = nextBlocksFromResource(.block(block, direction))
                
                var index = 0
                var pointSettings: [PointSetting] = []
                
                while forwardNextBlocks.count > index {     // Could be a hanging point as the first entry
                    switch forwardNextBlocks[index] {
                    case .block(let endBlock, _):
                        // End of path - create route
                        let blockRoute = BlockRoute(fromBlock: block, toBlock: endBlock, direction: direction, pointSettings: pointSettings)
                        blockRoutes.append(blockRoute)
                        
                        // Remove this block end
                        forwardNextBlocks.remove(at: index)
                        // Remove previous entry if it exists (must be a point if so)
                        if index > 0 {
                            forwardNextBlocks.remove(at: index - 1)
                        }
                        
                        // Loop to start next path
                        index = 0
                        pointSettings.removeAll()
                        
                    case .point(let point, let pointDirection):
                        // Add the point setting to the list for the route
                        pointSettings.append(PointSetting(point: point, direction: pointDirection))
                        index += 1
                    }
                }
            }
        }
        
        return blockRoutes
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

    // Return the resources after this one from the given direction until a block is reached
    private func nextBlocksFromResource(_ resourceDirection: TrackResourceDirection, resources: [TrackResourceDirection] = []) -> [TrackResourceDirection] {
        
        var newResources = resources
        
        if let point = resourceDirection.point {
            if resourceDirection.pointDirection! != .single {
                newResources += [.point(point, resourceDirection.pointDirection!)]
            }
            switch point.connections[resourceDirection.pointDirection!] {
            case .block(let block):         return newResources + [.block(block, nil)]
            case .point(let nextPoint, let pointDirection):
                newResources += [.point(nextPoint, pointDirection)]
                let exits: [PointDirection] = pointDirection == .single ? [.splitStraight, .splitBranch] : [.single]
                for exit in exits {
                    newResources += nextBlocksFromResource(.point(nextPoint, exit))
                }
                return newResources
            default:
                return resources
            }
        }
            
        if let block = resourceDirection.block {
            switch block.blockExit[resourceDirection.blockDirection!] {
            case .block(let nextBlock):     // Exit is another block so just add to the result array
                return newResources + [.block(nextBlock, resourceDirection.blockDirection!)]
            case .point(let pointSetting):  // Iterate through the exits from the next point
                let exits: [PointDirection] = pointSetting.direction == .single ? [.splitStraight, .splitBranch] : [.single]
                for exit in exits {
                    if pointSetting.direction != .single {
                        newResources += [.point(pointSetting.point, pointSetting.direction)]
                    }

                    newResources += nextBlocksFromResource(.point(pointSetting.point, exit))
                }
                return newResources

            default:
                return resources       // No additional blocks
            }
        }
        
        return resources
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
            case .start(let sensorBlock, _), .single(let sensorBlock), .end(let sensorBlock, _):
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
        
        
        return true
    }
}



