//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 04/08/2026.
//

import Foundation

struct Trains {
    static var trainParams: [TrainParams] {
        var trainID = 1
        var sbbSpeeds: [ TrainSpeed : TrainSpeedSetting ] {
            [
                .stop :     TrainSpeedSetting(power: 0, speed: 0),
                .slow :     TrainSpeedSetting(power: 12, speed: 12),
                .normal :   TrainSpeedSetting(power: 20, speed: 20),
                .fast :     TrainSpeedSetting(power: 40, speed: 40),
            ]
        }
        
        var sbbStartFunctions: [TrainStartFunction] {
            [
                TrainStartFunction(startFunction: 8, delay: 10),       // Platform announcement
                TrainStartFunction(startFunction: 5, delay: 2),        // Conductor whistle
            ]
        }
        
        return [TrainParams(id: trainID, name: "SBB Re430", address: 20, trainSpeeds: sbbSpeeds, startFunctions: sbbStartFunctions)]
    }
     
    static var trains: [Train] {
        return trainParams.map { Train(trainParams: $0) }
    }
}
