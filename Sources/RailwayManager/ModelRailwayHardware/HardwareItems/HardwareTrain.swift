//
//  Train.swift
//
//
//  Created by Phil Diggens on 19/10/2024.
//

import Foundation

public typealias TrainID = Int

public protocol HardwareTrain: Sendable {
    func setSpeed(_ speed: Int, direction: Direction, delay: TimeInterval, session: Int) async throws
    var address: Int { get }
}

public enum Direction: String, Codable, Sendable, CaseIterable, CustomStringConvertible {
    case forward
    case reverse
    
    var oppositeDirection: Direction {
        switch self {
        case .forward:      .reverse
        case .reverse:      .forward
        }
    }
    
    public var description: String {
        switch self {
        case .forward:      "forward"
        case .reverse:      "reverse"
        }
    }
}

public struct CBUSHardwareTrain: HardwareTrain, Sendable, CustomStringConvertible {
    let id: Int
    public let address: Int          // DCC address
    
    init(id: TrainID, address: Int) {
        self.id = id
        self.address = address
    }
    
    nonisolated public var description: String {
        return "\(self.id)"
    }
    
    public func setSpeed(_ speed: Int, direction: Direction, delay: TimeInterval, session: Int) async throws {
        try await CBUSManager.shared.powerTrain(session: session, direction: direction, speed: speed, delay: delay)
    }
}

