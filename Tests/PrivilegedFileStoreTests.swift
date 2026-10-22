import Darwin
import Foundation

@main
struct PrivilegedFileStoreTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "SecurityTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
    }

    private static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }
        throw NSError(domain: "SecurityTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let source = directory.appendingPathComponent("source")
        let bytes = Data("abc".utf8)
        try bytes.write(to: source)

        try expect(PrivilegedDirectory.sha256(bytes) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA256 known vector")
        try expect(PrivilegedDirectory.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "Empty SHA256 vector")
        try expect(PrivilegedDirectory.isSHA256(PrivilegedDirectory.sha256(bytes)), "Accept canonical SHA256")
        for invalid in ["", String(repeating: "a", count: 32), String(repeating: "g", count: 64), String(repeating: "A", count: 64)] {
            try expect(!PrivilegedDirectory.isSHA256(invalid), "Reject noncanonical digest")
        }
        try expect(try PrivilegedDirectory.readSource(source.path, limit: 3) == bytes, "Read exactly at the limit")
        try rejects("Reject oversized regular source") { _ = try PrivilegedDirectory.readSource(source.path, limit: 2) }
        try rejects("Reject directory sources") { _ = try PrivilegedDirectory.readSource(directory.path, limit: 100) }
        try rejects("Reject relative source") { _ = try PrivilegedDirectory.readSource("relative", limit: 100) }
        try rejects("Reject NUL in source") { _ = try PrivilegedDirectory.readSource(source.path + "\0ignored", limit: 100) }

        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        try rejects("Reject symbolic-link source") { _ = try PrivilegedDirectory.readSource(link.path, limit: 100) }
        let fifo = directory.appendingPathComponent("fifo")
        try expect(mkfifo(fifo.path, 0o600) == 0, "Create FIFO fixture")
        try rejects("Reject FIFO without blocking") { _ = try PrivilegedDirectory.readSource(fifo.path, limit: 100) }
        try rejects("Reject writable ancestor for privileged destination") { _ = try PrivilegedDirectory.open(directory.path) }
        try rejects("Reject relative privileged destination") { _ = try PrivilegedDirectory.open("relative") }
        try rejects("Reject path traversal") { _ = try PrivilegedDirectory.open("/Library/../private") }

        let root = try PrivilegedDirectory.open("/")
        try rejects("Reject slash in a descriptor-relative name") { _ = try root.read("Library/file", limit: 100) }
        try rejects("Reject dot-dot relative name") { _ = try root.read("..", limit: 100) }

        let request = ProxyConfigHelperMessages.StartMeta(path: source.path, core: .bundled,
            confPath: directory.path, configData: bytes, confJSON: "{}")
        let encoded = try ProxyConfigHelperXPCCodec.encodeRequest(request)
        let envelope = try ProxyConfigHelperXPCCodec.decodeRequestEnvelope(from: encoded)
        let decoded = try ProxyConfigHelperXPCCodec.decodeMessage(ProxyConfigHelperMessages.StartMeta.self, from: envelope)
        try expect(decoded.configData == bytes && decoded.core == .bundled, "V2 request preserves config bytes and core selector")
        let oldPayload = Data(#"{"path":"/tmp/core","confPath":"/tmp","confFilePath":"/tmp/config","confJSON":"{}","coreMD5":""}"#.utf8)
        try rejects("Reject the legacy start message") {
            _ = try ProxyConfigHelperXPCCodec.decodeMessage(ProxyConfigHelperMessages.StartMeta.self,
                from: ProxyConfigHelperRequestEnvelope(kind: "startMeta", payload: oldPayload))
        }
        try rejects("Reject V2 requests missing required fields") {
            _ = try ProxyConfigHelperXPCCodec.decodeMessage(ProxyConfigHelperMessages.StartMeta.self,
                from: ProxyConfigHelperRequestEnvelope(kind: "startMetaV2", payload: oldPayload))
        }
        print("Passed \(checks) file-boundary and protocol checks.")
    }
}
