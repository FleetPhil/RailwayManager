import Foundation

actor EventBus<Event: Sendable> {
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    func publish(_ event: Event) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func subscribe() -> AsyncStream<Event> {
        let id = UUID()

        // Bounded buffer so a stalled subscriber cannot grow memory without limit
        return AsyncStream(bufferingPolicy: .bufferingNewest(1024)) { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
