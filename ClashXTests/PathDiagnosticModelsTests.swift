import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct PathDiagnosticModelsTests {
    static func main() {
        expect(PathDiagnosticStage.allCases == [.core, .tun, .dns, .node, .internet],
               "stages must follow packet path")

        expect(PathDiagnosticsLogic.exitNode(from: ["Proxy A", "Auto", "MATCH"],
                                             groupNames: ["Auto", "MATCH"]) == "Proxy A",
               "leaf proxy must exclude groups")

        expect(PathDiagnosticsLogic.exitNode(from: ["Auto", "MATCH"],
                                             groupNames: ["Auto", "MATCH"]) == nil,
               "group-only chain must not invent exit node")

        let sanitized = PathDiagnosticsLogic.sanitized("Authorization: Bearer secret-token password=hello")
        expect(!sanitized.contains("secret-token") && !sanitized.contains("hello"),
               "diagnostic detail must redact credentials")

        let failed = PathDiagnosticResult(stage: .dns,
                                          status: .failed,
                                          summary: "Resolution failed",
                                          detail: "host not found",
                                          duration: 0.25,
                                          timestamp: Date())
        let blocked = PathDiagnosticsLogic.blockedResults(after: .dns, existing: [.dns: failed])
        expect(blocked[.node]?.status == .blocked && blocked[.internet]?.status == .blocked,
               "DNS failure must block downstream stages")
        expect(blocked[.core] == nil && blocked[.tun] == nil,
               "upstream stages must remain unchanged")

        expect(PathDiagnosticStatus.checking.displayName == "Checking" &&
            PathDiagnosticStatus.blocked.displayName == "Blocked",
               "every visual state needs a text label")

        print("PathDiagnosticModelsTests: PASS")
    }
}
