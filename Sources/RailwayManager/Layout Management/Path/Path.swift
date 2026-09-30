//
//  Path.swift
//  ModelRailway
//
//  Created by Phil Diggens on 06/01/2026.
//

// A path is a sequence of path items to move from a block to another block
// Each path item specifies the point settings (if any) to move from one block to the next one,
// and the travel direction in each of the two blocks (which differ only across a loop closure)

struct Path: Equatable {
    let direction: BlockDirection           // Travel direction in the starting block
    let pathItems: [PathItem]
}

enum PathItemRole {
    case only
    case first
    case last
    case intermediate
    
    var isFirst: Bool {
        switch self {
        case .only, .first:     return true
        default:                return false
        }
    }
    var isLast: Bool {
        switch self {
        case .only, .last:      return true
        default:                return false
        }
    }

}

struct PathItem: Equatable, CustomStringConvertible, Sendable {
    let fromBlock: Block
    let toBlock: Block
    let fromDirection: BlockDirection       // Travel direction in fromBlock
    let toDirection: BlockDirection         // Travel direction on entering toBlock
    let role: PathItemRole
    let pointSettings: [PointSetting]       // Might be more than 1 if back to back points
    
    var description: String {
        let flip = toDirection == fromDirection ? "" : " \(fromDirection) -> \(toDirection)"
        return "\(fromBlock)-\(toBlock)\(flip): \(pointSettings.map({ $0 }))"
    }
    
    static func initialPathItemForBlock(_ block: Block, direction: BlockDirection) -> PathItem {
        return PathItem(fromBlock: block, toBlock: block, fromDirection: direction, toDirection: direction,
                        role: .first, pointSettings: [])
    }
}
