//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation


enum BlockExit: Equatable {
    case unknown
    case noExit
    case block(Block)
    case point(PointSetting)        // Bool true will reverse point after exit
    
    var contiguousBlock: Block? {
        switch self {
        case .block(let block):     return block
        default:                    return nil
        }
    }
}

// Sendable is safe as no changes are made once Layout init is complete
final class Block: @unchecked Sendable, CustomStringConvertible {
    let id: String                          // Block ID - single character

    // MARK: Fixed configuration — set during layout init, immutable at runtime
    private(set) var blockExit: [ BlockDirection : BlockExit] = [ .forward : .unknown, .reverse : .unknown ]
    
    // True if the occupied/reserved state is unmonitored for this block (default = false)
    let isUnMonitored: Bool
    
    // Lights associated with this block
    let associatedLights: [Light]
    
    // Length in cm (nil if not known), used to check a train fits in a loop
    let length: Int?
    
    nonisolated var description: String {
        return self.id
    }

    internal init(id: String,
                  length: Int? = nil,
                  associatedLights: [Light] = [],
                  isUnMonitored: Bool = false)
    {
        self.id = id
        self.length = length

        self.isUnMonitored = isUnMonitored
        self.associatedLights = associatedLights
    }
    
    // MARK: Block exit
    func setExit(_ direction: BlockDirection, _ exit: BlockExit) {
        blockExit[direction] = exit
    }
    
    // Travel direction on entering this block through `exit`, the connection as it appears in the block's own exits.
    // Arriving through the block's forward exit means travelling reverse in it, and vice versa.
    // Nil if the block has no matching exit, or both its exits match (ambiguous).
    func entryDirection(through exit: BlockExit) -> BlockDirection? {
        let matching = BlockDirection.allCases.filter({ blockExit[$0] == exit })
        guard matching.count == 1, let exitDirection = matching.first else { return nil }
        return exitDirection.oppositeDirection
    }
}

extension Block: Equatable, Hashable {
    nonisolated static func == (lhs: Block, rhs: Block) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}


