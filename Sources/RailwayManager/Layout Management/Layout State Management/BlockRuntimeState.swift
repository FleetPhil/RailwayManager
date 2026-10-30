import Foundation

// A train's state in a block, with the train's travel direction in that block
// (a train part-way round a reversing loop travels in different directions in different blocks)
enum BlockRuntimeState: Equatable {
    case vacant
    case reserved(Train, BlockDirection)
    case occupied(Train, BlockDirection)
    case vacating(Train, BlockDirection)
    
    var isVacant: Bool {
        switch self {
        case .vacant:   true
        default:        false
        }
    }
    
    var train: Train? {
        switch self {
        case .reserved(let train, _), .occupied(let train, _), .vacating(let train, _):  train
        case .vacant: nil
        }
    }
    
    var direction: BlockDirection? {
        switch self {
        case .reserved(_, let direction), .occupied(_, let direction), .vacating(_, let direction):  direction
        case .vacant: nil
        }
    }
    
    // The same state with the travel direction reversed (the train has changed direction)
    var reversed: BlockRuntimeState {
        switch self {
        case .vacant:                                   .vacant
        case .reserved(let train, let direction):       .reserved(train, direction.oppositeDirection)
        case .occupied(let train, let direction):       .occupied(train, direction.oppositeDirection)
        case .vacating(let train, let direction):       .vacating(train, direction.oppositeDirection)
        }
    }
}

struct PointRuntimeState: CustomStringConvertible, Sendable, Equatable {
    var direction: PointDirection
    var reservedByTrain: Train?
    var freeWithBlock: Block?           // When the block frees then free the point as well
    
    var description: String {
        var result = "\(direction)"
        if let reservedByTrain { result.append(", reserved \(reservedByTrain)") }
        if let freeWithBlock { result.append(", free with \(freeWithBlock)") }
        return result
    }
}

// A train expecting to travel through a vacant block in the given direction.
// Another train can't enter the block in the opposite direction while it is held.
struct DirectionLock: Sendable, Equatable {
    let train: Train
    let direction: BlockDirection
}
