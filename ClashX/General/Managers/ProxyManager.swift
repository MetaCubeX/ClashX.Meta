//
//  ProxyManager.swift
//  ClashX
//
//

import Combine
import Foundation
import RxCocoa
import RxSwift

/// Owns user intent, runtime state, and SSID suspend for both the macOS system proxy
/// and the Clash TUN mode. All write paths run through here.
@MainActor
final class ProxyManager: NSObject {
    static let shared = ProxyManager()

    // MARK: - Nested Types

    struct StateSnapshot: Equatable {
        let intent: UserIntent
        let runtime: RuntimeState
        let suspend: SuspendState
    }

    struct UserIntent: Equatable {
        var systemProxyEnabled: Bool
        var tunEnabled: Bool
        var tunOverridden: Bool
    }

    struct RuntimeState: Equatable {
        var systemProxyActive: Bool
        var tunActive: Bool
        /// True when the system proxy was changed by another app while we were running.
        var systemProxySetByOther: Bool
    }

    struct SuspendState: Equatable {
        var isSuspended: Bool
    }

    // MARK: - State

    private(set) var userIntent: UserIntent

    private(set) var runtimeState: RuntimeState {
        didSet { notifyStateChanged() }
    }

    private(set) var suspendState: SuspendState {
        didSet { notifyStateChanged() }
    }

    let stateDidChange = PublishRelay<StateSnapshot>()

    /// Combine mirror of runtimeState.tunActive for SwiftUI (ConfigView toggle sync).
    @Published private(set) var runtimeTunActive: Bool = false

    /// Monotonically increasing counter; stale TUN XPC completions are discarded.
    private var tunApplyGeneration: UInt64 = 0

    var state: StateSnapshot {
        .init(intent: userIntent, runtime: runtimeState, suspend: suspendState)
    }

    var isIconActive: Bool {
        if suspendState.isSuspended { return false }
        return runtimeState.systemProxyActive || runtimeState.tunActive
    }

    // MARK: - Initialization

    private override init() {
        self.userIntent = Self.readUserIntent()
        self.runtimeState = RuntimeState(systemProxyActive: false,
                                         tunActive: false,
                                         systemProxySetByOther: false)
        self.suspendState = SuspendState(isSuspended: false)
        // Legacy key from the pre-refactor code path.
        UserDefaults.standard.removeObject(forKey: "restoreSystemProxy")
    }

    // MARK: - User Intent (Persistence)

    private enum Keys {
        static let systemProxyEnabled = "proxyPortAutoSet"
        static let tunEnabled = "restoreTunProxy"
        static let tunOverridden = "tunOverridden"
    }

    private static func readUserIntent() -> UserIntent {
        UserIntent(
            systemProxyEnabled: UserDefaults.standard.bool(forKey: Keys.systemProxyEnabled),
            tunEnabled: UserDefaults.standard.bool(forKey: Keys.tunEnabled),
            tunOverridden: UserDefaults.standard.bool(forKey: Keys.tunOverridden)
        )
    }

    /// Explicit setter: updates in-memory value, persists, and notifies.
    func setIntent(_ newIntent: UserIntent) {
        userIntent = newIntent
        UserDefaults.standard.set(userIntent.systemProxyEnabled, forKey: Keys.systemProxyEnabled)
        UserDefaults.standard.set(userIntent.tunEnabled, forKey: Keys.tunEnabled)
        UserDefaults.standard.set(userIntent.tunOverridden, forKey: Keys.tunOverridden)
        notifyStateChanged()
    }

    // MARK: - Saved Proxy (Restore on Exit)

    /// Snapshot of user's pre-ClashX system proxy, restored on exit
    /// when !Settings.disableRestoreProxy. nil means never saved.
    private var savedProxyInfo: [String: Any]? {
        get { UserDefaults.standard.dictionary(forKey: "kSavedProxyInfo") }
        set { UserDefaults.standard.set(newValue, forKey: "kSavedProxyInfo") }
    }

    // MARK: - State Sync

    func syncTunState(from config: ClashConfig? = nil) async {
        let activeConfig = config ?? ConfigManager.shared.currentConfig
        let isActive = activeConfig?.tun.enable ?? false
        runtimeState.tunActive = isActive
    }

    func syncSystemProxyState() {
        let isClashSet = NetworkChangeNotifier.isCurrentSystemSetToClash()
        let (http, https, socks) = NetworkChangeNotifier.currentSystemProxySetting()
        let hasSetting = http > 0 || https > 0 || socks > 0

        runtimeState.systemProxyActive = isClashSet && hasSetting
        runtimeState.systemProxySetByOther = hasSetting && !isClashSet
    }

    // MARK: - User Actions

    func setSystemProxyEnabled(_ enabled: Bool) async {
        // Takeover branch: system proxy was set by another app.
        if runtimeState.systemProxySetByOther {
            if !enabled {
                // User asks to disable: just clear the flag, do NOT touch the
                // system proxy (it currently belongs to the other app).
                runtimeState.systemProxySetByOther = false
                notifyStateChanged()
                return
            }
            // enabled == true: user wants ClashX to reclaim.
            // Run SSID guard BEFORE any state mutation so Cancel is a no-op.
            let allowed = await SSIDSuspendTool.shared.checkAndHandleOverride(
                isTun: false, requestedEnable: true)
            if !allowed {
                // No state changes (intent, setByOther all untouched).
                notifyStateChanged()
                return
            }
            let success = await enableSystemProxy(skipSavingOriginal: true)
            guard success else {
                notifyStateChanged()
                return
            }
            runtimeState.systemProxySetByOther = false
            var newIntent = userIntent
            newIntent.systemProxyEnabled = true
            setIntent(newIntent)
            return
        }

        // Normal branch
        if enabled {
            let allowed = await SSIDSuspendTool.shared.checkAndHandleOverride(
                isTun: false, requestedEnable: true)
            if !allowed {
                notifyStateChanged()
                return
            }
            let success = await enableSystemProxy()
            guard success else {
                notifyStateChanged()
                return
            }
            var newIntent = userIntent
            newIntent.systemProxyEnabled = true
            setIntent(newIntent)
        } else {
            _ = await disableSystemProxy(force: true)
            var newIntent = userIntent
            newIntent.systemProxyEnabled = false
            setIntent(newIntent)
        }
    }

    func setTunEnabled(_ enabled: Bool) async {
        if enabled {
            let allowed = await SSIDSuspendTool.shared.checkAndHandleOverride(
                isTun: true, requestedEnable: enabled)
            if !allowed {
                notifyStateChanged()
                return
            }
            let success = await enableTun()
            guard success else {
                notifyStateChanged()
                return
            }
        } else {
            _ = await disableTun()
        }
        var newIntent = userIntent
        newIntent.tunEnabled = enabled
        newIntent.tunOverridden = true
        setIntent(newIntent)
    }

    // MARK: - Unified Recovery Entry

    /// Reconcile all proxy states after config load, network change, or wakeup.
    func reconcileState() async {
        await syncTunState()
        syncSystemProxyState()

        if suspendState.isSuspended {
            _ = await disableSystemProxy(force: true)
            _ = await disableTun()
            return
        }

        await reconcileSystemProxy()
        await reconcileTun()
    }

    // MARK: - SSID Suspend

    func setSuspended(_ suspended: Bool) async {
        guard suspended != suspendState.isSuspended else { return }
        suspendState.isSuspended = suspended
        await reconcileState()
    }

    // MARK: - System Proxy Helpers

    private func reconcileSystemProxy() async {
        guard !suspendState.isSuspended else { return }

        if userIntent.systemProxyEnabled {
            _ = await enableSystemProxy()
        } else if runtimeState.systemProxyActive || isAnySystemProxySet() {
            _ = await disableSystemProxy(force: true)
        }
    }

    @discardableResult
    private func enableSystemProxy(skipSavingOriginal: Bool = false) async -> Bool {
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socketPort = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        guard port > 0 && socketPort > 0 else {
            Logger.log("enableSystemProxy fail: invalid port \(port) \(socketPort)", level: .error)
            return false
        }

        // Snapshot user's pre-ClashX proxy once, so disable can restore it.
        // Takeover branch skips save (system is someone else's proxy).
        if !skipSavingOriginal, !Settings.disableRestoreProxy, savedProxyInfo == nil {
            await saveCurrentProxySetting()
        }

        do {
            let message = ProxyConfigHelperMessages.EnableProxy(
                port: port,
                socksPort: socketPort,
                pac: nil,
                filterInterface: Settings.filterInterface,
                ignoreList: Settings.proxyIgnoreList
            )
            if let error = try await PrivilegedHelperManager.shared.request(message) {
                Logger.log("enableSystemProxy \(error)", level: .error)
                return false
            } else {
                runtimeState.systemProxyActive = true
                return true
            }
        } catch {
            Logger.log("enableSystemProxy failed: \(error)", level: .error)
            return false
        }
    }

    private func saveCurrentProxySetting() async {
        do {
            let payload = try await PrivilegedHelperManager.shared.request(
                ProxyConfigHelperMessages.GetCurrentProxySetting())
            savedProxyInfo = try payload.dictionary()
            Logger.log("saveCurrentProxySetting done", level: .debug)
        } catch {
            Logger.log("saveCurrentProxySetting failed: \(error)", level: .error)
        }
    }

    @discardableResult
    private func disableSystemProxy(force: Bool = false) async -> Bool {
        // 1) force or user opted out of restore or savedProxyInfo nil/empty -> DisableProxy (clear all)
        // 2) otherwise -> RestoreProxy (re-apply savedProxyInfo)
        // Per decision: empty savedProxyInfo (user had no proxy originally) is
        // NOT treated as restorable. Use force-disable (clear all) instead.
        let shouldRestore = !force
            && !Settings.disableRestoreProxy
            && savedProxyInfo != nil
            && !(savedProxyInfo!.isEmpty)

        if shouldRestore, let info = savedProxyInfo {
            do {
                let infoPlist = try ProxyConfigHelperPropertyList(info)
                let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
                let socketPort = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
                let message = ProxyConfigHelperMessages.RestoreProxy(
                    currentPort: port,
                    socksPort: socketPort,
                    info: infoPlist,
                    filterInterface: Settings.filterInterface)
                if let error = try await PrivilegedHelperManager.shared.request(message) {
                    Logger.log("restoreSystemProxy \(error), fallback to disable", level: .error)
                    try? await sendDisableProxy()
                    // XPC fail: keep savedProxyInfo for next attempt
                } else {
                    Logger.log("restoreSystemProxy done", level: .debug)
                    savedProxyInfo = nil   // consumed on success
                }
            } catch {
                Logger.log("savedProxyInfo invalid, fallback to disable", level: .error)
                savedProxyInfo = nil   // corrupted; clear to avoid repeated failure
                try? await sendDisableProxy()
            }
        } else {
            try? await sendDisableProxy()
        }
        runtimeState.systemProxyActive = false
        return true
    }

    private func sendDisableProxy() async throws {
        let message = ProxyConfigHelperMessages.DisableProxy(filterInterface: Settings.filterInterface)
        if let error = try await PrivilegedHelperManager.shared.request(message) {
            Logger.log("disableSystemProxy \(error)", level: .error)
        }
    }

    // MARK: - TUN Helpers

    private func reconcileTun() async {
        guard !suspendState.isSuspended else { return }

        if userIntent.tunOverridden {
            if userIntent.tunEnabled {
                _ = await enableTun()
            } else {
                _ = await disableTun()
            }
        }
    }

    @discardableResult
    private func enableTun() async -> Bool {
        if await SSIDSuspendTool.shared.shouldSuspend() {
            Logger.log("not enableTun due to ssid in disabled list", level: .info)
            return false
        }
        return await applyTunOnKernel(enabled: true)
    }

    @discardableResult
    private func disableTun() async -> Bool {
        await applyTunOnKernel(enabled: false)
    }

    /// Single point that drives every TUN state change.
    @discardableResult
    private func applyTunOnKernel(enabled: Bool) async -> Bool {
        if enabled && ExitManager.shared.quitState != .idle { return false }
        tunApplyGeneration += 1
        let generation = tunApplyGeneration
        Logger.log("applyTunOnKernel enabled=\(enabled) generation=\(generation)")
        await ApiRequest.updateTun(enable: enabled)
        do {
            try await PrivilegedHelperManager.shared.request(
                ProxyConfigHelperMessages.UpdateTun(state: enabled, dns: ConfigManager.metaTunDNS))
            Logger.log("UpdateTun(\(enabled)) done")
        } catch {
            Logger.log("UpdateTun(\(enabled)) failed: \(error.localizedDescription)", level: .warning)
        }
        // Discard stale completion — a newer applyTunOnKernel already ran.
        guard generation == tunApplyGeneration else { return false }
        runtimeState.tunActive = enabled
        return true
    }

    func disableTunForTermination() async {
        tunApplyGeneration += 1
        Logger.log("disableTunForTermination, generation \(tunApplyGeneration)")
        do {
            try await PrivilegedHelperManager.shared.request(
                ProxyConfigHelperMessages.UpdateTun(state: false, dns: ConfigManager.metaTunDNS))
            Logger.log("UpdateTun(false) done")
        } catch {
            Logger.log("UpdateTun(false) failed: \(error.localizedDescription)", level: .warning)
        }
        runtimeState.tunActive = false
        Logger.log("tunActive reset to false")
    }

    // MARK: - Port Change

    func updateProxyPortsIfNeeded(oldConfig: ClashConfig?, newConfig: ClashConfig) async {
        guard oldConfig?.usedHttpPort != newConfig.usedHttpPort ||
                oldConfig?.usedSocksPort != newConfig.usedSocksPort else { return }

        Logger.log("port config updated,new: \(newConfig.usedHttpPort),\(newConfig.usedSocksPort)")
        guard userIntent.systemProxyEnabled && runtimeState.systemProxyActive else { return }

        _ = await enableSystemProxy()
    }

    // MARK: - External Change (System proxy changed by another app)

    func handleSystemProxySettingChanged() async {
        syncSystemProxyState()
        // No auto-recovery: the user resolves through the menu (shows .mixed).
    }

    // MARK: - Termination

    func disableAllProxiesForTermination(force: Bool) async {
        _ = await disableSystemProxy(force: force)
    }

    // MARK: - Private

    private func notifyStateChanged() {
        stateDidChange.accept(state)
        runtimeTunActive = runtimeState.tunActive
    }

    private func isAnySystemProxySet() -> Bool {
        let (http, https, socks) = NetworkChangeNotifier.currentSystemProxySetting()
        return http > 0 || https > 0 || socks > 0
    }
}
