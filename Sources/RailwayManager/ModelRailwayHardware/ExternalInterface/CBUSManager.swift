//
//  CBUSManager.swift
//  ModelRailway
//
//  Created by Phil Diggens on 24/01/2026.
//

import Foundation
@preconcurrency import SwiftSerial

enum CBUSError: Error, Equatable, CustomStringConvertible {
    case CBUSUnreachable
    case UnrecognisedOpCode(String)
    case NotCBUSMessage(String)
    case DecodeFailed(String)
    case MissingField(String)
    
    var description: String {
        switch self {
        case .CBUSUnreachable:                  "CBUS Unreachable"
        case .UnrecognisedOpCode(let string):   "Unrecognised CBUS OpCode: \(string)"
        case .NotCBUSMessage(let string):       "Not CBUS message: \(string)"
        case .DecodeFailed(let string):         "CBUS decode failed: \(string)"
        case .MissingField(let string):         "Missing CBUS field: \(string)"
        }
    }
    
    var isFatal: Bool {
        switch self {
        case .CBUSUnreachable:      true
        default:                    false
        }
    }
}



actor CBUSManager: Sendable {
    // Singleton
    static let shared = CBUSManager()
    
    // Serial port can be overridden without rebuilding via an environment variable
    private var serialPort: SerialPort!
    
    private var sessionMap: [ Int : Int] = [:]        // Address : Session
    
    private init() { }
    
    func setup() throws {
        if GlobalOptions.noCBUS == false {
            if let serialPortName = findCBUSSerialPortName() {
                serialPort = SerialPort(path: serialPortName)
                log.info("Found CANUSB4 on \(serialPortName)")
            } else {
                throw TrainError.CBUSError("No CANUSB4 found")
            }
            
            try serialPort.openPort()
            try serialPort.setSettings(
                baudRateSetting: .symmetrical(.baud115200),
                minimumBytesToRead: 1)
        }
        
        try setSignal(211, state: .stop)
        log.debug("Signal 211 to red")

    }
    
    func setPoint(_ id: Int, direction: PointDirection) throws {
        try sendCBUSMessage(CBUSMessage(opCode: direction == .splitStraight ? .ASOF : .ASON, device: id))
    }
    
    func resetPoint(_ id: Int, toDirection: PointDirection) async throws {
        let oppositeDirection: PointDirection = toDirection == .splitBranch ? .splitStraight : .splitBranch
        try setPoint(id, direction: oppositeDirection)
        try await Task.sleep(for: .milliseconds(200))
        try setPoint(id, direction: toDirection)
    }
    
    func setSignal(_ address: Int, state: SignalState) throws {
        if address == 0 { return }          // Dummy device
        try sendCBUSMessage(CBUSMessage(opCode: .ASON1, device: address, dataBytes: [state.rawValue]))
    }
    
    func powerTrain(session: Int, direction: Direction, speed: Int, delay: TimeInterval = 0) throws {
        
        // Set the light if stopped and commanded to move
        if speed != 0 {
            try setFunction(0, session: session, on: true)
        }
        
        // OK, all ready - power the train after an optional interval
        let cbus = CBUSMessage(opCode: .DSPD, session: session, direction: direction, speed: speed)
        
        if delay == 0 {
            try sendCBUSMessage(cbus)
        } else {
            Task {
                try await Task.sleep(for: .seconds(delay))
                try sendCBUSMessage(cbus)
            }
        }
    }
    
    // Track-wide DCC emergency stop (CBUS RSTOP/RESTP)
    func stopAllTrains() throws {
        try sendCBUSMessage(CBUSMessage(opCode: .STOP))
    }
    
    func setFunction(_ function: Int, session: Int, on: Bool) throws {
        let cbus = CBUSMessage(opCode: on ? .DFNON : .DFNOF, session: session, dataBytes: [UInt8(function)] )
        try sendCBUSMessage(cbus)
    }
    
    // MARK: DCC Management
    func resetTrack() throws {
        try sendCBUSMessage(CBUSMessage(opCode: .ARST))
    }
    
    func requestSession(forAddress: Int) throws {
        try sendCBUSMessage(CBUSMessage(opCode: .RLOC, address: forAddress))
    }
    
    func releaseSession(_ session: Int) throws {
        try sendCBUSMessage(CBUSMessage(opCode: .KLOC, session: session))
    }
    
    func sendKeepAlive(session: Int) throws {
        try self.sendCBUSMessage(CBUSMessage(opCode: .DKEEP, session: session))
    }
        
    // MARK: LEDs
    func setLED(_ colour: LEDColour, on: Bool) {
    }
    
    // MARK: Lights
    func setLight(_ id: Int, on: Bool) async {
    }
    
    func setClocks(_ on: Bool) async {
    }
}

// MARK: CBUS interface
extension CBUSManager {
    
    // MARK: Sending messages

    func sendCBUSMessage(_ message: CBUSMessage) throws {
        let cbusHeader = ":S6FC0N"

        let dataToSend: String = {
            var data = cbusHeader + message.opCode.rawValue.hexStr
            switch message.opCode {
            case .ASON, .ASON1, .ASON2, .ASON3, .ASOF, .ASOF1, .ASOF2:
                // Convert the node and device ID into 4 hex bytes
                data += String(format: "%08X", message.device!)
                
                // Add the correct number of data bytes for the OpCode
                if message.opCode.dataByteCount > 1 { data += message.dataBytes[0].hexStr }
                if message.opCode.dataByteCount > 2 { data += message.dataBytes[1].hexStr }
                if message.opCode.dataByteCount > 3 { data += message.dataBytes[2].hexStr }
                return data
                
            case .DKEEP:
                return data + message.session!.hexStr
                
            case .RLOC:
                return data + String(format: "%04X", message.address!)

            case .KLOC:
                return data + message.session!.hexStr

            case .DSPD:
                var speedByte: UInt8 = UInt8 (message.speed!)
                if message.direction! == .reverse {
                    speedByte |= 0x80           // Set b0 if reverse
                }
                return data + message.session!.hexStr + speedByte.hexStr
                
            case .STMOD:
                return data + message.session!.hexStr + message.dataBytes[0].hexStr
                
            case .STOP:     // Emergency stop
                return data
                
            case .DFNON, .DFNOF:
                return data + message.session!.hexStr + message.dataBytes[0].hexStr
                
            case .ARST:
                return data
                
            case .WCVS:
                return data
                + 0x00.hexStr                       // Session
                + (message.cv! / 256).hexStr        // CV High
                + (message.cv! % 256).hexStr        // CV Low
                + 0x00.hexStr                       // Mode - direct byte
                + message.dataBytes[0].hexStr       // Value

            case .QCVS:
                return data
                + 0x00.hexStr                       // Session
                + (message.cv! / 256).hexStr        // CV High
                + (message.cv! % 256).hexStr        // CV Low
                + 0x00.hexStr                       // Mode - direct byte

            case .WCVO:
                return data
                + (message.session!).hexStr         // Session
                + (message.cv! / 256).hexStr        // CV High
                + (message.cv! % 256).hexStr        // CV Low
                + message.dataBytes[0].hexStr       // Value
                
            case .RDCC3:
                return data
                + 1.hexStr                          // Number of times to send packet
                + message.dataBytes[0].hexStr
                + message.dataBytes[1].hexStr
                + message.dataBytes[2].hexStr

            default:
                return ""
            }
        }()
        
        // Add terminator and convert to ascii
        var asciiData = (dataToSend + ";").asciiValues

        if (GlobalOptions.noCBUS == false) {
            do {
                let _ = try serialPort.writeBytes(from: &asciiData, size: asciiData.count)
            } catch {
                throw CBUSError.CBUSUnreachable
            }
        }
    }
    
    // MARK: Receiving Messages
    
    // Return a stream of layout events decoded from CBUS
    func CBUSEvents() throws -> AsyncStream<LayoutEvent> {
        if GlobalOptions.noCBUS {
            return AsyncStream<LayoutEvent> { continuation in
                // Never returns anything
            }
        }
        
        let readStream = try serialPort.asyncBytes()
        return AsyncStream<LayoutEvent> { continuation in
            let task = Task {
                var data: [UInt8] = []
                for await byte in readStream {
                    if byte == 0x3B {           // Semicolon
                        // A bad frame must not end the event stream: log it and continue
                        do {
                            if let cbusMessage = try receivedCBUSMessage(data) {
                                if let event = processReceivedMessage(cbusMessage) {
                                    continuation.yield(event)
                                }
                            }
                        } catch {
                            log.warning("Ignored invalid CBUS frame: \(error)")
                        }
                        data.removeAll()
                    } else {
                        data.append(byte)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Translate received message into array of bytes if valis
    private func receivedCBUSMessage(_ data: [UInt8]) throws -> [UInt8]?  {
        if data.count < 8 { return nil }               // Message too short

        // Build an array of the data values from pairs of ascii characters
        // Starting with the OpCode
        let message = data
            .dropFirst(7)                                   // Ignore header
            .map({ Character(UnicodeScalar($0))})           // Map to ASCII characters
            .unfoldSubSequences(limitedTo: 2)               // Split into pairs
            .map({ String($0.first!) + String($0.last!) })  // Convert to array of 2 char strings
            .compactMap({ UInt8($0, radix: 16) })           // Map to numbers

        // compactMap drops non-hex pairs, so the message may be shorter than the raw data
        guard let opCodeByte = message.first else {
            throw CBUSError.NotCBUSMessage("No opcode in frame")
        }

        if OpCode(rawValue: opCodeByte) == nil {
            throw CBUSError.UnrecognisedOpCode(String(format: "%02X", opCodeByte))
        }
        
        return message
    }
    
    // Process a received CBUS message and return a layout event if it triggers one, nil if not
    private func processReceivedMessage(_ message: [UInt8]) -> LayoutEvent? {
        
        // Validate the message has the fields required for its opcode before indexing:
        // a short frame from a corrupt read must not crash the controller
        func hasBytes(_ count: Int) -> Bool {
            if message.count < count {
                log.warning("Ignored short CBUS message for opcode \(String(format: "%02X", message[0])): \(message.count) bytes")
                return false
            }
            return true
        }
        
        switch OpCode(rawValue: message[0]) {
        case .ASON1:
            guard hasBytes(6) else { return nil }
            let deviceID = Int(message[3]) * 256 + Int(message[4])
            let orientation: SensorEventOrientation = message[5] == 1 ? .north : .south
            
             return .didSetSensor(deviceID, orientation)
            
        case .ASOF1:
            guard hasBytes(6) else { return nil }
            let deviceID = Int(message[3]) * 256 + Int(message[4])
            let orientation: SensorEventOrientation = message[5] == 1 ? .north : .south
            
            return .didUnsetSensor(deviceID, orientation)
            
        case .PLOC:
            guard hasBytes(4) else { return nil }
            // Add to session map
            let session = Int(message[1])
            let address = Int(message[3])
            
            sessionMap[address] = session
            
            return .didGetSession(session: session, address: address)
            
        case .STOPPED:
            // Emergency stop confirmed
            return nil
            
        case .ERR:
            guard hasBytes(4) else { return nil }
            print("*** Received CBUS error \(message[3]) for address \(String(format: "%02X", message[2]))")
            return nil
            
        case .ARST:
            return nil
            
        case .STAT:
            guard hasBytes(4) else { return nil }
            let flags = message[3]
            var statStrings: [String?] = []
            statStrings.append((flags & 0x80 != 0x00) ? "Hardware Error" : nil)
            statStrings.append((flags & 0x40 != 0x00) ? "Track Error" : nil)
            statStrings.append((flags & 0x20 != 0x00) ? "Track On" : "Track Off")
            statStrings.append((flags & 0x10 != 0x00) ? "Bus On" : "Bus halted")
            statStrings.append((flags & 0x08 != 0x00) ? "EM stop all" : nil)
            statStrings.append((flags & 0x04 != 0x00) ? "Reset performed" : nil)
            statStrings.append((flags & 0x02 != 0x00) ? "Service mode on" : "Service mode off")
            let statString = statStrings.compactMap({ $0 }).joined(separator: ", ")
            
            print("*** Received stats: \(statString)")
            return nil
            
        default:
            
            // Message ignored
            return nil
        }
    }

}


// Helper extensions to convert ascii hex string to numbers
extension Collection {
    func unfoldSubSequences(limitedTo maxLength: Int) -> UnfoldSequence<SubSequence,Index> {
        sequence(state: startIndex) { start in
            guard start < self.endIndex else { return nil }
            let end = self.index(start, offsetBy: maxLength, limitedBy: self.endIndex) ?? self.endIndex
            defer { start = end }
            return self[start..<end]
        }
    }
}

extension StringProtocol {
    var byte: UInt8? { UInt8(self, radix: 16) }
    var hexaToBytes: [UInt8] { unfoldSubSequences(limitedTo: 2).compactMap(\.byte) }
    var hexaToData: Data { .init(hexaToBytes) }
}

extension StringProtocol {
    var asciiValues: [UInt8] {
        return compactMap { $0.asciiValue }
    }

    var asciiValue: UInt8 {
        return self.first?.asciiValue ?? Character("?").asciiValue!
    }
}
extension BinaryInteger where Self: CVarArg {
    var hexStr: String { String(format: "%02X", self) }
}



