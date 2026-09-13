//
//  HardwarePoint.swift
//
//
//  Created by Phil Diggens on 16/10/2024.
//

// Immutable hardware attributes and control functions of a point

import Foundation

public typealias PointID = Int

public protocol HardwarePoint: Sendable {
    var defaultPosition: PointDirection? { get }
    
    func setPoint(_ id: PointID, direction: PointDirection) async throws
    func resetPoint(_ id: PointID, toDirection direction: PointDirection) async throws
    func setDefault(_ id: PointID) async throws
}

extension HardwarePoint {
    public func setDefault(_ id: PointID) async throws {
        guard let direction = defaultPosition else { return }
        try await setPoint(id, direction: direction)
    }
}

// MARK: DCC Point
public final class DCCHardwarePoint: HardwarePoint, Sendable, CustomStringConvertible {
    let id: Int         // As known to controller

    nonisolated public var description: String {
        return "\(id)"
    }

    // Address
    let address: Int

    // True if DCC wired reversed
    let isReversed: Bool

    // Default position
    public let defaultPosition: PointDirection?
        
    init(id: Int,
         defaultPosition: PointDirection? = nil,
         address: Int,
         isReversed: Bool = false
        )  {
        self.id = id
        self.defaultPosition = defaultPosition
        self.address = address
        self.isReversed = isReversed
    }
    
    public func setPoint(_ id: PointID, direction: PointDirection) async throws {
        
        let setDirection = isReversed ? direction.oppositeDirection : direction
        
        let command = dccPointCommand(address: address, direction: setDirection)
        try await CBUSManager.shared.sendCBUSMessage(CBUSMessage(opCode: .RDCC3, address: address, dataBytes: command))
        
        try await Task.sleep(for: .milliseconds(200))
    }
    
    public func resetPoint(_ id: PointID, toDirection direction: PointDirection) async throws {
        let oppositeDirection: PointDirection = direction == .splitBranch ? .splitStraight : .splitBranch
        try await setPoint(id, direction: oppositeDirection)
        try await Task.sleep(for: .milliseconds(200))
        try await setPoint(id, direction: direction)
    }
    
    // Convert point address and direction to 3 byte DCC command
    private func dccPointCommand(address: Int, direction: PointDirection) -> [UInt8] {
        
        let address: UInt16 = UInt16(address) & 0x3FF      // 9 bits
        let directionBit: UInt8 = direction == .splitBranch ? 0x00 : 0x01
        
        var result: [UInt8] = [ 0x00, 0x00, 0x00 ]
        
        // Work out accessory address
        // From NMRA RP9.2.1 D - accessory decoder packet format
        // First  byte is 10AAAAAA where AAAAAA is bits 3 to 8 of the accessory address
        result[0] = 0x80 | UInt8((address >> 2) & 0x3F)
        
        // Second byte is 1AAACDDD where DDD are bits 0 to 2 of the accessory address, C is 'activate' or 'deactivate'
        // and AAA are the inverted bits 9 to 11 of the accessory address
        
        // s_ptr->d[1] = 0x88 | (~(acc_address.addr_hi.byte << 4) & 0x70) + ((acc_address.addr_lo << 1) & 0x06);
        result[1] = 0x88 | UInt8(~(address >> 5) & 0x70) | UInt8(((address - 1) << 1) & 0x06) | directionBit
        
        result[2] = result[0] ^ result[1]
        
        return result
    }
}

final class CBUSHardwarePoint: HardwarePoint, Sendable, CustomStringConvertible {
    let id: Int         // As known to controller
    
    nonisolated var description: String {
        return "\(id)"
    }
    
    // Address
    let address: Int
    
    // True if wired reversed
    let isReversed: Bool
    
    // Default position
    let defaultPosition: PointDirection?
    
    init(id: Int,
         defaultPosition: PointDirection? = nil,
         address: Int,
         isReversed: Bool = false
    )  {
        self.id = id
        self.defaultPosition = defaultPosition
        self.address = address
        self.isReversed = isReversed
    }
    
    func setPoint(_ id: Int, direction: PointDirection) async throws {
        var opCode: OpCode {
            if isReversed { return (direction == .splitStraight ? OpCode.ASON : .ASOF) }
            else { return (direction == .splitStraight ? OpCode.ASOF : .ASON) }
        }
        try await CBUSManager.shared.sendCBUSMessage(CBUSMessage(opCode: opCode, device: id))
    }
    
    func resetPoint(_ id: Int, toDirection: PointDirection) async throws {
        let oppositeDirection: PointDirection = toDirection == .splitBranch ? .splitStraight : .splitBranch
        try await setPoint(id, direction: oppositeDirection)
        try await Task.sleep(for: .milliseconds(200))
        try await setPoint(id, direction: toDirection)
    }
}







