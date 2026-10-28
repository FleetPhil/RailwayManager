//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 04/08/2026.
//

import Foundation

// Speeds in cm/s, train length in cm

extension TrainRoster {
    // The hard-coded train roster
    static let standard = TrainRoster([
        TrainParams(id: 1,
                    name: "SBB Re430",
                    address: 20,
                    length: 70,
                    speeds: TrainSpeeds(slow:   TrainSpeedSetting(power: 40, speed: 6),
                                        normal: TrainSpeedSetting(power: 50, speed: 15),
                                        fast:   TrainSpeedSetting(power: 70, speed: 29)),
                    startFunctions: [
//                        TrainStartFunction(startFunction: 8, delay: 8),       // Platform announcement
//                        TrainStartFunction(startFunction: 2, delay: 2),       // Horn up/down
//                        TrainStartFunction(startFunction: 3, delay: 2),       // Horn single
//                        TrainStartFunction(startFunction: 7, delay: 5),       // Running noise
                        TrainStartFunction(startFunction: 5, delay: 2),         // Whistle
//                        TrainStartFunction(startFunction: 14, delay: 5),      // Long platform announcement
//                        TrainStartFunction(startFunction: 15, delay: 10),     // Long platform announcement
                    ]),

        TrainParams(id: 2,
                    name: "Bernina",
                    address: 22,
                    length: 26,
                    speeds: TrainSpeeds(slow:   TrainSpeedSetting(power: 25, speed: 12),
                                        normal: TrainSpeedSetting(power: 40, speed: 20),
                                        fast:   TrainSpeedSetting(power: 60, speed: 40))),

        TrainParams(id: 3,
                    name: "Train 3",
                    address: 23,
                    length: 26,
                    speeds: TrainSpeeds(slow:   TrainSpeedSetting(power: 25, speed: 12),
                                        normal: TrainSpeedSetting(power: 40, speed: 20),
                                        fast:   TrainSpeedSetting(power: 60, speed: 40))),
    ])
}
