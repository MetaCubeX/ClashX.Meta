import CoreFoundation
import Foundation

// The runner supplies the production manager and codec. These substitutes never
// open an XPC connection, display UI, read installed helpers, or request elevation.
protocol ProxyConfigRemoteProcessProtocol: AnyObject {
    func sendRequest(_ request: Data, reply: @escaping (Data?, NSString?) -> Void)
}

final class BehaviorRelay<Value> {
    private(set) var value: Value
    init(value: Value) { self.value = value }
    func accept(_ value: Value) { self.value = value }
}

enum Logger {
    enum Level { case debug, info, error }
    static func log(_ message: String, level: Level = .info) {}
}

final class NSXPCInterface {
    init(with value: Any) {}
}

final class NSXPCConnection {
    struct Options: OptionSet {
        let rawValue: Int
        static let privileged = Options(rawValue: 1)
    }
    var remoteObjectInterface: NSXPCInterface?
    var invalidationHandler: (() -> Void)?
    var interruptionHandler: (() -> Void)?
    private(set) var invalidated = false
    let remote: OfflineRemote

    init(machServiceName: String, options: Options) {
        precondition(machServiceName == PrivilegedHelperManager.machServiceName)
        precondition(options == .privileged)
        remote = OfflineEnvironment.nextRemote
        remote.connection = self
        OfflineEnvironment.connections.append(self)
    }

    func resume() {}
    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        invalidationHandler?()
    }
    func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any { remote }
}

final class NSAlert {
    enum Style { case warning }
    enum Response { case alertFirstButtonReturn, alertSecondButtonReturn, alertThirdButtonReturn }
    var messageText = ""
    var alertStyle = Style.warning
    static var responses: [Response] = []
    static var shownErrors: [String] = []
    static var modalCount = 0
    func addButton(withTitle title: String) {}
    func runModal() -> Response {
        Self.modalCount += 1
        precondition(!Self.responses.isEmpty, "Unexpected installation dialog")
        return Self.responses.removeFirst()
    }
    static func alert(with message: String) { shownErrors.append(message) }
}

enum SMAppService {
    enum Status { case requiresApproval, enabled }
    static var status = Status.enabled
    static func statusForLegacyPlist(at url: URL) -> Status { status }
    static func openSystemSettingsLoginItems() {}
}

private enum DaemonInstallResult {
    case success, authorizationFail
    var alertContent: String { "Offline installer unavailable" }
    func alertAction() { preconditionFailure("The real installer must never be reached") }
}

enum OfflineEnvironment {
    static let supportedInfo: [String: Any] = [
        "CFBundleShortVersionString": "1.25", "CFBundleVersion": "33"
    ]
    static var bundledInfo = supportedInfo
    static var installedInfo: [String: Any]? = supportedInfo
    static var nextRemote = OfflineRemote()
    static var connections: [NSXPCConnection] = []
    static var installationError: Error?
    static var installationCount = 0

    static func reset(remote: OfflineRemote = OfflineRemote()) {
        bundledInfo = supportedInfo
        installedInfo = supportedInfo
        nextRemote = remote
        connections = []
        installationError = nil
        installationCount = 0
        NSAlert.responses = []
        NSAlert.shownErrors = []
        NSAlert.modalCount = 0
        SMAppService.status = .enabled
        OfflineClock.reset()
    }

    static func fileExists(atPath path: String) -> Bool { installedInfo != nil }
    static func bundleInfo(_ url: CFURL) -> CFDictionary? {
        let path = (url as URL).path
        let info = path.hasPrefix("/Library/PrivilegedHelperTools/") ? installedInfo : bundledInfo
        return info.map { $0 as CFDictionary }
    }
}

enum OfflineClock {
    private static let lock = NSLock()
    private static var values: [Double] = []
    static func record(_ seconds: Double) {
        lock.lock()
        values.append(seconds)
        lock.unlock()
    }
    static func reset() {
        lock.lock()
        values = []
        lock.unlock()
    }
    static func contains(_ seconds: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values.contains(seconds)
    }
}

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        OfflineClock.record(seconds)
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}

final class OfflineRemote: ProxyConfigRemoteProcessProtocol {
    enum Behavior { case normal, missingCapabilities, malformedResponse, noReply, lateReply }
    static let required = ["trusted-core-sha256", "private-run-config", "managed-core-logs"]
    private static let callbackQueue = DispatchQueue(label: "helper-compatibility-callbacks")
    var version = "1.25"
    var capabilityVersion = "1.25"
    var build = "33"
    var protocolVersion = 2
    var capabilities = required
    var behavior = Behavior.normal
    var afterCapabilities: (() -> Void)?
    weak var connection: NSXPCConnection?
    private(set) var received: [String] = []
    private(set) var executed: [String] = []

    func sendRequest(_ request: Data, reply: @escaping (Data?, NSString?) -> Void) {
        let envelope: ProxyConfigHelperRequestEnvelope
        do { envelope = try ProxyConfigHelperXPCCodec.decodeRequestEnvelope(from: request) }
        catch { preconditionFailure("Manager sent an invalid request") }
        received.append(envelope.kind)
        let query = envelope.kind == ProxyConfigHelperMessages.GetVersion.kind
            || envelope.kind == ProxyConfigHelperMessages.GetCapabilities.kind
        if !query, behavior == .noReply { return }
        let delay = !query && behavior == .lateReply ? 0.2 : 0.001
        Self.callbackQueue.asyncAfter(deadline: .now() + delay) {
            if self.connection?.invalidated == true {
                reply(nil, "The fixture connection was invalidated.")
                return
            }
            do {
                switch envelope.kind {
                case ProxyConfigHelperMessages.GetVersion.kind:
                    reply(try ProxyConfigHelperXPCCodec.encodeResponse(self.version,
                        for: ProxyConfigHelperMessages.GetVersion.self), nil)
                case ProxyConfigHelperMessages.GetCapabilities.kind:
                    if self.behavior == .missingCapabilities {
                        reply(nil, "Unexpected message: getCapabilities")
                    } else {
                        let response = ProxyConfigHelperCapabilities(protocolVersion: self.protocolVersion,
                            helperVersion: self.capabilityVersion, helperBuild: self.build,
                            capabilities: self.capabilities)
                        self.afterCapabilities?()
                        reply(try ProxyConfigHelperXPCCodec.encodeResponse(response,
                            for: ProxyConfigHelperMessages.GetCapabilities.self), nil)
                    }
                case ProxyConfigHelperMessages.StopMeta.kind:
                    if self.behavior == .malformedResponse {
                        reply(Data("invalid JSON".utf8), nil)
                    } else {
                        self.executed.append(envelope.kind)
                        reply(try ProxyConfigHelperXPCCodec.encodeResponse(ProxyConfigHelperExplicitSuccess(),
                            for: ProxyConfigHelperMessages.StopMeta.self), nil)
                    }
                case ProxyConfigHelperMessages.StartMeta.kind:
                    reply(try ProxyConfigHelperXPCCodec.encodeResponse(nil as String?,
                        for: ProxyConfigHelperMessages.StartMeta.self), nil)
                case ProxyConfigHelperMessages.UpdateAlphaCore.kind:
                    reply(try ProxyConfigHelperXPCCodec.encodeResponse(
                        ProxyConfigHelperAlphaInfo(version: "fixture", path: "/fixture"),
                        for: ProxyConfigHelperMessages.UpdateAlphaCore.self), nil)
                default:
                    preconditionFailure("Unexpected fixture request: \(envelope.kind)")
                }
            } catch {
                preconditionFailure("Could not encode a fixture response: \(error)")
            }
        }
    }
}

private struct CompatibilityTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CompatibilityTestFailure(description: message) }
}

extension PrivilegedHelperManager {
    enum HelperInstallationError: Error { case cancelled, scriptFailed(String) }

    @MainActor
    func legacyInstallHelper() async throws {
        OfflineEnvironment.installationCount += 1
        if let error = OfflineEnvironment.installationError { throw error }
        OfflineEnvironment.installedInfo = OfflineEnvironment.supportedInfo
    }

    @MainActor
    func removeInstallHelper() async throws {
        preconditionFailure("Uninstallation is outside this offline test")
    }

    @MainActor
    private static func reject(_ remote: OfflineRemote, _ label: String) async throws {
        OfflineEnvironment.reset(remote: remote)
        let manager = PrivilegedHelperManager()
        do {
            try await manager.request(ProxyConfigHelperMessages.StopMeta())
            throw CompatibilityTestFailure(description: "\(label): operation was allowed")
        } catch AsyncHelperError.updateRequired {}
        try require(remote.executed.isEmpty, "\(label): helper operation executed")
        try require(!remote.received.contains(ProxyConfigHelperMessages.StopMeta.kind),
                    "\(label): operation was sent before successful validation")
    }

    @MainActor
    static func runCompatibilityTests() async throws {
        for version in ["", "1.24", "unknown", "1..25", "-1", "1.25beta"] {
            let remote = OfflineRemote()
            remote.version = version
            try await reject(remote, "unsupported version \(version)")
        }
        for build in ["", "32", "unknown", "-1"] {
            let remote = OfflineRemote()
            remote.build = build
            try await reject(remote, "unsupported build \(build)")
        }
        for version in [1, 3] {
            let remote = OfflineRemote()
            remote.protocolVersion = version
            try await reject(remote, "unsupported protocol \(version)")
        }
        let missing = OfflineRemote()
        missing.behavior = .missingCapabilities
        try await reject(missing, "legacy helper without capabilities")
        let incomplete = OfflineRemote()
        incomplete.capabilities.removeLast()
        try await reject(incomplete, "missing required capability")
        let mismatched = OfflineRemote()
        mismatched.capabilityVersion = "1.26"
        try await reject(mismatched, "inconsistent capability version")
        print("PASS: unsupported versions, builds, capabilities, and protocols fail closed")

        for version in ["1.25", "1.26"] {
            let remote = OfflineRemote()
            remote.version = version
            remote.capabilityVersion = version
            remote.build = version == "1.25" ? "33" : "34"
            OfflineEnvironment.reset(remote: remote)
            let manager = PrivilegedHelperManager()
            try await manager.request(ProxyConfigHelperMessages.StopMeta())
            try require(remote.received == ["getVersion", "getCapabilities", "stopMeta"],
                        "Supported helper did not receive the ordered handshake")
        }
        print("PASS: current and newer compatible helpers complete the handshake before mutation")

        let original = OfflineRemote()
        let replacement = OfflineRemote()
        OfflineEnvironment.reset(remote: original)
        let pinned = PrivilegedHelperManager()
        original.afterCapabilities = { pinned._helper = replacement }
        try await pinned.request(ProxyConfigHelperMessages.StopMeta())
        try require(original.executed == ["stopMeta"] && replacement.received.isEmpty,
                    "An operation moved to a proxy that was not validated")

        let interrupted = OfflineRemote()
        OfflineEnvironment.reset(remote: interrupted)
        let reconnecting = PrivilegedHelperManager()
        interrupted.afterCapabilities = {
            OfflineEnvironment.nextRemote = OfflineRemote()
            interrupted.connection?.interruptionHandler?()
        }
        do {
            try await reconnecting.request(ProxyConfigHelperMessages.StopMeta())
            throw CompatibilityTestFailure(description: "Disconnected helper accepted an operation")
        } catch AsyncHelperError.remote {}
        try require(interrupted.executed.isEmpty, "Disconnected helper executed an operation")
        try require(OfflineEnvironment.connections.count == 1,
                    "The request silently reconnected after validation")
        try await reconnecting.request(ProxyConfigHelperMessages.StopMeta())
        try require(OfflineEnvironment.nextRemote.received == ["getVersion", "getCapabilities", "stopMeta"],
                    "The next connection did not repeat the complete handshake")
        print("PASS: checked proxies remain pinned and reconnections repeat validation")

        let malformed = OfflineRemote()
        malformed.behavior = .malformedResponse
        OfflineEnvironment.reset(remote: malformed)
        do {
            try await PrivilegedHelperManager().request(ProxyConfigHelperMessages.StopMeta())
            throw CompatibilityTestFailure(description: "Malformed response was accepted")
        } catch AsyncHelperError.codec {}

        for kind in ["stopMeta", "startMetaV2", "updateAlphaCore"] {
            let stalled = OfflineRemote()
            stalled.behavior = .noReply
            OfflineEnvironment.reset(remote: stalled)
            let manager = PrivilegedHelperManager()
            do {
                switch kind {
                case "stopMeta":
                    try await manager.request(ProxyConfigHelperMessages.StopMeta())
                case "startMetaV2":
                    let _: String? = try await manager.request(ProxyConfigHelperMessages.StartMeta(
                        path: "/fixture", core: .bundled, confPath: "/fixture",
                        configData: Data("fixture".utf8), confJSON: "{}"))
                default:
                    let _: ProxyConfigHelperAlphaInfo = try await manager.request(ProxyConfigHelperMessages.UpdateAlphaCore())
                }
                throw CompatibilityTestFailure(description: "\(kind): timeout was accepted")
            } catch AsyncHelperError.timedOut {}
            let expected = kind == "stopMeta" ? 15.0 : (kind == "startMetaV2" ? 45.0 : 240.0)
            try require(OfflineClock.contains(expected), "\(kind): incorrect timeout policy")
            try require(manager._helper == nil && manager.connection == nil,
                        "\(kind): timed-out connection remained cached")
        }
        let late = OfflineRemote()
        late.behavior = .lateReply
        OfflineEnvironment.reset(remote: late)
        let timedOut = PrivilegedHelperManager()
        do {
            try await timedOut.request(ProxyConfigHelperMessages.StopMeta())
            throw CompatibilityTestFailure(description: "Late response beat the timeout")
        } catch AsyncHelperError.timedOut {}
        try await Task.sleep(nanoseconds: 250_000_000)
        try require(timedOut._helper == nil, "Late response revived a timed-out connection")
        print("PASS: malformed responses, per-operation timeouts, and late replies fail safely")

        OfflineEnvironment.reset()
        OfflineEnvironment.installedInfo = ["CFBundleShortVersionString": "1.24", "CFBundleVersion": "32"]
        let old = PrivilegedHelperManager()
        try require(await old.getHelperStatus() == .needUpdate, "Old installed helper did not require upgrade")
        try require(OfflineEnvironment.connections.isEmpty, "An obsolete disk helper was contacted")

        OfflineEnvironment.reset()
        OfflineEnvironment.installedInfo = nil
        let absent = PrivilegedHelperManager()
        try require(await absent.getHelperStatus() == .noFound, "Missing installed helper was accepted")

        OfflineEnvironment.reset()
        OfflineEnvironment.bundledInfo = ["CFBundleShortVersionString": "1.24", "CFBundleVersion": "32"]
        let obsoleteApp = PrivilegedHelperManager()
        try require(await obsoleteApp.getHelperStatus() == .incompatible, "Obsolete bundled helper was accepted")

        let future = OfflineRemote()
        future.version = "1.26"
        future.capabilityVersion = "1.26"
        future.build = "34"
        future.protocolVersion = 3
        OfflineEnvironment.reset(remote: future)
        OfflineEnvironment.installedInfo = ["CFBundleShortVersionString": "1.26", "CFBundleVersion": "34"]
        let newer = PrivilegedHelperManager()
        try require(await newer.getHelperStatus() == .incompatible,
                    "A newer incompatible helper would be overwritten by a downgrade")
        print("PASS: disk and running helper states reject obsolete installs and unsafe downgrades")

        OfflineEnvironment.reset()
        OfflineEnvironment.installedInfo = nil
        NSAlert.responses = [.alertThirdButtonReturn]
        let cancelledDialog = PrivilegedHelperManager()
        await cancelledDialog.checkInstall()
        try require(!cancelledDialog.isHelperCheckFinishedRelay.value,
                    "Cancelling the installation dialog marked the helper ready")
        try require(OfflineEnvironment.installationCount == 0, "Cancel still invoked installation")

        OfflineEnvironment.reset()
        OfflineEnvironment.installedInfo = nil
        OfflineEnvironment.installationError = HelperInstallationError.cancelled
        NSAlert.responses = [.alertFirstButtonReturn]
        let cancelledAuthorization = PrivilegedHelperManager()
        await cancelledAuthorization.checkInstall()
        try require(!cancelledAuthorization.isHelperCheckFinishedRelay.value,
                    "Cancelling administrator authorization marked the helper ready")
        try require(OfflineEnvironment.installationCount == 1 && NSAlert.modalCount == 1,
                    "Cancelled authorization retried installation")
        try require(NSAlert.shownErrors.isEmpty, "Cancellation displayed an error alert")

        OfflineEnvironment.reset()
        OfflineEnvironment.installedInfo = nil
        OfflineEnvironment.installationError = HelperInstallationError.scriptFailed("fixture failure")
        NSAlert.responses = [.alertFirstButtonReturn]
        let failed = PrivilegedHelperManager()
        await failed.checkInstall()
        try require(!failed.isHelperCheckFinishedRelay.value && NSAlert.shownErrors.count == 1,
                    "Installation failure was hidden")
        try require(OfflineEnvironment.installationCount == 1 && NSAlert.modalCount == 1,
                    "Failed installation entered a retry loop")

        OfflineEnvironment.reset()
        OfflineEnvironment.installedInfo = nil
        NSAlert.responses = [.alertFirstButtonReturn]
        let installed = PrivilegedHelperManager()
        await installed.checkInstall()
        try require(installed.isHelperCheckFinishedRelay.value, "Verified installation did not become ready")
        try require(OfflineEnvironment.nextRemote.received == ["getVersion", "getCapabilities"],
                    "Installation became ready without checking the running helper")
        print("PASS: cancellation, installation failure, and successful installation readiness")
    }
}

@main
enum HelperCompatibilityTests {
    static func main() async {
        do {
            try await PrivilegedHelperManager.runCompatibilityTests()
            print("All offline helper compatibility tests passed.")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }
}
