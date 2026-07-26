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
    case stoppingForResource(TrackResource, Sensor, Int, PathItem)         // Resource, Sensor, PathItem
    case stoppedForResource(TrackResource, PathItem)              // Waiting for track resource, PathItem
    case stoppingAtSensor(Sensor, Int)                         // Stopping on transition command after distance
    case stoppedAtSensor(Sensor)
    
    var isMoving: Bool {
        switch self {
        case .idle, .stoppedAtSensor, .stoppedForResource, .waiting:
            return false
        case .running, .stoppingForResource, .stoppingAtSensor:
            return true
        }
    }
    
    var pathItem: PathItem? {
        switch self {
        case .running(let item), .stoppedForResource(_ , let item), .stoppingForResource(_, _, _, let item):
            return item
        default:
            return nil
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
        case .stoppingForResource(let trackResource, let stopSensor, let distance, let block):
            "Stopping for resource \(trackResource), \(stopSensor), \(distance), \(block)"
        case .stoppedForResource(let trackResource, let block):
            "Stopped for resource \(trackResource), \(block)"
        case .stoppingAtSensor(let sensor, let distance):
            "Stopping at sensor \(sensor), \(distance)"
        case .stoppedAtSensor(let sensor):
            "Stopped at sensor \(sensor)"
        }
    }
}



