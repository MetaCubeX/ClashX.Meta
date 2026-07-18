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

    static let machServiceName = "com.metacubex.ClashX.ProxyConfigHelper"
    static let shared = PrivilegedHelperManager()

    enum HelperStatus {
        case installed
        case noFound
        case needUpdate
    }

	// MARK: Public API

    func request<Message: ProxyConfigHelperXPCMessage>(_ message: Message) async throws -> Message.Response {
        try await performAsyncRequest(message)
    }

    func request<Message>(_ message: Message) async throws where Message: ProxyConfigHelperXPCMessage, Message.Response == ProxyConfigHelperExplicitSuccess {
        _ = try await performAsyncRequest(message) as ProxyConfigHelperExplicitSuccess
    }

    @MainActor
    func checkInstall() async {
        Logger.log("checkInstall", level: .debug)
        let status = await getHelperStatus()
        Logger.log("check result: \(status)", level: .debug)

        switch status {
        case .noFound:
            await resolveRequiresApprovalIfNeeded()
            fallthrough
        case .needUpdate:
            Logger.log("need to install helper", level: .debug)
            await notifyInstall()
        case .installed:
            isHelperCheckFinishedRelay.accept(true)
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
        connection.interruptionHandler = { [weak self] in
            Logger.log("XPC Connection Interrupted")
            self?.resetHelper(invalidate: false)
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

    private func performAsyncRequest<Message: ProxyConfigHelperXPCMessage>(_ message: Message) async throws -> Message.Response {
        let helper = try helperProxy()

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

            timeoutTask = Task { [requestTimeout] in
                do {
                    try await Task.sleep(seconds: requestTimeout)
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
            let helperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String else {
            Logger.log("check helper status fail")
            return .noFound
        }
        
        let helperInstalledURL = helperInstalledURL()
        
        if FileManager.default.fileExists(atPath: helperInstalledURL.path) {
            if let info = CFBundleCopyInfoDictionaryForURL(helperInstalledURL as CFURL) as? [String: Any],
               let version = info["CFBundleShortVersionString"] as? String,
               version == helperVersion {
                Logger.log("helper version CFBundleShortVersionString \(version)", level: .debug)
            } else {
                return .needUpdate
            }
            // Same CFBundleShortVersionString can still ship different binaries (rebuilds,
            // arch slice changes, local Debug vs release). Version-only checks skip install
            // in those cases; compare on-disk content so SMJobBless/legacy install re-runs.
            if helperBinaryDiffersFromBundle(installed: helperInstalledURL, bundled: helperURL) {
                Logger.log("helper binary differs from app bundle, need update", level: .info)
                return .needUpdate
            }
        } else {
            return .noFound
        }
        
        let timeout: TimeInterval = 15
        let time = Date()
        return await withTaskGroup(of: HelperStatus.self, returning: HelperStatus.self) { group in
            group.addTask {
                try? await Task.sleep(seconds: timeout)
                Logger.log("check helper timeout time: \(timeout)")
                return .noFound
            }

            group.addTask {
                do {
                    let installedHelperVersion: String = try await self.request(ProxyConfigHelperMessages.GetVersion())
                    Logger.log("helper version \(installedHelperVersion) require version \(helperVersion)", level: .debug)
                    let versionMatch = installedHelperVersion == helperVersion
                    let interval = Date().timeIntervalSince(time)
                    Logger.log("check helper using time: \(interval)")
                    return versionMatch ? .installed : .needUpdate
                } catch {
                    return .noFound
                }
            }

            let status = await group.next() ?? .noFound
            group.cancelAll()
            return status
        }
    }

    /// Returns true when installed helper bytes differ from the one embedded in the app,
    /// or either file cannot be read (treat as needing reinstall).
    private func helperBinaryDiffersFromBundle(installed: URL, bundled: URL) -> Bool {
        guard let bundledData = try? Data(contentsOf: bundled),
              let installedData = try? Data(contentsOf: installed) else {
            return true
        }
        return bundledData != installedData
    }

    @MainActor
    private func resolveRequiresApprovalIfNeeded() async {
        guard #available(macOS 13, *) else { return }

        let status = SMAppService.statusForLegacyPlist(at: launchDaemonPlistURL())
        guard status == .requiresApproval else { return }

        let alert = NSAlert()
        let notice = NSLocalizedString("ClashX use a daemon helper to setup your system proxy. Please enable ClashX in the Login Items under the Allow in the Background section and relaunch the app", comment: "")
        let addition = NSLocalizedString("If you can not find ClashX in the settings, you can try reset daemon", comment: "")
        alert.messageText = notice + "\n" + addition
        alert.addButton(withTitle: NSLocalizedString("Open System Login Item Setting", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Reset Daemon", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            await removeInstallHelper()
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
            await legacyInstallHelper()
            if !cancelInstallCheck {
                await checkInstall()
            }
            return
        }

        let result = installHelperDaemon()
        if case .success = result {
            return
        }
        result.alertAction()
        NSAlert.alert(with: result.alertContent)
        if !cancelInstallCheck {
            await checkInstall()
        }
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
            isHelperCheckFinishedRelay.accept(true)
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
