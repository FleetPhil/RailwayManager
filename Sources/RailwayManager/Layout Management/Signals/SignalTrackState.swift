//
//  SignalTrackState.swift
//  RailwayManager
//
//  Created by Phil Diggens on 26/07/2026.
//

import Foundation

// Function to return the track state of the signal based on a track state snapshot

enum SignalTrackState {
    case signalIndicationNotBlockDirection
    case signalBlockOccupiedOppositeDirection
    case indicatedBlockOccupiedSameDirection
    case indicatedBlockOccupiedOppositeDirection
    case signalBlockOccupiedIndicatedBlockVacant
    case signalBlockVacantIndicatedBlockVacant
    case stoppingAtAssociatedSensor
    case nextBlockUnavailable
    case unexpectedState
}

// Return the basic signal state according to the current track conditions
extension Signal {
    func signalIndication(snapshot: LayoutTrackSnapshot) -> SignalTrackState {
        guard let nextBlock = nextBlock(snapshot: snapshot) else {
            // Next block is unavailable (assume end of line or points against)
            return .nextBlockUnavailable
        }
        
        // Deal with the case where the block direction conflicts with the signal direction
        if let locationBlockDirection = snapshot.travelDirection(in: self.location) {
            if self.direction != locationBlockDirection {
                return  .signalIndicationNotBlockDirection
            }
        }
        
        guard let signalBlockState =  snapshot.blockState(location) else { return .unexpectedState }
        switch signalBlockState {
        // TODO: reserved block signal should check if train is stopping
        case .occupied(let train):
            // Check the block direction
            guard let signalBlockDirection = snapshot.travelDirection(in: self.location) else { return .unexpectedState }
            if signalBlockDirection != self.direction {
                // Block is occupied in the opposite direction or unknown state
                return .signalBlockOccupiedOppositeDirection
            }
            
            // Check if the train is stopping at a sensor in the signal block
            switch snapshot.trainState(train) {
            case .stoppingAtSensor(let stopSensor, _):
                if stopSensor.location.block == self.location {
                    return .stoppingAtAssociatedSensor
                } else {
                    break
                }
            default:    break
            }
            
            // Train is moving through this block in the direction of the signal
            // Check if the next block is reserved for this train, if so treat as vacant
            if let nextBlockReservedTrain = snapshot.blockState(nextBlock)?.train {
                if nextBlockReservedTrain == train {
                    return .signalBlockOccupiedIndicatedBlockVacant
                }
            }
            
            // Next block is not occupied for this train
            guard let nextBlockState = snapshot.blockState(nextBlock) else { return .unexpectedState }
            switch nextBlockState {
            case .vacant:
                return .signalBlockOccupiedIndicatedBlockVacant
            
            case .reserved(let reservedTrain):
                if reservedTrain == train { return .signalBlockOccupiedIndicatedBlockVacant }
                
                // reserved for another route - check the direction
                let reservedDirection = snapshot.travelDirection(in: nextBlock)
                return reservedDirection == self.direction ? .indicatedBlockOccupiedSameDirection : .indicatedBlockOccupiedOppositeDirection
            case .occupied, .vacating:
                // Direction is not relevant
                return .indicatedBlockOccupiedSameDirection
            }
            
        default:
            break
        }
        
        // Done with cases where the signal block is occupied
        
        // Check next block state
        guard let nextBlockState = snapshot.blockState(nextBlock) else { return .unexpectedState }
        
        switch nextBlockState {
        case .vacant:
            return .signalBlockVacantIndicatedBlockVacant
            
        case .reserved, .occupied, .vacating:
            let nextBlockDirection = snapshot.travelDirection(in: nextBlock)
            return nextBlockDirection == self.direction ? .indicatedBlockOccupiedSameDirection : .indicatedBlockOccupiedOppositeDirection
        }
    }
    
    // The block that the signal is currently indicating for or nil if it's inaccessable or route is blocked
    func nextBlock(snapshot: LayoutTrackSnapshot) ->  Block? {
//        log.verbose("Checking next block for \(indication)")
        switch indication {
        case .block(let block):             // If a block follows the signal and the status is monitored return it
            return nextMonitoredBlock(afterBlock: block, snapshot: snapshot)
            
        case .point(let point, let pointDirection):
            // check if the point is reserved for a different block to the one in the signal block
            if let locationBlockTrain = snapshot.blockState(self.location)?.train,
            let pointTrain = snapshot.reservedTrainForPoint(point) {
                if locationBlockTrain != pointTrain {
                    // Point is reserved for a different train
                    return nil
                }
            }

            // Point is free or reserved for this train
            
            if let nextBlock = nextActiveBlock(afterPoint: point, entering: pointDirection, snapshot: snapshot) {
                return nextMonitoredBlock(afterBlock: nextBlock, snapshot: snapshot)
            } else {
                return nil        // Point set against this direction
            }
        }
    }
    
    fileprivate func nextMonitoredBlock(afterBlock: Block, snapshot: LayoutTrackSnapshot) -> Block? {
        if afterBlock.isUnMonitored == false {
            return afterBlock
        }
        
        // The status of this block is not managed so get the next one (assume no more than one)
        switch afterBlock.blockExit[direction]! {
        case .block(let nextBlock):
            return nextBlock
        case .point(let pointSetting):
            return nextActiveBlock(afterPoint: pointSetting.point, entering: pointSetting.direction, snapshot: snapshot)
        default:
            return nil
        }
    }
    
    // Return the next block entering the point from this direction or nil if the point is against us or error
    fileprivate func nextActiveBlock(afterPoint: Point, entering: PointDirection, snapshot: LayoutTrackSnapshot) -> Block? {
        // Check if point is against us
        guard let currentDirection = snapshot.pointState(afterPoint)?.direction else { return nil }
        
        if entering == .splitBranch && currentDirection == .splitStraight { return nil }
        if entering == .splitStraight && currentDirection == .splitBranch { return nil }

        // Point is in our favour so find the next block
        // Find the exit from this point
        // If entering single it's the point direction, otherwise it's single
        let exitDirection = entering == .single ? currentDirection : .single
        
        // If the exit is another point then calculate the exit from that
        switch afterPoint.connections[exitDirection] {
        case .block(let block):
            return block
        case .point(let point, let direction):
            return nextActiveBlock(afterPoint: point, entering: direction, snapshot: snapshot)
        case .none:
            return nil
        }
    }

}

