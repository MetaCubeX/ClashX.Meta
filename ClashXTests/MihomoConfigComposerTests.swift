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
        print("MihomoConfigComposerTests passed")
    }
}
