//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation

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
    
    // Where trains start: train id -> block, each train placed (its block occupied) at startup
    nonisolated(unsafe) var initialTrainBlocks: [Int: Block] = [:]
    
    // Blocks a train sent to a block may stop in instead if that block is held by another train:
    // block -> alternatives in order of preference. One way only: [B: [A]] lets A stand in for B, not B for A
    nonisolated(unsafe) var alternativeEndBlocks: [Block: [Block]] = [:]
    
    struct BlockRoute: CustomStringConvertible {
        var fromBlock: Block
        var toBlock: Block
        var direction: BlockDirection           // Travel direction in fromBlock
        var toDirection: BlockDirection         // Travel direction on entering toBlock (differs only across a loop closure)
        var pointSettings: [PointSetting]

        var description: String {
            let flip = toDirection == direction ? "" : " -> \(toDirection)"
            return "\(fromBlock)-\(toBlock) \(direction)\(flip): \(pointSettings.map({ $0 }))"
        }
    }
    // Every block -> block transition, calculated at init; the edges searched by path()
    var blockRoutes: [BlockRoute] = []

    init() {  }

    // Must be called at the end of every subclass override init(), after all
    // blocks/points/sensors/signals are assigned. Builds the block route
    // cache, which is unsafe to initialise lazily on a Sendable class.
    func buildLayout() {
        blockRoutes = makeBlockRoutes()
    }
    
    // Helper functions
    func hasBlock(_ id: String) -> Bool {
        return blocks.contains(where: { $0.id == id })
    }
    
    func block(_ id: String) -> Block {
        if let block = blocks.first(where: { $0.id == id }) {
            return block
        } else {
            print("*** No Block \(id) ***")
            return blocks[blocks.endIndex + 1]      // Invalid - mwill cause crash
        }
    }
    func point(_ id: Int) -> Point {
        return points.first(where: { $0.id == id })!
    }
    func sensor(_ address: Int) -> Sensor? {
        return sensors.first(where: { $0.address == address })
    }
    
    func signal(_ id: Int) -> Signal {
        return signals.first(where: { $0.id == id })!
    }
    
    func light(_ id: Int) -> Light {
        return lights.first(where: { $0.id == id })!
    }
    
    // The blocks a segment to this block can end in: the block itself, then its alternatives
    func endBlocks(for block: Block) -> [Block] {
        [block] + (alternativeEndBlocks[block] ?? [])
    }
    
    // Return the signal at the end of the block in the specified direction
    func endSignalForBlock(_ block: Block, direction: BlockDirection) -> Signal? {
        return signals.first(where: {
            $0.direction == direction
            && $0.location == block
        })
    }
    
    // Return the sensor at the start or end of this block depending on the direction
    // Start sensor indicates occupancy
    // End sensor is where the train should stop waiting for the next resource
    // Start and end sensors could be the same....
    
    func sensorForBlock(_ block: Block, atBlockStart: Bool, inDirection: BlockDirection) -> Sensor? {
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
    
    func stationSensorForBlock(_ block: Block) -> Sensor? {
        return sensors.filter({ $0.block == block }).first(where: { $0.isStation })
    }
    
    // Return the blocks starting with the parameter up to the next point in the given direction,
    // i.e. the blocks with no intervening points, with the travel direction in each.
    // The direction changes if a block -> block link is a loop closure.
    
    func contiguousBlocks(fromBlock: Block, direction: BlockDirection) -> [(block: Block, direction: BlockDirection)] {
        var result: [(block: Block, direction: BlockDirection)] = [(fromBlock, direction)]
        
        // Traverse the blocks from here, stopping if a block repeats (a circle with no points)
        while let current = result.last,
              let next = current.block.blockExit[current.direction]?.contiguousBlock,
              result.contains(where: { $0.block == next }) == false {
            // An unmatched link is reported by layoutIsValid(); keep the direction meanwhile
            let nextDirection = next.entryDirection(through: .block(current.block)) ?? current.direction
            result.append((next, nextDirection))
        }
        
        log.verbose("Contiguous from \(fromBlock), \(direction): \(result.map({ "\($0.block) \($0.direction)" }))")
        
        return result
    }
}

