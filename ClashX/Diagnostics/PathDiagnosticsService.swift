import Foundation

struct PathProbeEvidence {
    let status: PathDiagnosticStatus
    let summary: String
    let detail: String
    let duration: TimeInterval?
}

protocol PathDiagnosticsProbing: AnyObject {
    func probe(_ stage: PathDiagnosticStage, completion: @escaping (PathProbeEvidence) -> Void)
}

final class PathDiagnosticsService {
    private let prober: PathDiagnosticsProbing
    private let lock = NSLock()
    private var activeRunID: UUID?

    init(prober: PathDiagnosticsProbing) {
        self.prober = prober
    }

    func run(completion: @escaping (PathDiagnosticsSnapshot) -> Void) {
        let runID = UUID()
        lock.lock()
        activeRunID = runID
        lock.unlock()
        run(stageIndex: 0, runID: runID, results: [:], completion: completion)
    }

    func cancel() {
        lock.lock()
        activeRunID = nil
        lock.unlock()
    }

    private func run(
        stageIndex: Int,
        runID: UUID,
        results: [PathDiagnosticStage: PathDiagnosticResult],
        completion: @escaping (PathDiagnosticsSnapshot) -> Void
    ) {
        guard isActive(runID) else { return }
        let stages = PathDiagnosticStage.allCases
        guard stageIndex < stages.count else {
            completion(PathDiagnosticsSnapshot(runID: runID, results: results))
            return
        }

        let stage = stages[stageIndex]
        prober.probe(stage) { [weak self] evidence in
            guard let self = self, self.isActive(runID) else { return }
            var updated = results
            updated[stage] = PathDiagnosticResult(
                stage: stage,
                status: evidence.status,
                summary: evidence.summary,
                detail: PathDiagnosticsLogic.sanitized(evidence.detail),
                duration: evidence.duration,
                timestamp: Date()
            )

            if evidence.status == .failed && (stage == .core || stage == .dns) {
                updated = PathDiagnosticsLogic.blockedResults(after: stage, existing: updated)
                completion(PathDiagnosticsSnapshot(runID: runID, results: updated))
                return
            }

            self.run(stageIndex: stageIndex + 1,
                     runID: runID,
                     results: updated,
                     completion: completion)
        }
    }

    private func isActive(_ runID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeRunID == runID
    }
}
