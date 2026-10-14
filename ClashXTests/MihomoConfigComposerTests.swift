import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum MihomoConfigComposerTests {
    static func main() {
        let missing = "tun:\n  enable: true\nrules: []"
        expect(MihomoConfigComposer.applyingSystemStackDefault(to: missing).contains("tun:\n  stack: system\n"), "missing stack defaults to system")

        let empty = "tun:\n  stack:\n  enable: true"
        expect(MihomoConfigComposer.applyingSystemStackDefault(to: empty).contains("stack: system"), "empty stack defaults to system")

        let explicit = "tun:\n  stack: gvisor\n  enable: true"
        expect(MihomoConfigComposer.applyingSystemStackDefault(to: explicit) == explicit, "explicit gvisor must survive")

        let noTun = "mixed-port: 7890\nrules: []"
        expect(MihomoConfigComposer.applyingSystemStackDefault(to: noTun) == noTun, "do not create TUN section")

        let enabled = MihomoConfigComposer.applyingTunOverride(to: noTun, enabled: true)
        expect(enabled.contains("tun:\n  enable: true\n  stack: system"), "enabled override creates system TUN")

        let disabled = MihomoConfigComposer.applyingTunOverride(to: missing, enabled: false)
        expect(disabled.contains("enable: false"), "disabled override turns existing TUN off")

        let preserveStack = MihomoConfigComposer.applyingTunOverride(to: explicit, enabled: true)
        expect(preserveStack.contains("stack: gvisor"), "enabled override preserves explicit stack")

        let noPort = "mode: rule\nrules: []"
        expect(MihomoConfigComposer.applyingMixedPortDefault(to: noPort).hasPrefix("mixed-port: 7890\n"), "missing proxy ports default to mixed 7890")

        let explicitPort = "port: 8888\nmode: rule"
        expect(MihomoConfigComposer.applyingMixedPortDefault(to: explicitPort) == explicitPort, "explicit proxy port survives")
        print("MihomoConfigComposerTests passed")
    }
}
