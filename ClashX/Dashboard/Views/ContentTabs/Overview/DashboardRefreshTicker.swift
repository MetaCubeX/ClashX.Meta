//
//  DashboardRefreshTicker.swift
//  ClashX Dashboard
//

import Foundation

/// A single 1-second heartbeat that dispatches aligned ticks to subscribers.
/// Cards subscribe via `ticks(every:)` and receive an immediate yield on
/// subscribe plus aligned yields at each interval boundary thereafter.
@MainActor
final class DashboardRefreshTicker {
    static let shared = DashboardRefreshTicker()

    private struct Subscription {
        let interval: Int
        let continuation: AsyncStream<Void>.Continuation
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private var tickCount = 0
    private var heartbeatTask: Task<Void, Never>?

    /// Returns an `AsyncStream` that yields immediately on subscribe,
    /// then every `seconds` seconds aligned to the global 1-second tick.
    func ticks(every seconds: Int) -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield()
            self.subscriptions[id] = Subscription(interval: seconds, continuation: continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.subscriptions.removeValue(forKey: id)
                    if self?.subscriptions.isEmpty == true {
                        self?.stop()
                    }
                }
            }
            self.startIfNeeded()
        }
    }

    // MARK: - Private

    private func startIfNeeded() {
        guard heartbeatTask == nil else { return }
        tickCount = 0
        heartbeatTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(seconds: 1)
                guard !Task.isCancelled else { break }
                self.fire()
            }
        }
    }

    private func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        tickCount = 0
    }

    private func fire() {
        tickCount += 1
        // Dispatch 1s subscribers first, then 3s, then 5s — ensures data
        // producers (flush, connections poll) run before UI readers.
        let ordered = subscriptions.values.sorted { $0.interval < $1.interval }
        for sub in ordered where tickCount % sub.interval == 0 {
            sub.continuation.yield()
        }
    }
}
