//
//  Light.swift
//  ModelRailway
//
//  Created by West Hill Lodge on 24/11/2024.
//

import Foundation

// Trackside LED light set
actor Light: CustomStringConvertible, Sendable {
    let id: Int
    
    enum LightState {
        case on
        case off
        case pendingOff
        case unknown
    }
    
    private var state: LightState = .unknown
    private var isCommandedOn: Bool = false
    
    nonisolated var description: String {
        return "\(id)"
    }
    
    init(id: Int) {
        self.id = id
    }
    
//    func setOn(on: Bool) async {
//        // Set the commanded state
//        isCommandedOn = on
//        
//        switch (isCommandedOn, state) {
//        case (_, .unknown):         // Initial state
//            await TrackCommandDispatcher.shared.setLight(self, on: on)
//            state = on ? .on : .off
//        case (false, .off):        // Commanded off, state off
//            break
//        case (true, .on):         // Commanded on, state on
//            break
//        case (true, .off), (true, .pendingOff):          // Other commanded on
//            await TrackCommandDispatcher.shared.setLight(self, on: on)
//            state = .on
//            
//        case (false, .on):         // Commanded off, state on
//            state = .pendingOff
//            try? await Task.sleep(for: .seconds(1))
//
//            if state == .pendingOff {
//                // Still commanded off
//                state = .off
//                await TrackCommandDispatcher.shared.setLight(self, on: false)
//            } else {
//                // Light has been commanded on during sleep so don't turn off
//                
//            }
//        case (false, .pendingOff):         // Commanded off, state turning off
//            break       // No change
//        }
//        
//    }
}

extension Light: Equatable, Hashable {
    nonisolated static func == (lhs: Light, rhs: Light) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
