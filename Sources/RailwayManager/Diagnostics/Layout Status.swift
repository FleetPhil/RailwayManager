//
//  Layout Status.swift
//  RailwayManager
//
//  Created by Phil Diggens on 27/07/2026.
//

import Foundation

extension LayoutTrackStateService {
    func printStatus() async {
        let snapshot = await snapshot()
        
        for train in snapshot.allTrains {
            log.verbose("Train \(train.id) (\(train.address)): \(snapshot.trainState(train)!)")
        }
        
        for block in snapshot.allBlocks.sorted(by: { $0.id < $1.id }) {
            let blockState = snapshot.blockState(block)!
            if  blockState != .vacant {
                log.verbose("\(block): \(blockState)")
            }
            
            if let locks = snapshot.directionLocks(block) {
                log.verbose("\(block) locks: \(locks.map({ "\($0.train.id) \($0.direction)" }))")
            }
        }
        
        let signalStates = snapshot.allSignals
            .sorted(by: { $0.id < $1.id })
            .filter({ snapshot.signalState($0)! != (.stop, .stop) })
            .map({ signal in
                "\(signal.id): \(snapshot.signalState(signal)!)"
            })
        log.verbose("Signals: \(signalStates)")

        for point in snapshot.allPoints.sorted(by: { $0.id < $1.id }) {
            log.verbose("Point \(point.id): \(snapshot.pointState(point)!)")
        }
    }
}


