//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation

enum PointConnection: Equatable, CustomStringConvertible {
    case block(Block)
    case point(Point, PointDirection)
    
    var description: String {
        switch self {
        case .block(let block):
            "block \(block)"
        case .point(let point, let pointDirection):
            "point \(point): \(pointDirection)"
        }
    }
}

public enum PointDirection: String, Hashable, CustomStringConvertible, Codable, CaseIterable, Sendable {
    case single             = "Single"
    case splitStraight      = "Straight"
    case splitBranch        = "Branch"
    
    public var description: String {
        switch self {
        case .splitStraight:
            return "Exit Straight"
        case .splitBranch:
            return "Exit Branch"
        case .single:
            return "Single"
        }
    }
}

enum BranchOrientation {
    case right
    case left
    
    // Set the appropriate signal state for this orientation
    var signalState: SignalState {
        switch self {
        case .right:
                .right
        case .left:
                .left
        }
    }
}

struct PointSetting: Equatable, Hashable, CustomStringConvertible {
    var point: Point
    var direction: PointDirection
    
    var description: String {
        return "\(point): \(direction)"
    }
}

// MARK: Point routing
// @unchecked Sendable: connections are wired once during layout init and never mutated after
final class Point: @unchecked Sendable, CustomStringConvertible {
    let id: Int
    let hardware: HardwarePoint

    nonisolated var description: String {
        return "\(id)"
    }

    // MARK: Fixed configuration — set during layout init, immutable at runtime
    let branchOrientation: BranchOrientation
    private(set) var connections: [ PointDirection : PointConnection]
    let defaultPosition: PointDirection?

    init(id: Int,
         connections: [ PointDirection : PointConnection] = [:],
         orientation: BranchOrientation,
         defaultPosition: PointDirection? = nil)  {
        self.id = id
        // TODO: set true hardware config (DCC/CBUS) in init, separate id and DCC/CBUS address
        self.hardware = DCCHardwarePoint(id: id, defaultPosition: defaultPosition, address: id, isReversed: false)
        self.branchOrientation = orientation
        self.connections = connections
        self.defaultPosition = defaultPosition
    }
    
    func setConnection(from connection: PointDirection, to: PointConnection) {
        connections[connection] = to
    }
    
    func setDirection(_ direction: PointDirection) async throws {
        try await hardware.setPoint(id, direction: direction)
    }
}

extension Point: Equatable, Hashable {
    static func == (lhs: Point, rhs: Point) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}





