//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 04/08/2026.
//

import Foundation

// Speeds in cm/s, train length in cm

struct Trains {
    static var trainParams: [TrainParams] {
        let sbbTrainID = 1
        var sbbSpeeds: [ TrainSpeed : TrainSpeedSetting ] {
            [
                .stop :     TrainSpeedSetting(power: 0, speed: 0),
                .slow :     TrainSpeedSetting(power: 40, speed: 6),
                .normal :   TrainSpeedSetting(power: 50, speed: 15),
                .fast :     TrainSpeedSetting(power: 70, speed: 29),
            ]
        }
        
        var sbbStartFunctions: [TrainStartFunction] {
            [
//                TrainStartFunction(startFunction: 8, delay: 8),       // Platform announcement
//                TrainStartFunction(startFunction: 2, delay: 2),        // Horn up/down
//                TrainStartFunction(startFunction: 3, delay: 2),        // Horn single
//                TrainStartFunction(startFunction: 7, delay: 5),        // Running noise

                TrainStartFunction(startFunction: 5, delay: 2),        // Whistle
//                TrainStartFunction(startFunction: 14, delay: 5),        // Long platforma announcement
//                TrainStartFunction(startFunction: 15, delay: 10),        // Long platforma announcement

            ]
        }
        let bernTrainID = 2
        var bernSpeeds: [ TrainSpeed : TrainSpeedSetting ] {
            [
                .stop :     TrainSpeedSetting(power: 0, speed: 0),
                .slow :     TrainSpeedSetting(power: 25, speed: 12),
                .normal :   TrainSpeedSetting(power: 40, speed: 20),
                .fast :     TrainSpeedSetting(power: 60, speed: 40),
            ]
        }
        
        var bernStartFunctions: [TrainStartFunction] {
            [
            ]
        }

        return [
            TrainParams(id: sbbTrainID,
                        name: "SBB Re430",
                        address: 20,
                        length: 70,
                        trainSpeeds: sbbSpeeds, startFunctions: sbbStartFunctions),
            TrainParams(id: bernTrainID,
                        name: "Bernina",
                        address: 22,
                        length: 26,
                        trainSpeeds: bernSpeeds,
                        startFunctions: bernStartFunctions)
        ]
    }

    static var trains: [Train] {
        return trainParams.map { Train(trainParams: $0) }
    }
}
