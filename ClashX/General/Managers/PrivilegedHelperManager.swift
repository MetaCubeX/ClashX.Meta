//
//  PrivilegedHelperManager.swift
//  ClashX
//
//  Created by yicheng on 2020/4/21.
//  Copyright © 2020 west2online. All rights reserved.
//

import AppKit
import RxCocoa
import RxSwift
import ServiceManagement

final class PrivilegedHelperManager {
	// MARK: Types

    enum AsyncHelperError: LocalizedError {
        case unavailable
        case remote(String)
        case codec(Error)
        case timedOut
        case updateRequired

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The privileged helper is unavailable."
            case let .remote(message):
                return message
            case let .codec(error):
                return error.localizedDescription
            case .timedOut:
                return "The privileged helper request timed out."
            case .updateRequired:
                return "The privileged helper must be updated before privileged operations can continue."
            }
        }
    }

    private final class ContinuationCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var didComplete = false

        func tryComplete() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return false }
            didComplete = true
            return true
        }
    }

    let isHelperCheckFinishedRelay = BehaviorRelay<Bool>(value: false)

    private var cancelInstallCheck = false
    private let useLegacyInstall = true
    private var connection: NSXPCConnection?
    private var _helper: ProxyConfigRemoteProcessProtocol?
    private let requestTimeout: TimeInterval = 15
    private static let minimumHelperVersion = "1.25"
    private static let minimumHelperBuild = 33
    private static let requiredProtocolVersion = 2
    private static let requiredCapabilities: Set<String> = [
        "trusted-core-sha256", "private-run-config", "managed-core-logs"
    ]

    static let machServiceName = "com.metacubex.ClashX.ProxyConfigHelper"
    static let shared = PrivilegedHelperManager()

    enum HelperStatus {
        case installed
        case noFound
        case needUpdate
        case incompatible
    }

	// MARK: Public API

    func request<Message: ProxyConfigHelperXPCMessage>(_ message: Message) async throws -> Message.Response {
        try await performValidatedRequest(message)
    }

    func request<Message>(_ message: Message) async throws where Message: ProxyConfigHelperXPCMessage, Message.Response == ProxyConfigHelperExplicitSuccess {
        _ = try await performValidatedRequest(message) as ProxyConfigHelperExplicitSuccess
    }

    @MainActor
    func checkInstall() async {
        Logger.log("checkInstall", level: .debug)
        isHelperCheckFinishedRelay.accept(false)
        cancelInstallCheck = false
        let status = await getHelperStatus()
        Logger.log("check result: \(status)", level: .debug)

        switch status {
        case .noFound:
            guard await resolveRequiresApprovalIfNeeded() else { return }
            fallthrough
        case .needUpdate:
            Logger.log("need to install helper", level: .debug)
            await notifyInstall()
        case .installed:
            isHelperCheckFinishedRelay.accept(true)
        case .incompatible:
            NSAlert.alert(with: "This app cannot use the bundled or installed privileged helper. Update the app before continuing.")
        }
    }

	// MARK: Connection

    private func installHelperDaemon() -> DaemonInstallResult {
        Logger.log("installHelperDaemon", level: .info)

        defer {
            resetHelper(invalidate: true)
        }

        var authRef: AuthorizationRef?
        var authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        guard authStatus == errAuthorizationSuccess else {
            Logger.log("Authorization failed: \(authStatus)", level: .error)
            return .authorizationFail
        }

        var authItem = AuthorizationItem(name: (kSMRightBlessPrivilegedHelper as NSString).utf8String!, valueLength: 0, value: nil, flags: 0)
        var authRights = withUnsafeMutablePointer(to: &authItem) { pointer in
            AuthorizationRights(count: 1, items: pointer)
        }
        let flags: AuthorizationFlags = [[], .interactionAllowed, .extendRights, .preAuthorize]
        authStatus = AuthorizationCreate(&authRights, nil, flags, &authRef)
        defer {
            if let ref = authRef {
                AuthorizationFree(ref, [])
            }
        }

        guard authStatus == errAuthorizationSuccess else {
            Logger.log("Couldn't obtain admin privileges: \(authStatus)", level: .error)
            return .getAdminFail
        }

        var error: Unmanaged<CFError>?
        if SMJobBless(kSMDomainSystemLaunchd, PrivilegedHelperManager.machServiceName as CFString, authRef, &error) == false {
            let blessError = error!.takeRetainedValue() as Error
            Logger.log("Bless Error: \(blessError)", level: .error)
            return .blessError((blessError as NSError).code)
        }

        Logger.log("\(PrivilegedHelperManager.machServiceName) installed successfully", level: .info)
        return .success
    }

    private func configuredConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: PrivilegedHelperManager.machServiceName,
                                         options: NSXPCConnection.Options.privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ProxyConfigRemoteProcessProtocol.self)
        return connection
    }

    func resetHelper(invalidate: Bool) {
        if invalidate {
            connection?.invalidationHandler = nil
            connection?.interruptionHandler = nil
            connection?.invalidate()
        }

        connection = nil
        _helper = nil
    }

    private func helperProxy() throws -> ProxyConfigRemoteProcessProtocol {
        if let helper = _helper {
            return helper
        }

        let connection = configuredConnection()
        connection.invalidationHandler = { [weak self] in
            Logger.log("XPC Connection Invalidated")
            self?.resetHelper(invalidate: false)
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            Logger.log("XPC Connection Interrupted")
            // A checked proxy must not reconnect to a different helper instance.
            connection?.invalidate()
            if self?.connection === connection {
                self?.resetHelper(invalidate: false)
            }
        }
        connection.resume()

        guard let helper = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            Logger.log("Helper connection was closed with error: \(error)")
            self?.resetHelper(invalidate: true)
        }) as? ProxyConfigRemoteProcessProtocol else {
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            connection.invalidate()
            throw AsyncHelperError.unavailable
        }

        self.connection = connection
        self._helper = helper
        return helper
    }

    private func performValidatedRequest<Message: ProxyConfigHelperXPCMessage>(_ message: Message) async throws -> Message.Response {
        let helper = try helperProxy()
        if Message.kind != ProxyConfigHelperMessages.GetVersion.kind,
           Message.kind != ProxyConfigHelperMessages.GetCapabilities.kind {
            _ = try await validateRunningHelper(helper)
        }
        return try await performAsyncRequest(message, using: helper)
    }

    private func validateRunningHelper(_ helper: ProxyConfigRemoteProcessProtocol) async throws -> ProxyConfigHelperCapabilities {
        let version = try await performAsyncRequest(ProxyConfigHelperMessages.GetVersion(), using: helper)
        guard Self.isSupportedVersion(version) else {
            throw AsyncHelperError.updateRequired
        }

        let capabilities: ProxyConfigHelperCapabilities
        do {
            capabilities = try await performAsyncRequest(ProxyConfigHelperMessages.GetCapabilities(), using: helper)
        } catch {
            throw AsyncHelperError.updateRequired
        }
        guard capabilities.helperVersion == version,
              Self.isSupportedRelease(version: capabilities.helperVersion, build: capabilities.helperBuild),
              capabilities.protocolVersion == Self.requiredProtocolVersion,
              Self.requiredCapabilities.isSubset(of: Set(capabilities.capabilities)) else {
            throw AsyncHelperError.updateRequired
        }
        return capabilities
    }

    private static func isSupportedVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else {
            return false
        }
        return version.compare(minimumHelperVersion, options: .numeric) != .orderedAscending
    }

    private static func isSupportedRelease(version: String, build: String) -> Bool {
        guard let buildNumber = Int(build), buildNumber >= minimumHelperBuild else { return false }
        return isSupportedVersion(version)
    }

    private func performAsyncRequest<Message: ProxyConfigHelperXPCMessage>(_ message: Message,
                                                                         using helper: ProxyConfigRemoteProcessProtocol) async throws -> Message.Response {
        let timeout: TimeInterval
        switch Message.kind {
        case ProxyConfigHelperMessages.UpdateAlphaCore.kind: timeout = 240
        case ProxyConfigHelperMessages.StartMeta.kind,
             ProxyConfigHelperMessages.StopMeta.kind,
             ProxyConfigHelperMessages.TerminateExistingMeta.kind: timeout = 45
        default: timeout = requestTimeout
        }

        let requestData: Data
        do {
            requestData = try ProxyConfigHelperXPCCodec.encodeRequest(message)
        } catch {
            throw AsyncHelperError.codec(error)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let completion = ContinuationCompletion()
            var timeoutTask: Task<Void, Never>?

            let finish: (Result<Message.Response, Error>) -> Void = { result in
                guard completion.tryComplete() else { return }
                timeoutTask?.cancel()
                switch result {
                case let .success(response):
                    continuation.resume(returning: response)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            helper.sendRequest(requestData) { responseData, errorMessage in
                if let errorMessage {
                    self.resetHelper(invalidate: true)
                    finish(.failure(AsyncHelperError.remote(errorMessage as String)))
                    return
                }

                guard let responseData else {
                    self.resetHelper(invalidate: true)
                    finish(.failure(AsyncHelperError.unavailable))
                    return
                }

                do {
                    let response = try ProxyConfigHelperXPCCodec.decodeResponse(responseData, as: Message.self)
                    finish(.success(response))
                } catch {
                    finish(.failure(AsyncHelperError.codec(error)))
                }
            }

            timeoutTask = Task {
                do {
                    try await Task.sleep(seconds: timeout)
                } catch {
                    return
                }

                self.resetHelper(invalidate: true)
                finish(.failure(AsyncHelperError.timedOut))
            }
        }
    }

	// MARK: Install Status

    @MainActor
    private func getHelperStatus() async -> HelperStatus {
        let helperURL = helperBundleURL()
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let helperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String,
            let helperBuild = helperBundleInfo["CFBundleVersion"] as? String,
            Self.isSupportedRelease(version: helperVersion, build: helperBuild) else {
            Logger.log("check helper status fail")
            return .incompatible
        }
        
        let helperInstalledURL = helperInstalledURL()
        var installedIsNewer = false
        
        if FileManager.default.fileExists(atPath: helperInstalledURL.path) {
            guard let info = CFBundleCopyInfoDictionaryForURL(helperInstalledURL as CFURL) as? [String: Any],
                  let version = info["CFBundleShortVersionString"] as? String,
                  let build = info["CFBundleVersion"] as? String else {
                return .needUpdate
            }
            installedIsNewer = version.compare(helperVersion, options: .numeric) == .orderedDescending
                || build.compare(helperBuild, options: .numeric) == .orderedDescending
            guard Self.isSupportedRelease(version: version, build: build),
                  version.compare(helperVersion, options: .numeric) != .orderedAscending,
                  build.compare(helperBuild, options: .numeric) != .orderedAscending else {
                return installedIsNewer ? .incompatible : .needUpdate
            }
            Logger.log("installed helper version \(version) build \(build)", level: .debug)
        } else {
            return .noFound
        }
        
        resetHelper(invalidate: true)
        do {
            let capabilities = try await validateRunningHelper(try helperProxy())
            guard capabilities.helperVersion.compare(helperVersion, options: .numeric) != .orderedAscending,
                  capabilities.helperBuild.compare(helperBuild, options: .numeric) != .orderedAscending else {
                return installedIsNewer ? .incompatible : .needUpdate
            }
            Logger.log("running helper version \(capabilities.helperVersion) build \(capabilities.helperBuild), protocol \(capabilities.protocolVersion)", level: .debug)
            return .installed
        } catch AsyncHelperError.updateRequired {
            return installedIsNewer ? .incompatible : .needUpdate
        } catch {
            return installedIsNewer ? .incompatible : .noFound
        }
    }

    @MainActor
    private func resolveRequiresApprovalIfNeeded() async -> Bool {
        guard #available(macOS 13, *) else { return true }

        let status = SMAppService.statusForLegacyPlist(at: launchDaemonPlistURL())
        guard status == .requiresApproval else { return true }

        let alert = NSAlert()
        let notice = NSLocalizedString("ClashX use a daemon helper to setup your system proxy. Please enable ClashX in the Login Items under the Allow in the Background section and relaunch the app", comment: "")
        let addition = NSLocalizedString("If you can not find ClashX in the settings, you can try reset daemon", comment: "")
        alert.messageText = notice + "\n" + addition
        alert.addButton(withTitle: NSLocalizedString("Open System Login Item Setting", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Reset Daemon", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
            return false
        } else {
            do {
                try await removeInstallHelper()
                return true
            } catch {
                showInstallationError(error)
                return false
            }
        }
    }

    private func helperBundleURL() -> URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + PrivilegedHelperManager.machServiceName)
    }
    
    private func helperInstalledURL() -> URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)")
    }

    private func launchDaemonPlistURL() -> URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist")
    }
}

extension PrivilegedHelperManager {
	// MARK: Install Flow

    @MainActor
    private func notifyInstall() async {
        guard showInstallHelperAlert() else { exit(0) }

        if cancelInstallCheck {
            return
        }

        if useLegacyInstall {
            do {
                try await legacyInstallHelper()
                await finishInstallation()
            } catch {
                showInstallationError(error)
            }
            return
        }

        let result = installHelperDaemon()
        if case .success = result {
            await finishInstallation()
            return
        }
        result.alertAction()
        NSAlert.alert(with: result.alertContent)
    }

    @MainActor
    private func finishInstallation() async {
        resetHelper(invalidate: true)
        if case .installed = await getHelperStatus() {
            isHelperCheckFinishedRelay.accept(true)
        } else {
            isHelperCheckFinishedRelay.accept(false)
            resetHelper(invalidate: true)
            NSAlert.alert(with: AsyncHelperError.updateRequired.localizedDescription)
        }
    }

    @MainActor
    private func showInstallationError(_ error: Error) {
        isHelperCheckFinishedRelay.accept(false)
        resetHelper(invalidate: true)
        if case HelperInstallationError.cancelled = error { return }
        NSAlert.alert(with: error.localizedDescription)
    }

    private func showInstallHelperAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("ClashX needs to install/update a helper tool with administrator privileges, otherwise ClashX won't be able to configure system proxy.", comment: "")
        alert.alertStyle = .warning
        if useLegacyInstall {
            alert.addButton(withTitle: NSLocalizedString("Legacy Install", comment: ""))
        } else {
            alert.addButton(withTitle: NSLocalizedString("Install", comment: ""))
        }
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertThirdButtonReturn:
            cancelInstallCheck = true
            isHelperCheckFinishedRelay.accept(false)
            resetHelper(invalidate: true)
            Logger.log("cancelInstallCheck = true", level: .error)
            return true
        default:
            return false
        }
    }
}

private enum DaemonInstallResult {
    case success
    case authorizationFail
    case getAdminFail
    case blessError(Int)

    var alertContent: String {
        switch self {
        case .success:
            return ""
        case .authorizationFail:
            return "Failed to create authorization!"
        case .getAdminFail:
            return "Failed to get admin authorization!"
        case let .blessError(code):
            switch code {
            case kSMErrorInternalFailure:
                return "blessError: kSMErrorInternalFailure"
            case kSMErrorInvalidSignature:
                return "blessError: kSMErrorInvalidSignature"
            case kSMErrorAuthorizationFailure:
                return "blessError: kSMErrorAuthorizationFailure"
            case kSMErrorToolNotValid:
                return "blessError: kSMErrorToolNotValid"
            case kSMErrorJobNotFound:
                return "blessError: kSMErrorJobNotFound"
            case kSMErrorServiceUnavailable:
                return "blessError: kSMErrorServiceUnavailable"
            case kSMErrorJobMustBeEnabled:
                return "ClashX Helper is disabled by other process. Please run \"sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)\" in your terminal. The command has been copied to your pasteboard"
            case kSMErrorInvalidPlist:
                return "blessError: kSMErrorInvalidPlist"
            default:
                return "bless unknown error:\(code)"
            }
        }
    }

    func alertAction() {
        switch self {
        case let .blessError(code):
            switch code {
            case kSMErrorJobMustBeEnabled:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)", forType: .string)
            default:
                break
            }
        default:
            break
        }
    }
}
