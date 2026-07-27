//
//  TrainSpeedSetting.swift
//  ModelRailway
//
//  Created by Phil Diggens on 20/03/2026.
//


struct TrainSpeedSetting: Codable, Equatable {
    var power: Int      // Power setting 0-100
    var speed: Int      // Speed in cm/sec
}

struct TrainParams: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var address: Int
    
    var trainSpeeds: [ TrainSpeed : TrainSpeedSetting ]
}
