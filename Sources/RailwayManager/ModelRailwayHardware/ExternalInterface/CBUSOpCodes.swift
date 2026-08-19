//
//  File.swift
//  ModelRailwayHardware
//
//  Created by Phil Diggens on 24/07/2026.
//

import Foundation

enum OpCode: UInt8 {
    case ASON       = 0x98
    case ASOF       = 0x99
    case ASOF1      = 0xB9
    case ASOF2      = 0xD9
    case ASOF3      = 0xF9
    case ASON1      = 0xB8
    case ASON2      = 0xD8
    case ASON3      = 0xF8
    
    case ARST       = 0x07
    case RLOC       = 0x40
    case PLOC       = 0xE1
    case GLOC       = 0x61
    case KLOC       = 0x21
    case STMOD      = 0x44
    case DKEEP      = 0x23
    case DSPD       = 0x47
    case ERR        = 0x63
    case STOP       = 0x0A
    case STOPPED    = 0x06
    case DFNON      = 0x49
    case DFNOF      = 0x4A
    case STAT       = 0xE3
    case ACON       = 0x90
    
    case WCVS       = 0xA2
    case QCVS       = 0x84
    case PCVS       = 0x85
    case SSTAT      = 0x4C
    
    case WCVO       = 0x82
    
    case RDCC3      = 0x80
    
    // Dummy
    case UNK        = 0xFF
    
    var name: String {
        switch self {
        case .ASON:     "ASON"
        case .ASOF:     "ASOF"
        case .ASOF1:    "ASOF1"
        case .ASOF2:    "ASOF2"
        case .ASOF3:    "ASOF3"
        case .ASON1:    "ASON1"
        case .ASON2:    "ASON2"
        case .ASON3:    "ASON3"
        case .ARST:     "ARST"
        case .RLOC:     "RLOC"
        case .PLOC:     "PLOC"
        case .GLOC:     "GLOC"
        case .KLOC:     "KLOC"
        case .STMOD:    "STMOD"
        case .DKEEP:    "DKEEP"
        case .DSPD:     "DSPD"
        case .ERR:      "ERR"
        case .STOP:     "STOP"
        case .STOPPED:  "STOPPED"
        case .DFNON:    "DFNON"
        case .DFNOF:    "DFNOF"
        case .STAT:     "STAT"
        case .ACON:     "ACON"
        case .UNK:      "UNK"
        case .WCVS:     "WCVS"      // Write CV
        case .QCVS:     "QCVS"      // Query CV
        case .PCVS:     "PCVS"      // CV Value
        case .SSTAT:    "SSTAT"     // CV update status
            
        case .WCVO:     "WCVO"     // CV write OTM
            
        case .RDCC3:    "RDCC3"     // DCC 3 byte packet
        }
    }
    
    var dataByteCount: Int {
        switch self {
        case .ASON:     0
        case .ASOF:     0
        case .ASOF1:    1
        case .ASOF2:    2
        case .ASOF3:    3
        case .ASON1:    1
        case .ASON2:    2
        case .ASON3:    3
        default:        0
        }
    }
}
