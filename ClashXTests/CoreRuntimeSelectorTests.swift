import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum CoreRuntimeSelectorTests {
    static func main() {
        expect(CoreRuntimeSelector.select(majorVersion: 12) == .legacy, "macOS 12 must remain legacy")
        expect(CoreRuntimeSelector.select(majorVersion: 13) == .mihomo, "macOS 13 must select Mihomo")
        expect(CoreRuntimeSelector.select(majorVersion: 15) == .mihomo, "newer macOS must select Mihomo")
        expect(CoreRuntimeSelector.select(majorVersion: 15, override: "legacy") == .legacy, "legacy override")
        expect(CoreRuntimeSelector.select(majorVersion: 12, override: "mihomo") == .mihomo, "Mihomo override")
        expect(CoreRuntimeSelector.select(majorVersion: 15, override: "invalid") == .mihomo, "invalid override ignored")
        print("CoreRuntimeSelectorTests passed")
    }
}
