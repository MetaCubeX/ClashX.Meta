import Foundation

private final class FakePathDiagnosticsProber: PathDiagnosticsProbing {
    var statuses: [PathDiagnosticStage: PathDiagnosticStatus] = [:]
    var calls: [PathDiagnosticStage] = []

    func probe(_ stage: PathDiagnosticStage, completion: @escaping (PathProbeEvidence) -> Void) {
        calls.append(stage)
        completion(PathProbeEvidence(status: statuses[stage] ?? .healthy,
                                     summary: stage.title,
                                     detail: stage.title,
                                     duration: 0.01))
    }
}

@main
struct PathDiagnosticsServiceTests {
    static func main() {
        let coreFailure = FakePathDiagnosticsProber()
        coreFailure.statuses[.core] = .failed
        let coreSnapshot = run(prober: coreFailure)
        check(coreSnapshot.results[.tun]?.status == .blocked, "core failure blocks TUN")
        check(coreFailure.calls == [.core], "blocked probes do not run")

        let inactiveTun = FakePathDiagnosticsProber()
        inactiveTun.statuses[.tun] = .inactive
        let tunSnapshot = run(prober: inactiveTun)
        check(tunSnapshot.results[.internet]?.status == .healthy, "inactive TUN keeps diagnostics running")
        check(inactiveTun.calls == PathDiagnosticStage.allCases, "all downstream probes run")

        let dnsFailure = FakePathDiagnosticsProber()
        dnsFailure.statuses[.dns] = .failed
        let dnsSnapshot = run(prober: dnsFailure)
        check(dnsSnapshot.results[.node]?.status == .blocked, "DNS failure blocks node")
        check(dnsSnapshot.results[.internet]?.status == .blocked, "DNS failure blocks Internet")

        let nodeFailure = FakePathDiagnosticsProber()
        nodeFailure.statuses[.node] = .failed
        let nodeSnapshot = run(prober: nodeFailure)
        check(nodeSnapshot.results[.internet]?.status == .healthy, "node delay failure does not hide Internet result")

        print("PathDiagnosticsServiceTests: PASS")
    }

    private static func run(prober: FakePathDiagnosticsProber) -> PathDiagnosticsSnapshot {
        let semaphore = DispatchSemaphore(value: 0)
        var snapshot: PathDiagnosticsSnapshot?
        let service = PathDiagnosticsService(prober: prober)
        service.run {
            snapshot = $0
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
        return snapshot!
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
