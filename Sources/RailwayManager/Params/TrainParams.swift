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

// A DCC function turned on at the start of a route (e.g. a sound), then off after the delay.
// In JSON, description and enabled are optional: {"function": 5, "delay": 2, "description": "Whistle"}
struct TrainStartFunction: Codable, Equatable, Sendable {
    var function: Int
    var delay: TimeInterval             // Seconds before the next function
    var description: String? = nil
    var enabled: Bool = true            // A disabled function is kept in the file but not run
}

extension TrainStartFunction {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        function = try container.decode(Int.self, forKey: .function)
        delay = try container.decode(TimeInterval.self, forKey: .delay)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct TrainParams: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var address: Int            // DCC address
    var length: Int             // Length between sensors in cm
    
    var speeds: TrainSpeeds
    
    var startFunctions: [TrainStartFunction] = []       // Run in order at the start of a route (e.g. sounds)
}

// startFunctions is optional in JSON
extension TrainParams {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(Int.self, forKey: .address)
        length = try container.decode(Int.self, forKey: .length)
        speeds = try container.decode(TrainSpeeds.self, forKey: .speeds)
        startFunctions = try container.decodeIfPresent([TrainStartFunction].self, forKey: .startFunctions) ?? []
    }
}

// The trains that can be run, loaded once at startup
struct TrainRoster: Sendable {
    let trains: [Train]
    
    // Throws if the parameters are not valid
    init(_ trainParams: [TrainParams]) throws {
        try Self.validate(trainParams)
        trains = trainParams.map(Train.init(trainParams:))
    }
    
    func train(id: Int) -> Train? {
        trains.first(where: { $0.id == id })
    }
}

// MARK: Loading
extension TrainRoster {
    // Used when no path is given, if it exists
    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".railwaymanager/trains.json")
    }
    
    // Load the roster from the JSON file at path (~ allowed) if given, otherwise from the default
    // file if it exists, otherwise from the trains.json resource built into the app
    static func load(path: String?) throws -> TrainRoster {
        let url: URL
        if let path {
            url = URL(filePath: NSString(string: path).expandingTildeInPath)
        } else if FileManager.default.fileExists(atPath: defaultFileURL.path) {
            url = defaultFileURL
        } else if let bundledURL = Bundle.module.url(forResource: "trains", withExtension: "json") {
            url = bundledURL
        } else {
            throw TrainError.trainRosterError("No trains file at \(defaultFileURL.path) and no built-in trains.json")
        }
        
        let trainParams: [TrainParams]
        do {
            trainParams = try JSONDecoder().decode([TrainParams].self, from: Data(contentsOf: url))
        } catch {
            throw TrainError.trainRosterError("Can't read \(url.path): \(error)")
        }
        let roster = try TrainRoster(trainParams)
        log.info("Loaded \(roster.trains.count) trains from \(url.path)")
        return roster
    }
}

// MARK: Validation
extension TrainRoster {
    // Ids and DCC addresses must be unique; lengths and speeds positive, power 0-100,
    // increasing from slow to fast; start function delays not negative
    private static func validate(_ trainParams: [TrainParams]) throws {
        guard trainParams.isEmpty == false else {
            throw TrainError.trainRosterError("No trains defined")
        }
        for (id, duplicates) in Dictionary(grouping: trainParams, by: \.id) where duplicates.count > 1 {
            throw TrainError.trainRosterError("Train id \(id) is used by \(duplicates.map(\.name))")
        }
        for (address, duplicates) in Dictionary(grouping: trainParams, by: \.address) where duplicates.count > 1 {
            throw TrainError.trainRosterError("DCC address \(address) is used by \(duplicates.map(\.name))")
        }
        
        for train in trainParams {
            let name = "Train \(train.id) (\(train.name))"
            guard train.address > 0 else {
                throw TrainError.trainRosterError("\(name): DCC address must be positive")
            }
            guard train.length > 0 else {
                throw TrainError.trainRosterError("\(name): length must be positive")
            }
            let settings = [train.speeds.slow, train.speeds.normal, train.speeds.fast]
            guard settings.allSatisfy({ (0...100).contains($0.power) && $0.speed > 0 }) else {
                throw TrainError.trainRosterError("\(name): each speed needs power 0-100 and a positive speed")
            }
            guard train.speeds.slow.power <= train.speeds.normal.power,
                  train.speeds.normal.power <= train.speeds.fast.power else {
                throw TrainError.trainRosterError("\(name): power must not decrease from slow to normal to fast")
            }
            guard train.startFunctions.allSatisfy({ $0.delay >= 0 }) else {
                throw TrainError.trainRosterError("\(name): start function delays must not be negative")
            }
        }
    }
}
