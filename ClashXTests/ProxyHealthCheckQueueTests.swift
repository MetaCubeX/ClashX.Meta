import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum ProxyHealthCheckQueueTests {
    static func main() {
        let queue = ProxyHealthCheckQueue(maxConcurrent: 3)
        let lock = NSLock()
        var active = 0
        var maximum = 0
        var starts = [Int]()
        var completed = 0

        for index in 0..<8 {
            queue.enqueue(key: "node-\(index)", work: { done in
                lock.lock()
                active += 1
                maximum = max(maximum, active)
                starts.append(index)
                lock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) {
                    lock.lock()
                    active -= 1
                    lock.unlock()
                    done()
                }
            }, completion: {
                completed += 1
            })
        }

        let deadline = Date().addingTimeInterval(2)
        while completed < 8, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        expect(completed == 8, "all queued checks must finish")
        expect(maximum == 3, "queue must cap concurrency at three")
        expect(starts == Array(0..<8), "queue must preserve FIFO start order")
        print("ProxyHealthCheckQueueTests passed")
    }
}
