//
//  File.swift
//  
//
//  Created by Phil Diggens on 16/10/2024.
//

import Foundation

// Signal state raw values also set in SIGSENS module
public enum SignalState: UInt8, Sendable, CustomStringConvertible, Codable, CaseIterable {
    case off        = 0
    case stop       = 1
    case caution    = 2
    case go         = 3
    case opposed    = 9            // Train direction opposes signal direction
    case right      = 4
    case left       = 5
    
    public nonisolated var description: String {
        switch self {
        case .off:
            "off"
        case .stop:
            "stop"
        case .caution:
            "caution"
        case .go:
            "go"
        case .opposed:
            "opposed"
        case .right:
            "right"
        case .left:
            "left"
        }
    }
}


// Defines what is beyond the signal
enum SignalIndication {
    // Indicates what follows the signal
    // If a block it's the block
    // If a point it's the branch of the point after the signal
    
    case block(Block)                       // On entry to the block
    case point(Point, PointDirection)       // Before the point connection
}

final class Signal: CustomStringConvertible, Sendable {
    internal init(id: Int, address: Int, location: Block, indication: SignalIndication, direction: Direction) {
        self.id = id
        self.location = location
        self.indication = indication
        self.direction = direction
        
        self.hardware = CBUSHardwareSignal(id: id, address: address)
    }

    nonisolated var description: String {
        return "\(id)"
    }
    
    let id: Int                             // As known to hardware controller
    let hardware: HardwareSignal
    let location: Block                     // Actual location of signal
    let direction: Direction
    let indication: SignalIndication        // What the signal status refers to
    
    public func setState(_ state: SignalState) async throws {
        try await hardware.setState(state)
    }
}


extension Signal: Equatable  {
    static func == (lhs: Signal, rhs: Signal) -> Bool {
        return lhs.id == rhs.id
    }
    
}

extension Signal: Hashable  {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
