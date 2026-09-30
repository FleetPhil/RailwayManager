//
//  File.swift
//  ModelRailwayHardware
//
//  Created by Phil Diggens on 25/07/2026.
//

import Foundation

struct CBUSMessage {
    var opCode: OpCode
    var device: Int?
    var address: Int?
    var decoder: Int?
    var session: Int?
    var direction: BlockDirection?
    var speed: Int?
    var cv: Int?
    var dataBytes: [UInt8]

    // Init from parameters
    init(opCode: OpCode,
                  device: Int? = nil,
                  address: Int? = nil,
                  decoder: Int? = nil,
                  session: Int? = nil,
                  direction: BlockDirection? = nil,
                  speed: Int? = nil,
                  cv: Int? = nil,
                  dataBytes: [UInt8] = []) {
        self.opCode = opCode
        self.device = device
        self.address = address
        self.decoder = decoder
        self.session = session
        self.direction = direction
        self.speed = speed
        self.cv = cv
        self.dataBytes = dataBytes
    }

    // Description
    var description: String {
        var result: String = ""
        
        if let device { result += "Device: \(device) "}
        if let address { result += "Address: \(address) "}
        if let decoder { result += "Decoder: \(decoder) "}
        if let session { result += "Session: \(session) "}
        if let direction { result += "Direction: \(direction) "}
        if let speed { result += "Speed: \(speed) "}
        if let cv { result += "CV: \(cv) "}
        if dataBytes.isEmpty == false { result += "Data: \(dataBytes.map({ "\($0)"}))"}
        
        return result
    }
    
    // Init from message: [Uint8] starting with OpCode
    static func fromData(_ m: [UInt8]) -> Self? {
        
        // Extract the OpCode if found
        guard let opCode = OpCode(rawValue: m[0]) else {
//            let logItem = LogItem(direction: .receive, message: CBUSMessage(opCode: .UNK))
//            CBUSLog.shared.addItem(logItem)
            return nil
        }
        
        // Generate a CBUS Message from the OpCode and data bytes
        var cbm: CBUSMessage {
            switch opCode {
            case .ASON:     CBUSMessage(opCode: .ASON, device: Int(m[3]) * 256 + Int(m[4]))
            case .ASON1:    CBUSMessage(opCode: .ASON1, device: Int(m[3]) * 256 + Int(m[4]), dataBytes: [m[5]])
            case .ASON2:    CBUSMessage(opCode: .ASON2, device: Int(m[3]) * 256 + Int(m[4]), dataBytes: [m[5], m[6]])
            case .ASON3:    CBUSMessage(opCode: .ASON3, device: Int(m[3]) * 256 + Int(m[4]), dataBytes: [m[5], m[6], m[7]])

            case .ASOF:     CBUSMessage(opCode: .ASOF, device: Int(m[3]) * 256 + Int(m[4]))
            case .ASOF1:    CBUSMessage(opCode: .ASOF1, device: Int(m[3]) * 256 + Int(m[4]), dataBytes: [m[5]])
            case .ASOF2:    CBUSMessage(opCode: .ASOF2, device: Int(m[3]) * 256 + Int(m[4]), dataBytes: [m[5], m[6]])
            case .ASOF3:    CBUSMessage(opCode: .ASOF3, device: Int(m[3]) * 256 + Int(m[4]), dataBytes: [m[5], m[6], m[7]])

            case .ARST:     CBUSMessage(opCode: .ARST)
            case .RLOC:     CBUSMessage(opCode: .ASON, address: Int(m[1]))
            case .PLOC:     CBUSMessage(opCode: .PLOC, address: Int(m[3]), session: Int(m[1]))
            case .GLOC:     CBUSMessage(opCode: .GLOC, address: Int(m[2]), dataBytes: [m[3]])
            case .KLOC:     CBUSMessage(opCode: .KLOC, session: Int(m[1]))
            case .STMOD:    CBUSMessage(opCode: .STMOD)
            case .DKEEP:    CBUSMessage(opCode: .DKEEP)
            case .DSPD:     CBUSMessage(opCode: .DSPD, session: Int(m[1]),
                                                    direction: m[2] & 0x80 == 0x80 ? .forward : .reverse,
                                                    speed: Int(m[2] & 0x7F)
                                        )
            case .ERR:      CBUSMessage(opCode: .ERR, dataBytes: [m[1]])
            case .STOP:     CBUSMessage(opCode: .STOP)
            case .STOPPED:  CBUSMessage(opCode: .STOPPED)
            case .DFNON:    CBUSMessage(opCode: .DFNON)
            case .DFNOF:    CBUSMessage(opCode: .DFNOF)
            case .STAT:     CBUSMessage(opCode: .STAT, dataBytes: [m[4]])
            case .ACON:     CBUSMessage(opCode: .ACON)
            case .UNK:      CBUSMessage(opCode: .UNK)
                
            case .WCVS:     CBUSMessage(opCode: .WCVS)
            case .SSTAT:    CBUSMessage(opCode: .SSTAT, dataBytes: [m[2]])
                
            case .WCVO:     CBUSMessage(opCode: .WCVO)

            case .QCVS:     CBUSMessage(opCode: .QCVS)
            case .PCVS:     CBUSMessage(opCode: .PCVS, cv: Int(m[2]) * 256 + Int(m[3]), dataBytes: [m[4]])
                
            case .RDCC3:    CBUSMessage(opCode: .RDCC3)
            }
        }
        
        return cbm
    }

}

