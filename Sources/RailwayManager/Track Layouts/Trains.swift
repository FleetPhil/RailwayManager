//
//  File.swift
//  RailwayManager
//
//  Created by Phil Diggens on 04/08/2026.
//

import Foundation

struct Trains {

    static var sbb: Train {
        let sbbParams = TrainParams(id: 1, name: "SBB Re430", address: 20, trainSpeeds: [:])
        return Train(trainParams: sbbParams)
    }
    
}
