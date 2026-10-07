//
//  Errors.swift
//  ModelRailway
//
//  Created by West Hill Lodge on 02/12/2024.
//

import Foundation

enum TrainError: Error, Equatable {
    case unexpectedTrackState(String)
    case invalidRoute(String)
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
    case layoutError(String)
    
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
        case .layoutError:                  false
        }
    }
}

// Readable text for logs and the MQTT error topic
extension TrainError: CustomStringConvertible {
    var description: String {
        switch self {
        case .unexpectedTrackState(let message):        "Unexpected track state: \(message)"
        case .invalidRoute(let message):                "Invalid route: \(message)"
        case .invalidSensor(let address):               "Invalid sensor address \(address)"
        case .invalidPath(let message):                 "Invalid path: \(message)"
        case .noStartBlockForRoute(let routeID):        "No start block for route \(routeID)"
        case .queueError(let message):                  "Queue error: \(message)"
        case .invalidBlockStateChange(let message):     "Invalid block state change: \(message)"
        case .applicationError(let message):            "Application error: \(message)"
        case .noTrainForSetSensor(let address):         "No train for set sensor \(address)"
        case .noCurrentBlockForTrainSensor(let address): "No current block for train sensor \(address)"
        case .noTrainDirection(let trainID):            "No direction set for train \(trainID)"
        case .lockAlreadyExists(let block, let train):  "Direction lock already exists on block \(block) for train \(train)"
        case .noLockToRelease(let block, let train):    "No direction lock to release on block \(block) for train \(train)"
        case .CBUSError(let message):                   "CBUS error: \(message)"
        case .MQTTConnectFail(let message):             "MQTT connection failed: \(message)"
        case .noDCCSession(let trainID):                "No DCC session for train \(trainID)"
        case .trainAlreadyActive(let trainID):          "Train \(trainID) is already running a route"
        case .unexpectedSensorEvent(let message):       "Unexpected sensor event: \(message)"
        case .layoutError(let message):                 "Layout error: \(message)"
        }
    }
}

