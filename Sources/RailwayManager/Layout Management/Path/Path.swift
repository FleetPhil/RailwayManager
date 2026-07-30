//
//  Path.swift
//  ModelRailway
//
//  Created by Phil Diggens on 06/01/2026.
//

// A path is a sequence of path items to move from a block ending at a block in the same direction
// Each path item specifies the point settings (if any) to move from one block to the next one

struct Path: Equatable {
    let direction: Direction
    let pathItems: [PathItem]
}

enum PathItemRole {
    case first
    case last
    case intermediate
    
    var isFirst: Bool {
        if case .first = self { return true } else { return false }
    }
    var isLast: Bool {
        if case .last = self { return true } else { return false }
    }
}

struct PathItem: Equatable, CustomStringConvertible, Sendable {
    let fromBlock: Block
    let toBlock: Block
    let role: PathItemRole
    let pointSettings: [PointSetting]       // Might be more than 1 if back to back points
    
    var description: String {
        "\(fromBlock)-\(toBlock): \(pointSettings.map({ $0 }))"
    }
    
    static func initialPathItemForBlock(_ block: Block) -> PathItem {
        return PathItem(fromBlock: block, toBlock: block, role: .first, pointSettings: [])
    }
}
