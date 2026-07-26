//
//  Errors.swift
//  ModelRailway
//
//  Created by West Hill Lodge on 02/12/2024.
//

import Foundation

enum TrainError: Error, Equatable {
    case routeInErrorState(String)
    case unexpectedTrackState(String)
    case I2CNotReachable(Int)
    case I2CWriteFail
    case missingSerialBoards
    case invalidLayout
    case invalidSegment(String)
    case invalidTransition(String)
    case invalidTrain(Int)
    case invalidRoutine(Int)
    case invalidRoute(Int)
    case invalidBlockState(String)
    case routeStartFail(String)
    case nonContinuousRoute(String)
    case serialPortFail(String)
    case queueError(String)
    case invalidBlockStateChange(String)
    case applicationError(Int)
    case invalidTrainForState(Int)
    case invalidBlockForState(String)
    case noTrainForSetSensor(Int)
    case noCurrentBlockForTrainSensor(Int)
    case noBlockRoute(String, String)
    case noTrainDirection(Int)
    case noBlocksToPowerForTrain(Int)
    case errorProcessingEvent(String)
    case CBUSUnreachable
    case MQTTConnectFail
}

