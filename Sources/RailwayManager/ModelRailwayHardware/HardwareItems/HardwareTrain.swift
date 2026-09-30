//
//  Train.swift
//
//
//  Created by Phil Diggens on 19/10/2024.
//

import Foundation

public typealias TrainID = Int

public protocol HardwareTrain: Sendable {
    func setSpeed(_ speed: Int, direction: BlockDirection, delay: TimeInterval, session: Int) async throws
    func setFunction(_ function: Int, on: Bool, session: Int) async throws
    var address: Int { get }
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
    
    public func setSpeed(_ speed: Int, direction: BlockDirection, delay: TimeInterval, session: Int) async throws {
        try await CBUSManager.shared.powerTrain(session: session, direction: direction, speed: speed, delay: delay)
    }
    
    public func setFunction(_ function: Int, on: Bool, session: Int) async throws {
        try await CBUSManager.shared.setFunction(function, session: session, on: on)
    }
}

