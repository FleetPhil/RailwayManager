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
    func setState(_ state: SignalState) async throws
}

final public class CBUSHardwareSignal: HardwareSignal, CustomStringConvertible, Sendable {
    internal init(id: Int) {
        self.id = id
    }

    nonisolated public var description: String {
        return "\(id)"
    }
    
    let id: Int                             // As known to hardware controller
    
    public func setState(_ state: SignalState) async throws {
        try await CBUSManager.shared.setSignal(id, state: state)
    }
}

