//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation
import SwiftGraph

// Base class for layout, will always be subclassed for the layout implementation
class Layout: @unchecked Sendable  {
    // All layout values are set at init and never changed
    // Can't be defined as immutable due to cross-dependencies
    let name: String = "Layout"
    nonisolated(unsafe) var blocks: [Block] = []
    nonisolated(unsafe) var points: [Point] = []
    nonisolated(unsafe) var sensors: [Sensor] = []
    nonisolated(unsafe) var signals: [Signal] = []
    nonisolated(unsafe) var lights: [Light] = []
    
    nonisolated(unsafe) var trains: [Train] = []
    
    struct BlockRoute: CustomStringConvertible {
        var fromBlock: Block
        var toBlock: Block
        var direction: Direction
        var pointSettings: [PointSetting]
        
        var description: String {
            "\(fromBlock)-\(toBlock) \(direction): \(pointSettings.map({ $0 }))"
        }
    }
    // The routes from the layout graph calculated at init
    var blockRoutes: [BlockRoute] = []

    // The layout graphs in each direction
    var forwardLayoutGraph: UnweightedGraph<String> = UnweightedGraph(vertices: [])
    var reverseLayoutGraph: UnweightedGraph<String> = UnweightedGraph(vertices: [])

    init() {  }

    // Must be called at the end of every subclass override init(), after all
    // blocks/points/sensors/signals are assigned. Builds the route and graph
    // caches that are unsafe to initialise lazily on a Sendable class.
    func buildLayout() {
        blockRoutes = makeBlockRoutes()
        forwardLayoutGraph = makeLayoutGraph(.forward)
        reverseLayoutGraph = makeLayoutGraph(.reverse)
    }
    
    // Helper functions
    func hasBlock(_ id: String) -> Bool {
        return blocks.contains(where: { $0.id == id })
    }
    
    func block(_ id: String) -> Block {
        return blocks.first(where: { $0.id == id })!
    }
    func point(_ id: Int) -> Point {
        return points.first(where: { $0.id == id })!
    }
    func sensor(_ address: Int) -> Sensor? {
        return sensors.first(where: { $0.address == address })
    }
    func train(_ id: Int) -> Train? {
        return trains.first(where: { $0.id == id })!
    }
    
    func signal(_ id: Int) -> Signal {
        return signals.first(where: { $0.id == id })!
    }
    
    func light(_ id: Int) -> Light {
        return lights.first(where: { $0.id == id })!
    }
    
    // Return the signal at the end of the block in the specified direction
    func endSignalForBlock(_ block: Block, direction: Direction) -> Signal? {
        return signals.first(where: {
            $0.direction == direction
            && $0.location == block
        })
    }
    
    // Return the sensor at the start or end of this block depending on the direction
    // Start sensor indicates occupancy
    // End sensor is where the train should stop waiting for the next resource
    // Start and end sensors could be the same....
    
    func sensorForBlock(_ block: Block, atBlockStart: Bool, inDirection: Direction) -> Sensor? {
        // Get all the sensors in this block
        let blockSensors = sensors.filter({ $0.block == block })
        
        if blockSensors.isEmpty { return nil }
        if blockSensors.count == 1 { return blockSensors.first! }
        
        // More than 1 sensor - order the sensors start -> end in the forward direction
        let sensorsFirstToLastForward = blockSensors.sorted(by: { $0.location < $1.location })
        switch (atBlockStart, inDirection) {
        case (true, .forward):      return sensorsFirstToLastForward.first      // start sensor forward
        case (true, .reverse):      return sensorsFirstToLastForward.last       // start sensor reverse
        case (false, .forward):     return sensorsFirstToLastForward.last       // end sensor forward
        case (false, .reverse):     return sensorsFirstToLastForward.first      // end sensor reverse
            
        }
    }
    
    // Return the blocks starting with the parameter up to the next point in each direction
    // I.e. the blocks with no intervening points
    
    func contiguousBlocks(fromBlock: Block, direction: Direction) -> [Block] {
        var result: [Block] = [fromBlock]
        
        // Traverse the blocks from here
        while true {
            if let next = result.last!.blockExit[direction]?.contiguousBlock {
                result.append(next)
            } else {
                break
            }
        }
        
        log.verbose("Contiguous from \(fromBlock), \(direction): \(result.map({ $0 }))")
        
        return result
    }
}

