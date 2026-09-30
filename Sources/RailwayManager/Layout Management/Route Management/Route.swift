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
        
    var startBlock: Block  {
        get throws {
            if let startBlock = segments.first?.path.pathItems.first?.fromBlock {
                return startBlock
            } else {
                throw TrainError.noStartBlockForRoute(id)
            }
        }
    }
    
    // The direction for the first segment in the route
    var initialDirection: BlockDirection {
        return segments.first?.path.direction ?? .forward
    }

    nonisolated var description: String {
        return "\(self.id)"
    }
    

}

// MARK: Loop check
extension Route {
    // The blocks the front of the train enters, in order, split into stretches at each reversal
    // (a segment that starts in the opposite direction to the one the train arrived in)
    var blockStretches: [[Block]] {
        var stretches: [[Block]] = []
        var arrivalDirection: BlockDirection?
        for segment in segments {
            guard let firstItem = segment.path.pathItems.first else { continue }
            if stretches.isEmpty || firstItem.fromDirection != arrivalDirection {
                stretches.append([firstItem.fromBlock])     // New stretch: route start or reversal
            }
            stretches[stretches.count - 1] += segment.path.pathItems.map(\.toBlock)
            arrivalDirection = segment.path.pathItems.last?.toDirection
        }
        return stretches
    }
    
    // Within a stretch, a block the train enters twice means it has gone round a loop (or a circuit).
    // The blocks in between must hold the whole train, otherwise its front comes back to the block
    // while its rear is still there, and the train stops waiting for itself.
    // Throws if they are too short; warns and skips the check if any length is not known.
    func checkLoopLengths(for train: Train) throws {
        for stretch in blockStretches {
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

