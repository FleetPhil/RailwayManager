import Foundation

enum LedState {
    case off
    case singleFlash
    case extraSlowFlash
    case slowFlash
    case fastFlash
    case extraFastFlash
    case on

    var durations: ( on: TimeInterval, off: TimeInterval) {
        switch self {
        case .off:              ( 0, 0 )
        case .singleFlash:      ( 0.5, 0 )
        case .extraSlowFlash:   ( 4.0, 1.0 )
        case .slowFlash:        ( 1.0, 1.0 )
        case .fastFlash:        ( 0.5, 0.5 )
        case .extraFastFlash:   ( 0.2, 0.2 )
        case .on:               ( 0, 0 )
        }
    }

    var repeating: Bool {
        switch self {
        case .on, .off:         false
        default:                true
        }
    }
}

enum LEDColour: Int, CaseIterable, Equatable, Hashable {
    case red = 1
    case green = 2
    case blue = 3
    case white = 4
}

actor Led {
    static let shared = Led()

#if os(OSX)
    nonisolated static func setState(_ newState: LedState, forColour: LEDColour) { }
#else
    private var flashTasks: [LEDColour: Task<Void, Never>] = [:]

    nonisolated static func setState(_ newState: LedState, forColour colour: LEDColour) {
        Task { await Led.shared.apply(newState, forColour: colour) }
    }

    private func apply(_ newState: LedState, forColour colour: LEDColour) {
        flashTasks[colour]?.cancel()
        flashTasks[colour] = nil

        if newState.repeating {
            let durations = newState.durations
            flashTasks[colour] = Task {
                while !Task.isCancelled {
                    HardwareManager.setLED(colour, on: true)
                    try? await Task.sleep(for: .seconds(durations.on))
                    guard !Task.isCancelled else { break }
                    HardwareManager.setLED(colour, on: false)
                    try? await Task.sleep(for: .seconds(durations.off))
                }
                HardwareManager.setLED(colour, on: false)
            }
        } else {
            HardwareManager.setLED(colour, on: newState == .on)
        }
    }
#endif
}
