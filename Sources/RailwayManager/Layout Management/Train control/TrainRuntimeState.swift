//
//  TrainRuntimeState.swift
//  RailwayManager
//
//  Created by Phil Diggens on 26/07/2026.
//

import Foundation

enum TrainRuntimeState: Equatable, CustomStringConvertible {
    case idle
    case running(PathItem)                  // Normal - executing path item
    case waiting                            // Stop commanded in transition or waiting before move
    // Stopping at sensor waiting for block or for other transition item before moving to Block
    case stoppingForResource(TrackResource)         // Blocking Resource
    case stoppedForResource(TrackResource, PathItem)              // Waiting for track resource, PathItem
    case stoppingAtSensor(Sensor, Int)                         // Stopping on transition command after distance
    case stoppingForTimer(Sensor, WaitTime)
    case stoppedAtSensor(Sensor)
    
    var isMoving: Bool {
        switch self {
        case .idle, .stoppedAtSensor, .stoppedForResource, .waiting:
            return false
        case .running, .stoppingForResource, .stoppingAtSensor, .stoppingForTimer:
            return true
        }
    }
    
    var description: String {
        switch self {
        case .idle:
            "Idle"
        case .running(let item):
            "Running (\(item)"
        case .waiting:
            "Waiting"
        case .stoppingForResource(let trackResource):
            "Stopping for resource \(trackResource)"
        case .stoppedForResource(let trackResource, let block):
            "Stopped for resource \(trackResource), \(block)"
        case .stoppingAtSensor(let sensor, let distance):
            "Stopping at sensor \(sensor), \(distance)"
        case .stoppingForTimer(let sensor, let timer):
            "Stopping for timer \(timer) at \(sensor)"
        case .stoppedAtSensor(let sensor):
            "Stopped at sensor \(sensor)"
        }
    }
}



