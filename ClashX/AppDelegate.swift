//
//  AppDelegate.swift
//  ClashX
//
//  Created by CYC on 2018/6/10.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift
import SwiftyJSON
import Yams

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: NSStatusItem!

    @IBOutlet var statusMenu: NSMenu!
    @IBOutlet var proxySettingMenuItem: NSMenuItem!
    @IBOutlet var autoStartMenuItem: NSMenuItem!

    @IBOutlet var proxyModeGlobalMenuItem: NSMenuItem!
    @IBOutlet var proxyModeDirectMenuItem: NSMenuItem!
    @IBOutlet var proxyModeRuleMenuItem: NSMenuItem!
    @IBOutlet var allowFromLanMenuItem: NSMenuItem!

    @IBOutlet var proxyModeMenuItem: NSMenuItem!
    @IBOutlet var showNetSpeedIndicatorMenuItem: NSMenuItem!
    @IBOutlet var dashboardMenuItem: NSMenuItem!
    @IBOutlet var separatorLineTop: NSMenuItem!
    @IBOutlet var sepatatorLineEndProxySelect: NSMenuItem!
    @IBOutlet var configSeparatorLine: NSMenuItem!
    @IBOutlet var logLevelMenuItem: NSMenuItem!
    @IBOutlet var httpPortMenuItem: NSMenuItem!
    @IBOutlet var socksPortMenuItem: NSMenuItem!
    @IBOutlet var apiPortMenuItem: NSMenuItem!
    @IBOutlet var ipMenuItem: NSMenuItem!
    @IBOutlet var remoteConfigAutoupdateMenuItem: NSMenuItem!
    @IBOutlet var copyExportCommandMenuItem: NSMenuItem!
    @IBOutlet var copyExportCommandExternalMenuItem: NSMenuItem!
    @IBOutlet var externalControlSeparator: NSMenuItem!
    @IBOutlet var connectionsMenuItem: NSMenuItem!

    @IBOutlet var tunModeMenuItem: NSMenuItem!

    @IBOutlet var proxyProvidersMenu: NSMenu!
    @IBOutlet var ruleProvidersMenu: NSMenu!
    @IBOutlet var proxyProvidersMenuItem: NSMenuItem!
    @IBOutlet var ruleProvidersMenuItem: NSMenuItem!
    @IBOutlet var snifferMenuItem: NSMenuItem!
    @IBOutlet var flushFakeipCacheMenuItem: NSMenuItem!

    var disposeBag = DisposeBag()
    var statusItemView: StatusItemViewProtocol!

    let clashProcess = ClashProcess()
    let clashStatusTool = ClashStatusTool()

    func applicationWillFinishLaunching(_ notification: Notification) {
        Logger.log("applicationWillFinishLaunching")

        signal(SIGPIPE, SIG_IGN)
        // crash recorder
        Task { await failLaunchProtect() }
        NSAppleEventManager.shared()
            .setEventHandler(self,
                             andSelector: #selector(handleURL(event:reply:)),
                             forEventClass: AEEventClass(kInternetEventClass),
                             andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.setupLogSession()
        Logger.log("———————————————————————————————————————————————————————————")
        Logger.log("———————————————applicationDidFinishLaunching———————————————")
        Logger.log("———————————————————————————————————————————————————————————")
        Logger.log("Appversion: \(AppVersionUtil.currentVersion) \(AppVersionUtil.currentBuild)")
        ProcessInfo.processInfo.disableSuddenTermination()
        StatusItemView.suppressStatusBarTilingConstraintUpdates()
        Task { @MainActor in
            // setup menu item first
            statusItemView = await StatusItemView.create()
            statusItem = statusItemView.statusItem
            statusMenu.delegate = self
            setupStatusMenuItemData()
            
            await self.postFinishLaunching()
        }
    }

    @MainActor
    func postFinishLaunching() async {
        Logger.log("postFinishLaunching")
        defer {
            statusItem.menu = statusMenu
            Task { @MainActor in
                try? await Task.sleep(seconds: 8)
                self.checkMenuIconVisable()
            }
        }
        if #unavailable(macOS 10.15) {
            // dashboard is not support in macOS 10.15 below
            self.dashboardMenuItem.isHidden = true
            self.connectionsMenuItem.isHidden = true
        }
        await AppVersionUtil.showUpgradeAlert()
        ICloudManager.shared.setup()

        if WebPortalManager.hasWebProtal {
            WebPortalManager.shared.addWebProtalMenuItem(&statusMenu)
        }
		
        // install proxy helper
        _ = ClashResourceManager.check()
        await PrivilegedHelperManager.shared.checkInstall()
        ConfigFileManager.copySampleConfigIfNeed()

        // claer not existed selected model
        await ConfigReloadManager.shared.removeUnExistProxyGroups()
        setupData()

        await ConfigReloadManager.shared.updateLoggingLevel(menuItems: logLevelMenuItem.submenu?.items ?? [])

        // start watch config file change
        await ConfigManager.watchCurrentConfigFile()

        await RemoteConfigManager.shared.autoUpdateCheckIfNeeded()

        setupNetworkNotifier()
        registCrashLogger()
        KeyboardShortCutManager.setup()
        await RemoteControlManager.setupMenuItem(separator: externalControlSeparator)
    }

    
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch ExitManager.shared.quitState {
        case .done:
            return .terminateNow
        case .cleaning:
            return .terminateCancel
        case .idle:
            Task { @MainActor in
                let decision = await ExitManager.shared.handleShouldTerminate()
                if decision == .terminateNow {
                    NSApp.terminate(nil)
                }
            }
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
            Task {
            await ExitManager.shared.handleWillTerminate()
        }
    }

    func checkMenuIconVisable() {
        guard let button = statusItem.button else { assertionFailure(); return }
        guard let window = button.window else { assertionFailure(); return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let onScreenRect = window.convertToScreen(buttonRect)
        var leftScreenX: CGFloat = 0
        for screen in NSScreen.screens where screen.frame.origin.x < leftScreenX {
            leftScreenX = screen.frame.origin.x
        }
        let isMenuIconHidden = onScreenRect.midX < leftScreenX

        var isCoverdByNotch = false
        if #available(macOS 12, *), NSScreen.screens.count == 1, let screen = NSScreen.screens.first, let leftArea = screen.auxiliaryTopLeftArea, let rightArea = screen.auxiliaryTopRightArea {
            if onScreenRect.minX > leftArea.maxX, onScreenRect.maxX < rightArea.minX {
                isCoverdByNotch = true
            }
        }

        Logger.log("checkMenuIconVisable: \(onScreenRect) \(leftScreenX), hidden: \(isMenuIconHidden), coverd by notch:\(isCoverdByNotch)")

        if isMenuIconHidden || isCoverdByNotch, !Settings.disableMenubarNotice {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("The status icon is coverd or hide by other app.", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Never show again", comment: ""))
            if alert.runModal() == .alertSecondButtonReturn {
                Settings.disableMenubarNotice = true
            }
        }
    }

    @MainActor
    func setupStatusMenuItemData() {
        ConfigManager.shared
            .showNetSpeedIndicatorObservable
            .bind { [weak self] show in
                guard let self = self else { return }
                self.showNetSpeedIndicatorMenuItem.state = (show ?? true) ? .on : .off
                self.statusItemView.updateSize(self.statusItem, showSpeed: show ?? true)
                self.statusItemView.showSpeedContainer(show: show ?? true)
            }.disposed(by: disposeBag)

        statusItemView.updateViewStatus(enableProxy: ProxyManager.shared.isIconActive)
    }

    private func menuState(forSystemProxy state: ProxyManager.StateSnapshot) -> NSControl.StateValue {
        if state.suspend.isSuspended {
            return state.runtime.systemProxyActive ? .on : .mixed
        }
        if state.runtime.systemProxySetByOther {
            return .mixed
        }
        return state.intent.systemProxyEnabled ? .on : .off
    }

    private func menuState(forTun state: ProxyManager.StateSnapshot) -> NSControl.StateValue {
        if state.suspend.isSuspended {
            return state.runtime.tunActive ? .on : .mixed
        }
        if state.intent.tunOverridden {
            return state.intent.tunEnabled ? .on : .off
        }
        return state.runtime.tunActive ? .on : .off
    }
	
    func setupData() {
        ConfigManager.shared
            .showNetSpeedIndicatorObservable.skip(1)
            .bind { _ in
                Task { @MainActor in
                    ApiRequest.shared.resetStreamApi(for: .traffic)
                }
            }.disposed(by: disposeBag)

        ProxyManager.shared
            .stateDidChange
            .asObservable()
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe { [weak self] state in
                guard let self = self else { return }
                Task { @MainActor in
                    self.proxySettingMenuItem.state = self.menuState(forSystemProxy: state)
                    self.tunModeMenuItem.state = self.menuState(forTun: state)
                    self.statusItemView.updateViewStatus(enableProxy: ProxyManager.shared.isIconActive)
                }
            }
            .disposed(by: disposeBag)

        let configObservable = ConfigManager.shared
            .currentConfigRelay
            .asObservable()
        Observable.zip(configObservable, configObservable.skip(1))
            .filter { _, new in return new != nil }
            .observe(on: MainScheduler.instance)
            .bind { [weak self] old, config in
                guard let self = self, let config = config else { return }
                self.proxyModeDirectMenuItem.state = .off
                self.proxyModeGlobalMenuItem.state = .off
                self.proxyModeRuleMenuItem.state = .off

                switch config.mode {
                case .direct: self.proxyModeDirectMenuItem.state = .on
                case .global: self.proxyModeGlobalMenuItem.state = .on
                case .rule: self.proxyModeRuleMenuItem.state = .on
                }
                self.allowFromLanMenuItem.state = config.allowLan ? .on : .off

                self.proxyModeMenuItem.title = "\(NSLocalizedString("Proxy Mode", comment: "")) (\(config.mode.name))"

                Task {
                    await ProxyManager.shared.updateProxyPortsIfNeeded(oldConfig: old, newConfig: config)
                }

                self.httpPortMenuItem.title = "Http Port: \(config.usedHttpPort)"
                self.socksPortMenuItem.title = "Socks Port: \(config.usedSocksPort)"
                self.apiPortMenuItem.title = "Api Port: \(ConfigManager.shared.apiPort)"
                self.ipMenuItem.title = "IP: \(NetworkChangeNotifier.getPrimaryIPAddress() ?? "")"

                if RemoteControlManager.selectConfig == nil {
                    Task {
                        await self.clashStatusTool.checkPortConfig(cfg: config)
                    }
                }

                self.snifferMenuItem.state = config.sniffing ? .on : .off
            }.disposed(by: disposeBag)
		
		if !PrivilegedHelperManager.shared.isHelperCheckFinishedRelay.value {
			proxySettingMenuItem.target = nil
			tunModeMenuItem.target = nil
			PrivilegedHelperManager.shared.isHelperCheckFinishedRelay
				.filter({$0})
				.take(1)
				.observe(on: MainScheduler.instance)
				.subscribe { [weak self] _ in
					guard let self = self else { return }
					self.proxySettingMenuItem.target = self
					self.tunModeMenuItem.target = self
                    Task {
                        await self.startProxyCore()
                    }
				}.disposed(by: disposeBag)
		} else {
			self.proxySettingMenuItem.target = self
			self.tunModeMenuItem.target = self
            Task {
                await startProxyCore()
            }
		}

        LaunchAtLogin.shared
            .isLaunchAtLoginEnabledRelay
            .asObservable()
            .subscribe(onNext: { [weak self] enable in
                guard let self = self else { return }
                self.autoStartMenuItem.state = enable ? .on : .off
            }).disposed(by: disposeBag)

        remoteConfigAutoupdateMenuItem.state = RemoteConfigManager.autoUpdateEnable ? .on : .off

    }

    @MainActor
    func setupNetworkNotifier() {
        Task { @MainActor in
            try? await Task.sleep(seconds: 5)
            await NetworkChangeNotifier.start()
        }

        NotificationCenter
            .default
            .rx
            .notification(.systemNetworkStatusDidChange)
            .observe(on: MainScheduler.instance)
            .delay(.milliseconds(200), scheduler: MainScheduler.instance)
            .bind { _ in
                guard NetworkChangeNotifier.getPrimaryInterface() != nil else { return }
                Task { @MainActor in
                    await ProxyManager.shared.handleSystemProxySettingChanged()
                    let state = ProxyManager.shared.state
                    if state.suspend.isSuspended {
                        let (http, https, socks) = NetworkChangeNotifier.currentSystemProxySetting()
                        if http == 0 && https == 0 && socks == 0 {
                            Logger.log("Proxy paused!")
                            return
                        }
                    }
                    if state.runtime.systemProxySetByOther {
                        let proxiesSetting = NetworkChangeNotifier.getRawProxySetting()
                        Logger.log("Proxy changed by other process!, current:\(proxiesSetting), is Interface Set: \(NetworkChangeNotifier.hasInterfaceProxySetToClash())", level: .warning)
                    }
                }
            }.disposed(by: disposeBag)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(resetProxySettingOnWakeupFromSleep),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        ProxyHealthCheckManager.shared.setupHealthCheckOnIPAddressChange(disposeBag: disposeBag)

        ProxyManager.shared
            .stateDidChange
            .asObservable()
            .map { $0.runtime.systemProxySetByOther }
            .distinctUntilChanged()
            .filter { $0 }
            .filter { _ in !ProxyManager.shared.state.suspend.isSuspended }
            .bind { _ in
                let rawProxy = NetworkChangeNotifier.getRawProxySetting()
                Logger.log("proxy changed to no clashX setting: \(rawProxy)", level: .warning)
                UserNotificationCenter.shared.postProxyChangeByOtherAppNotice()
            }.disposed(by: disposeBag)

        ConfigReloadManager.shared.setupRemoteControlStreamResetOnIPAddressChange(disposeBag: disposeBag)
    }

    func updateProxyList(withMenus menus: [NSMenuItem]) {
        let startIndex = statusMenu.items.firstIndex(of: separatorLineTop)! + 1
        let endIndex = statusMenu.items.firstIndex(of: sepatatorLineEndProxySelect)!
        sepatatorLineEndProxySelect.isHidden = menus.isEmpty
        for _ in 0 ..< endIndex - startIndex {
            statusMenu.removeItem(at: startIndex)
        }
        for each in menus {
            statusMenu.insertItem(each, at: startIndex)
        }
    }

    @MainActor
    func updateConfigFiles() async {
        guard let menu = configSeparatorLine.menu else { return }
        let items = await MenuItemFactory.generateSwitchConfigMenuItems()
        let lineIndex = menu.items.firstIndex(of: self.configSeparatorLine)!
        for _ in 0 ..< lineIndex {
            menu.removeItem(at: 0)
        }
        for item in items.reversed() {
            menu.insertItem(item, at: 0)
        }
    }

    @objc func resetProxySettingOnWakeupFromSleep() {
        Task {
            await ProxyManager.shared.reconcileState()
        }
    }
}

// MARK: Meta Core

extension AppDelegate: ClashProcessDelegate {
	
    @MainActor
    func startProxyCore() async {
        guard !ConfigManager.shared.kernelState.isOperational else { return }
        await clashProcess.startIfNeeded(delegate: self)
	}
	
    func clashProcess(_ process: ClashProcess, didFailToResolveLaunchPath message: String) async {
		let alert = NSAlert()
        alert.messageText = message
		alert.alertStyle = .warning
		alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
		alert.runModal()
        ExitManager.shared.requestQuit(force: true)
	}

    func clashProcess(_ process: ClashProcess, didStartWith server: MetaServer) async {
		let port = server.externalController.components(separatedBy: ":").last ?? "9090"
		ConfigManager.shared.apiPort = port
		ConfigManager.shared.apiSecret = server.secret
		ConfigManager.shared.kernelState = .running
		proxyModeMenuItem.isEnabled = true
		dashboardMenuItem.isEnabled = true
	}
	
    func clashProcessDidUpdateConfig(_ process: ClashProcess) async {
        await ConfigReloadManager.shared.handleClashConfigUpdated(isInitialApply: true)
	}
	
    func clashProcess(_ process: ClashProcess, didFailToStartWith error: Error) async {
		let unc = UserNotificationCenter.shared
        switch error {
        case StartMetaError.pushConfigFailed:
			ConfigManager.shared.kernelState = .running
            proxyModeMenuItem.isEnabled = true
        default:
			ConfigManager.shared.kernelState = .failedToStart
            proxyModeMenuItem.isEnabled = false
        }

		switch error {
		case StartMetaError.configMissing:
			unc.postConfigErrorNotice(msg: "Can't find config.")
		case StartMetaError.remoteConfigMissing:
			unc.postConfigErrorNotice(msg: "Can't find remote config.")
		case StartMetaError.helperNotFound:
			unc.postMetaErrorNotice(msg: "Can't connect to helper.")
		case StartMetaError.startMetaFailed(let s):
			unc.postMetaErrorNotice(msg: s)
		case StartMetaError.pushConfigFailed(let s):
			unc.postConfigErrorNotice(msg: s)
		default:
			unc.postMetaErrorNotice(msg: "Unknown Error.")
		}
	}
}

// MARK: Main actions

extension AppDelegate {
    @IBAction func actionDashboard(_ sender: NSMenuItem?) {
		DashboardManager.shared.show(sender)
    }

    @IBAction func actionAllowFromLan(_ sender: NSMenuItem) {
        let allow = sender.state != .on
        ConfigOverride.shared.allowLan = allow
        Task {
            await ApiRequest.updateAllowLan(allow: allow)
            await ConfigReloadManager.shared.syncConfig()
            sender.state = allow ? .on : .off
        }
    }

    @IBAction func actionStartAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.shared.isEnabled = !LaunchAtLogin.shared.isEnabled
    }

    @IBAction func actionSwitchProxyMode(_ sender: NSMenuItem) {
        let mode: ClashProxyMode
        switch sender {
        case proxyModeGlobalMenuItem:
            mode = .global
        case proxyModeDirectMenuItem:
            mode = .direct
        case proxyModeRuleMenuItem:
            mode = .rule
        default:
            return
        }
        Task {
            await switchProxyMode(mode: mode)
        }
    }

    @MainActor
    func switchProxyMode(mode: ClashProxyMode) async {
        let config = ConfigManager.shared.currentConfig?.copy()
        config?.mode = mode
		_ = await ApiRequest.updateOutBoundMode(mode: mode)
		ConfigManager.shared.currentConfig = config
		ConfigOverride.shared.mode = mode
		await MenuItemFactory.recreateProxyMenuItems()
    }

    @IBAction func actionShowNetSpeedIndicator(_ sender: NSMenuItem) {
        ConfigManager.shared.showNetSpeedIndicator = !(sender.state == .on)
    }

    @IBAction func actionSetSystemProxy(_ sender: Any?) {
        let enable = proxySettingMenuItem.state != .on
        Task {
            await ProxyManager.shared.setSystemProxyEnabled(enable)
        }
    }

    @IBAction func actionCopyExportCommand(_ sender: NSMenuItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socksport = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        let localhost = "127.0.0.1"
        let isLocalhostCopy = sender == copyExportCommandMenuItem
        let ip = isLocalhostCopy ? localhost :
            NetworkChangeNotifier.getPrimaryIPAddress() ?? localhost
        pasteboard.setString("export https_proxy=http://\(ip):\(port) http_proxy=http://\(ip):\(port) all_proxy=socks5://\(ip):\(socksport)", forType: .string)
    }

    @IBAction func actionSpeedTest(_ sender: Any) {
		Task {
			await ProxyHealthCheckManager.shared.runSpeedTest()
        }
    }

    @IBAction func actionUpdateExternalResource(_ sender: Any) {
        Task {
            await UpdateExternalResourceAction.run()
        }
    }

    @IBAction func actionQuit(_ sender: Any) {
        let forceQuit = NSEvent.modifierFlags.contains(.option)
        Task {
            ExitManager.shared.requestQuit(force: forceQuit)
        }
    }

    @IBAction func checkForUpdates(_ sender: Any?) {
        // App updates stay local in this fork; never initialize an upstream updater.
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("You're up to date!", comment: "Local app update status")
        alert.informativeText = "ClashX Meta \(AppVersionUtil.currentVersion) (\(AppVersionUtil.currentBuild))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }

    @IBAction func actionMoreSetting(_ sender: Any) {
        ClashWindowController<SettingTabViewController>.create().showWindow(sender)
    }
}

// MARK: Streaming Info

extension AppDelegate: ApiRequestStreamDelegate {
	func didUpdateMemory(memory: Int64) async {
		
	}
	
	func streamStatusChanged() async {
        await MainActor.run {
            let isRunning = ConfigManager.shared.kernelState.isOperational
            if !isRunning {
                statusItemView.updateViewStatus(enableProxy: false)
            } else {
                statusItemView.updateViewStatus(enableProxy: ProxyManager.shared.isIconActive)
            }
        }
	}
	
    func didUpdateTraffic(up: Int, down: Int) async {
        await MainActor.run {
            statusItemView.updateSpeedLabel(up: up, down: down)
        }
    }

    func didGetLog(log: String, level: String) async {
        Logger.logCore(log, level: ClashLogLevel(rawValue: level) ?? .unknow)
    }
}

// MARK: Help actions

extension AppDelegate {
    @IBAction func actionShowLog(_ sender: Any?) {
        NSWorkspace.shared.openFilePath(Logger.shared.logFilePath())
    }
}

// MARK: Config actions

extension AppDelegate {
    @IBAction func openConfigFolder(_ sender: Any) {
        Task { @MainActor in
            await ConfigFileManager.shared.openConfigFolder()
        }
    }

    @IBAction func actionUpdateConfig(_ sender: AnyObject) {
        Task {
            await ConfigReloadManager.shared.updateConfig()
        }
    }

    @IBAction func actionSetLogLevel(_ sender: NSMenuItem) {
        let level = ClashLogLevel(rawValue: sender.title.lowercased()) ?? .unknow
        ConfigOverride.shared.logLevel = level
        Task { @MainActor in
            await ConfigReloadManager.shared.updateLoggingLevel(menuItems: logLevelMenuItem.submenu?.items ?? [])
            ConfigReloadManager.shared.resetStreamApi()
        }
    }

    @IBAction func actionAutoUpdateRemoteConfig(_ sender: Any) {
        RemoteConfigManager.autoUpdateEnable = !RemoteConfigManager.autoUpdateEnable
        remoteConfigAutoupdateMenuItem.state = RemoteConfigManager.autoUpdateEnable ? .on : .off
    }

    @IBAction func actionUpdateRemoteConfig(_ sender: Any) {
        Task {
            await RemoteConfigManager.shared.updateCheck(ignoreTimeLimit: true, showNotification: true)
        }
    }

    @IBAction func actionSetUpdateInterval(_ sender: Any) {
        RemoteConfigManager.showAdd()
    }

}


// MARK: Meta Menu

extension AppDelegate {
    @IBAction func actionSetTunMode(_ sender: NSMenuItem?) {
        let enable = tunModeMenuItem.state != .on
        tunModeMenuItem.isEnabled = false
        Task {
            await ProxyManager.shared.setTunEnabled(enable)
            tunModeMenuItem.isEnabled = true
        }
    }

    @IBAction func updateGEO(_ sender: NSMenuItem) {
        Task {
            _ = await ApiRequest.updateGEO()
        }
    }

    @IBAction func flushDNSCache(_ sender: NSMenuItem) {
        Task {
            await ApiRequest.flushDNSCache()
            try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.FlushDnsCache())
        }
    }

    @IBAction func updateSniffing(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        ConfigOverride.shared.snifferEnable = enable
        Task {
            await ApiRequest.updateSniffing(enable: enable)
            sender.state = enable ? .on : .off
        }
    }
}

// MARK: crash hanlder

extension AppDelegate {
    func registCrashLogger() {
        /*
        #if DEBUG
            return
        #else
            Task { @MainActor in
                try? await Task.sleep(seconds: 5)
                AppCenter.start(withAppSecret: "dce6e9a3-b6e3-4fd2-9f2d-35c767a99663", services: [
                    Analytics.self,
                    Crashes.self
                ])
            }

        #endif
         */
    }

    func failLaunchProtect() async {
        #if DEBUG
            return
        #else
            UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": false])
            let x = UserDefaults.standard
            var launch_fail_times = 0
            if let xx = x.object(forKey: "launch_fail_times") as? Int { launch_fail_times = xx }
            launch_fail_times += 1
            x.set(launch_fail_times, forKey: "launch_fail_times")
            if launch_fail_times > 3 {
                // 发生连续崩溃
                await MainActor.run { ConfigFileManager.backupAndRemoveConfigFile() }
					let ruleFiles = ClashResourceManager.RuleFiles.self

					try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.mmdb.rawValue)
					try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.geosite.rawValue)
					try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.geoip.rawValue)
					try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.bundleMRS.rawValue)

                if let domain = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                    UserDefaults.standard.synchronize()
                }
				UserNotificationCenter.shared.post(title: "Fail on launch protect", info: "You origin Config has been renamed", notiOnly: false)
            }
            Task {
                try? await Task.sleep(seconds: 5)
                x.set(0, forKey: "launch_fail_times")
            }
        #endif
    }
}

// MARK: Memory

extension AppDelegate {
    func hasMenuSelected() -> Bool {
        if #available(macOS 11, *) {
            return statusMenu.items.contains { $0.state == .on }
        } else {
            return true
        }
    }
}

// MARK: NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard ConfigManager.shared.kernelState.isOperational else { return }
		Task {
			await updateConfigFiles()
            await MenuItemFactory.refreshExistingMenuItems()
            await ConfigReloadManager.shared.syncConfig()
        }
        NotificationCenter.default.post(name: .proxyMeneViewShowLeftPadding,
                                        object: nil,
                                        userInfo: ["show": hasMenuSelected()])
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        menu.items.forEach {
            ($0.view as? ProxyGroupMenuHighlightDelegate)?.highlight(item: item)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menu.items.forEach {
            ($0.view as? ProxyGroupMenuHighlightDelegate)?.highlight(item: nil)
        }
    }
}

// MARK: URL Scheme

extension AppDelegate {
    @objc func handleURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }

        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              scheme.hasPrefix("clash"),
              let host = components.host
        else { return }

        if host == "install-config" {
            guard let url = components.queryItems?.first(where: { item in
                item.name == "url"
            })?.value else { return }

            var userInfo = ["url": url]
            if let name = components.queryItems?.first(where: { item in
                item.name == "name"
            })?.value {
                userInfo["name"] = name
            }

            remoteConfigAutoupdateMenuItem.menu?.performActionForItem(at: 0)

            Task { @MainActor in
                try? await Task.sleep(seconds: 0.2)
                NotificationCenter.default.post(name: Notification.Name(rawValue: "didGetUrl"), object: nil, userInfo: userInfo)
            }
        } else if host == "update-config" {
            Task {
                await ConfigReloadManager.shared.updateConfig()
            }
        }
    }
}
