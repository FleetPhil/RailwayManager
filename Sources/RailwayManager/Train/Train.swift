//
//  Train.swift
//
//
//  Created by Phil Diggens on 19/10/2024.
//

import Foundation

enum TrainSpeed: Sendable, Codable, Equatable, Hashable, CustomStringConvertible {
    case stop
    case slow
    case normal
    case fast
    case manual(speed: Int)
    
    var description: String {
        switch self {
        case .stop:
            "Stop"
        case .normal:
            "Normal"
        case .slow:
            "Slow"
        case .fast:
            "Fast"
        case .manual(let speed):
            "Manual \(speed)"
        }
    }
    
}

extension TrainSpeed {
    enum CodingKeys: String, CodingKey {
        case stop
        case slow
        case normal
        case fast
        case manual
    }
}

// The position of a sensor on a train
enum TrainSensor {
    case front
    case rear
    
    var oppositePosition: Self {
        self == .front ? .rear : .front
    }
}

struct Train: Sendable, CustomStringConvertible {
    let id: Int
    let name: String
    private let hardware: HardwareTrain
    
    let length: Int
    
    let speeds: [ TrainSpeed : TrainSpeedSetting]
    let startFunctions: [TrainStartFunction]
    
    let trainFrontSensorOrientation: SensorEventOrientation = .north
    let trainRearSensorOrientation: SensorEventOrientation = .south

    init(trainParams: TrainParams) {
        self.id = trainParams.id
        self.name = trainParams.name
        self.length = trainParams.length
        self.speeds = trainParams.trainSpeeds
        self.startFunctions = trainParams.startFunctions
        
        self.hardware = CBUSHardwareTrain(id: trainParams.id, address: trainParams.address)
    }
    
    nonisolated var description: String {
        return "\(self.id)"
    }
    
    public var address: Int {
        hardware.address
    }
    
    func setSpeed(_ speed: TrainSpeed, direction: BlockDirection, delay: TimeInterval?, session: Int) async throws {
        let power = powerForSpeed(speed)
        try await hardware.setSpeed(power, direction: direction, delay: delay ?? 0.0, session: session)
    }
    
    func setFunction(_ function: Int, on: Bool, session: Int) async throws {
        try await hardware.setFunction(function, on: on, session: session)
    }
    
    func powerForSpeed(_ trainSpeed: TrainSpeed) -> Int {
        switch trainSpeed {
        case .manual(speed: let speed):     return speed
        default:                            return speeds[trainSpeed]?.power ?? 0
        }
    }
    
    
    
}

extension Train: Equatable, Hashable {
    static func == (lhs: Train, rhs: Train) -> Bool {
        return lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
