//
//  HardwareSignal.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation

// Hardware signal

public typealias SignalID = Int

public protocol HardwareSignal: Sendable {
    func setState(home: SignalState, distant: SignalState) async throws
}

final public class CBUSHardwareSignal: HardwareSignal, CustomStringConvertible, Sendable {
    internal init(id: Int, address: Int) {
        self.id = id
        self.address = address
    }

    nonisolated public var description: String {
        return "\(id)"
    }
    
    let id: Int                 // Logical layout ID
    let address: Int            // CBUS address
    
    public func setState(home: SignalState, distant: SignalState) async throws {
        try await CBUSManager.shared.setSignal(address, homeState: home, distantState: distant)
    }
}

