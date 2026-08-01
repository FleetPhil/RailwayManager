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
    case MQTTConnectFail
    case noDCCSession(Int)
}

