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
    private(set) var blockExit: [ Direction : BlockExit] = [ .forward : .unknown, .reverse : .unknown ]
    
    // True if the occupied/reserved state is unmonitored for this block (default = false)
    let isUnMonitored: Bool
    
    // Lights associated with this block
    let associatedLights: [Light]
    
    nonisolated var description: String {
        return self.id
    }

    internal init(id: String,
                  associatedLights: [Light] = [],
                  isUnMonitored: Bool = false)
    {
        self.id = id

        self.isUnMonitored = isUnMonitored
        self.associatedLights = associatedLights
    }
    
    // MARK: Block exit
    func setExit(_ direction: Direction, _ exit: BlockExit) {
        blockExit[direction] = exit
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


