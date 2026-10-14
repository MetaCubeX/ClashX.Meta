import Foundation

final class ProxyHealthCheckQueue {
    typealias Work = (@escaping () -> Void) -> Void

    static let shared = ProxyHealthCheckQueue(maxConcurrent: 3)

    private struct Pending {
        let key: String
        let generation: UInt
        let work: Work
        let completion: () -> Void
    }

    private let stateQueue = DispatchQueue(label: "com.west2online.ClashX.health-check-queue")
    private let maxConcurrent: Int
    private var pending = [Pending]()
    private var activeKeys = Set<String>()
    private var activeCount = 0
    private var generation: UInt = 0

    init(maxConcurrent: Int) {
        precondition(maxConcurrent > 0)
        self.maxConcurrent = maxConcurrent
    }

    func enqueue(key: String,
                 work: @escaping Work,
                 completion: @escaping () -> Void = {}) {
        stateQueue.async {
            guard !self.activeKeys.contains(key),
                  !self.pending.contains(where: { $0.key == key && $0.generation == self.generation }) else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            self.pending.append(Pending(key: key,
                                        generation: self.generation,
                                        work: work,
                                        completion: completion))
            self.startNextIfPossible()
        }
    }

    func cancelQueued() {
        stateQueue.async {
            self.generation &+= 1
            let cancelled = self.pending
            self.pending.removeAll()
            cancelled.forEach { item in
                DispatchQueue.main.async(execute: item.completion)
            }
        }
    }

    private func startNextIfPossible() {
        while activeCount < maxConcurrent, !pending.isEmpty {
            let item = pending.removeFirst()
            guard item.generation == generation else { continue }
            activeCount += 1
            activeKeys.insert(item.key)
            item.work { [weak self] in
                self?.finish(item)
            }
        }
    }

    private func finish(_ item: Pending) {
        stateQueue.async {
            self.activeCount = max(0, self.activeCount - 1)
            self.activeKeys.remove(item.key)
            if item.generation == self.generation {
                DispatchQueue.main.async(execute: item.completion)
            }
            self.startNextIfPossible()
        }
    }
}
