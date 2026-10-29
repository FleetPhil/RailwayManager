//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation

struct Route: CustomStringConvertible, Sendable {
    let id: Int
    let segments: [Segment]
    // The DCC direction the loco sets off in, which fixes which way it faces at the start.
    // Nil keeps the train's current facing (forward if it has not run before).
    let initialDCCDirection: DCCDirection?

    internal init(id: Int, segments: [Segment], initialDCCDirection: DCCDirection? = nil) {
        self.id = id
        self.segments = segments
        self.initialDCCDirection = initialDCCDirection
        
        log.info("Route \(id) created with \(segments.count) segments\(initialDCCDirection.map({ ", starting \($0)" }) ?? "")")
    }
        
    // The direction for the first segment in the route
    var initialDirection: BlockDirection {
        return segments.first?.direction ?? .forward
    }

    nonisolated var description: String {
        return "\(self.id)"
    }
    
    nonisolated var path: String {
        return "\(id): \(segments)"
    }
    

}

// MARK: Loop check
extension Route {
    // The block each segment starts from: startBlock for the first, then where the previous one ended
    func segmentStartBlocks(from startBlock: Block) -> [Block] {
        [startBlock] + segments.dropLast().map(\.toBlock)
    }
    
    // Check the route can be run on the layout from startBlock: there is a path for each segment
    // (ignoring other trains). Throws if not.
    func validate(from startBlock: Block, in layout: Layout) throws {
        guard segments.isEmpty == false else {
            throw TrainError.invalidRoute("Route \(id) invalid: no segments")
        }
        for (fromBlock, segment) in zip(segmentStartBlocks(from: startBlock), segments) {
            _ = try segment.nominalPath(from: fromBlock, in: layout)
        }
    }
    
    // The blocks the front of the train enters on the segments' nominal paths, in order, split into
    // stretches at each reversal (a segment that starts in the opposite direction to the one the train arrived in)
    func blockStretches(from startBlock: Block, in layout: Layout) throws -> [[Block]] {
        var stretches: [[Block]] = []
        var arrivalDirection: BlockDirection?
        for (fromBlock, segment) in zip(segmentStartBlocks(from: startBlock), segments) {
            let pathItems = try segment.nominalPath(from: fromBlock, in: layout).pathItems
            if stretches.isEmpty || segment.direction != arrivalDirection {
                stretches.append([fromBlock])               // New stretch: route start or reversal
            }
            stretches[stretches.count - 1] += pathItems.map(\.toBlock)
            arrivalDirection = pathItems.last?.toDirection
        }
        return stretches
    }
    
    // Within a stretch, a block the train enters twice means it has gone round a loop (or a circuit).
    // The blocks in between must hold the whole train, otherwise its front comes back to the block
    // while its rear is still there, and the train stops waiting for itself.
    // Uses the nominal paths: a different path taken at runtime to avoid other trains is not checked.
    // Throws if they are too short; warns and skips the check if any length is not known.
    func checkLoopLengths(for train: Train, from startBlock: Block, in layout: Layout) throws {
        for stretch in try blockStretches(from: startBlock, in: layout) {
            for (index, block) in stretch.enumerated() {
                guard let previousIndex = stretch[..<index].lastIndex(of: block) else { continue }
                let loopBlocks = stretch[(previousIndex + 1)..<index]
                let lengths = loopBlocks.compactMap(\.length)
                guard lengths.count == loopBlocks.count else {
                    log.warning("Route \(id): can't check train \(train.id) fits the loop \(loopBlocks.map(\.id)) back to \(block): block lengths not known")
                    continue
                }
                let loopLength = lengths.reduce(0, +)
                if loopLength < train.length {
                    throw TrainError.invalidRoute("Route \(id): train \(train.id) (\(train.length) cm) is longer than the loop \(loopBlocks.map(\.id)) back to \(block) (\(loopLength) cm)")
                }
            }
        }
    }
}

extension Route: Equatable, Hashable {
    nonisolated static func == (lhs: Route, rhs: Route) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

