//
//  TrainSpeedSetting.swift
//  ModelRailway
//
//  Created by Phil Diggens on 20/03/2026.
//

import Foundation


struct TrainSpeedSetting: Codable, Equatable, Sendable {
    var power: Int      // Power setting 0-100
    var speed: Int      // Speed in cm/sec
}

// A train's power and speed at each of the set speeds. Stop is always zero
struct TrainSpeeds: Codable, Equatable, Sendable {
    var slow: TrainSpeedSetting
    var normal: TrainSpeedSetting
    var fast: TrainSpeedSetting
    
    // The setting for a train speed; nil for a manual speed, which has no table entry
    func setting(for trainSpeed: TrainSpeed) -> TrainSpeedSetting? {
        switch trainSpeed {
        case .stop:     TrainSpeedSetting(power: 0, speed: 0)
        case .slow:     slow
        case .normal:   normal
        case .fast:     fast
        case .manual:   nil
        }
    }
}

struct TrainStartFunction: Codable, Equatable, Sendable {
    var startFunction: Int
    var delay: TimeInterval
}

struct TrainParams: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var address: Int            // DCC address
    var length: Int             // Length between sensors in cm
    
    var speeds: TrainSpeeds
    
    var startFunctions: [TrainStartFunction] = []       // Run in order at the start of a route (e.g. sounds)
}

// The trains that can be run, built once at startup
struct TrainRoster: Sendable {
    let trains: [Train]
    
    init(_ trainParams: [TrainParams]) {
        trains = trainParams.map(Train.init(trainParams:))
    }
    
    func train(id: Int) -> Train? {
        trains.first(where: { $0.id == id })
    }
}
