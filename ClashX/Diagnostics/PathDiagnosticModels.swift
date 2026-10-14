import Foundation

enum PathDiagnosticStage: Int, CaseIterable {
    case core
    case tun
    case dns
    case node
    case internet

    var title: String {
        switch self {
        case .core: return "Clash Core"
        case .tun: return "TUN / Route"
        case .dns: return "DNS"
        case .node: return "Exit Node"
        case .internet: return "Internet"
        }
    }
}

enum PathDiagnosticStatus: Equatable {
    case checking
    case healthy
    case failed
    case blocked
    case inactive

    var displayName: String {
        switch self {
        case .checking: return "Checking"
        case .healthy: return "Healthy"
        case .failed: return "Failed"
        case .blocked: return "Blocked"
        case .inactive: return "Inactive"
        }
    }
}

struct PathDiagnosticResult {
    let stage: PathDiagnosticStage
    let status: PathDiagnosticStatus
    let summary: String
    let detail: String
    let duration: TimeInterval?
    let timestamp: Date
}

struct PathDiagnosticsSnapshot {
    let runID: UUID
    let results: [PathDiagnosticStage: PathDiagnosticResult]
}

enum PathDiagnosticsLogic {
    static func blockedResults(
        after failedStage: PathDiagnosticStage,
        existing: [PathDiagnosticStage: PathDiagnosticResult]
    ) -> [PathDiagnosticStage: PathDiagnosticResult] {
        var results = existing
        let now = Date()
        for stage in PathDiagnosticStage.allCases where stage.rawValue > failedStage.rawValue {
            results[stage] = PathDiagnosticResult(
                stage: stage,
                status: .blocked,
                summary: "Blocked upstream",
                detail: "\(failedStage.title) failed, so this stage was not tested.",
                duration: nil,
                timestamp: now
            )
        }
        return results
    }

    static func exitNode(from chains: [String], groupNames: Set<String>) -> String? {
        return chains.first { !groupNames.contains($0) && $0 != "DIRECT" && $0 != "REJECT" }
    }

    static func sanitized(_ message: String) -> String {
        var value = message
        let patterns = [
            "(?i)(authorization\\s*:\\s*bearer\\s+)[^\\s]+",
            "(?i)(password\\s*=\\s*)[^\\s&]+",
            "(?i)(secret\\s*=\\s*)[^\\s&]+",
            "(?i)(token\\s*=\\s*)[^\\s&]+",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..., in: value)
            value = regex.stringByReplacingMatches(in: value,
                                                   range: range,
                                                   withTemplate: "$1<redacted>")
        }
        return value
    }
}
