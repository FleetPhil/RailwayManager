//
//  Errors.swift
//  ModelRailway
//
//  Created by West Hill Lodge on 02/12/2024.
//

import Foundation

enum TrainError: Error, Equatable {
    case unexpectedTrackState(String)
    case invalidRoute(Int)
    case invalidSensor(Int)
    case invalidPath(String)
    case noStartBlockForRoute(Int)
    case queueError(String)
    case invalidBlockStateChange(String)
    case applicationError(String)
    case noTrainForSetSensor(Int)
    case noCurrentBlockForTrainSensor(Int)
    case noTrainDirection(Int)
    case lockAlreadyExists(Block, Train)
    case noLockToRelease(Block, Train)
    case CBUSError(String)
    case MQTTConnectFail(String)
    case noDCCSession(Int)
    case trainAlreadyActive(Int)
    case unexpectedSensorEvent(String)
    
    var isFatal: Bool {
        switch self {
        case .unexpectedTrackState:         true
        case .invalidRoute:                 true
        case .invalidSensor:                true
        case .invalidPath:                  true
        case .noStartBlockForRoute:         true
        case .queueError:                   true
        case .invalidBlockStateChange:      true
        case .applicationError:             true
        case .noTrainForSetSensor:          false
        case .noCurrentBlockForTrainSensor: true
        case .noTrainDirection:             true
        case .lockAlreadyExists:            false
        case .noLockToRelease:              true
        case .CBUSError:                    true
        case .MQTTConnectFail:              true
        case .noDCCSession:                 true
        case .trainAlreadyActive:           false
        case .unexpectedSensorEvent:        false
        }
    }
}

