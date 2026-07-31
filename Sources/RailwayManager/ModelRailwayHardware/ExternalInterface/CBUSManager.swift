//
//  CBUSManager.swift
//  ModelRailway
//
//  Created by Phil Diggens on 24/01/2026.
//

import Foundation
@preconcurrency import SwiftSerial

enum CBUSError: Error, Equatable {
    case CBUSUnreachable
    case UnrecognisedOpCode(String)
    case NotCBUSMessage(String)
    case DecodeFailed(String)
    case MissingField(String)
}



actor CBUSManager: Sendable {
    // Singleton
    static let shared = CBUSManager()
    
    // Serial port can be overridden without rebuilding via an environment variable
    private let serialPortName: String = ProcessInfo.processInfo.environment["CBUS_SERIAL_PORT"] ?? "/dev/cu.usbmodem101"
    private let serialPort: SerialPort
    
    private var sessionMap: [ Int : Int] = [:]        // Address : Session
    
    private init() {
        serialPort = SerialPort(path: serialPortName)
    }
    
    func setup() throws {
        if GlobalOptions.noCBUS == false {
            try serialPort.openPort()
            try serialPort.setSettings(
                baudRateSetting: .symmetrical(.baud115200),
                minimumBytesToRead: 1)
        }
        
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
    
    func setSignal(_ id: Int, state: SignalState) throws {
        if state == .off {
            try sendCBUSMessage(CBUSMessage(opCode: .ASOF, device: id))
        } else {
            try sendCBUSMessage(CBUSMessage(opCode: .ASON1, device: id, dataBytes: [state.rawValue]))
        }
    }
    
    func powerTrain(session: Int, direction: Direction, speed: Int, delay: TimeInterval = 0) throws {
        
        // Turn the light on
        try setFunction(0, session: session, on: true)
        
        // Speed for CBUS is 0-255
        var speedByte: UInt8 = UInt8 (speed * 255 / 100)
        if direction == .reverse {
            speedByte |= 0x80           // Set b0 if reverse
        }
        
        // OK, all ready - power the train after an optional interval
        let cbus = CBUSMessage(opCode: .DSPD, session: session, dataBytes: [speedByte])
        
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

        var dataToSend: [UInt8] = try {
            
            var data = cbusHeader + String(format: "%02X", message.opCode.rawValue)
            
            switch message.opCode {
            case .ASON, .ASON1, .ASON2, .ASOF, .ASOF1, .ASOF2:
                guard let device = message.device else {
                    throw CBUSError.MissingField("device for \(message.opCode)")
                }
                guard message.dataBytes.count >= message.opCode.dataByteCount - 1 else {
                    throw CBUSError.MissingField("data bytes for \(message.opCode)")
                }
                
                // Convert the node and device ID into 4 hex bytes
                data += String(format: "%08X", device)
                
                // Add the correct number of data bytes for the OpCode
                if message.opCode.dataByteCount > 1 { data += String(format: "%02x", message.dataBytes[0]) }
                if message.opCode.dataByteCount > 2 { data += String(format: "%02x", message.dataBytes[1]) }
                if message.opCode.dataByteCount > 3 { data += String(format: "%02x", message.dataBytes[2]) }
                return (data + ";").asciiValues
                
            case .DKEEP, .KLOC:
                guard let session = message.session else {
                    throw CBUSError.MissingField("session for \(message.opCode)")
                }
                return (data + String(format: "%02X", session) + ";").asciiValues
                
            case .RLOC:
                guard let address = message.address else {
                    throw CBUSError.MissingField("address for \(message.opCode)")
                }
                return (data + String(format: "%04X", address) + ";").asciiValues

            case .DSPD, .STMOD, .DFNON, .DFNOF:
                guard let session = message.session else {
                    throw CBUSError.MissingField("session for \(message.opCode)")
                }
                guard let dataByte = message.dataBytes.first else {
                    throw CBUSError.MissingField("data byte for \(message.opCode)")
                }
                return (data + String(format: "%02X", session)
                        + String(format: "%02X", dataByte) + ";").asciiValues
                
            case .STOP:     // Emergency stop
                return (data + ";").asciiValues
                
            case .ARST:
                return (data + ";").asciiValues

            default:
                return []
            }
        }()
        
        // Translate to strings for log
//        if message.opCode != .DKEEP {               // Ignore keepalive
//            let debugMessage = dataToSend
//                .map({ Character(UnicodeScalar($0))})           // Map to ASCII characters
//                .dropFirst(7)                                   // Ignore header
//                .unfoldSubSequences(limitedTo: 2)               // Split into pairs
//                .map({ String($0.first!) + String($0.last!) })  // Convert to array of 2 char stringsstring

//            log.debug("Sending CBUS \(debugMessage)")
//        }

        if (GlobalOptions.noCBUS == false) {
            do {
                let _ = try serialPort.writeBytes(from: &dataToSend, size: dataToSend.count)
            } catch {
                throw CBUSError.CBUSUnreachable
            }
        }
    }
    
    // MARK: Receiving Messages
    
    // Return a stream of layout events decoded from CBUS
    func CBUSEvents() throws -> AsyncStream<LayoutEvent> {
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


