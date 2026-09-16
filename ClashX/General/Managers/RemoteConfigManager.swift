//
//  RemoteConfigManager.swift
//  ClashX
//
//  Created by yicheng on 2018/11/6.
//  Copyright © 2018 west2online. All rights reserved.
//

import Cocoa

class RemoteConfigManager {
    var configs: [RemoteConfigModel] = []
    var refreshActivity: NSBackgroundActivityScheduler?

    static let shared = RemoteConfigManager()

    private init() {
        if let savedConfigs = UserDefaults.standard.object(forKey: "kRemoteConfigs") as? Data {
            let decoder = JSONDecoder()
            if let loadedConfig = try? decoder.decode([RemoteConfigModel].self, from: savedConfigs) {
                configs = loadedConfig
            } else {
                assertionFailure()
            }
        }
        migrateOldRemoteConfig()
        setupAutoUpdateTimer()
    }

    func saveConfigs() {
        Logger.log("Saving Remote Config Setting")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(configs) {
            UserDefaults.standard.set(encoded, forKey: "kRemoteConfigs")
        }
    }

    func migrateOldRemoteConfig() {
        if let url = UserDefaults.standard.string(forKey: "kRemoteConfigUrl"),
           let name = URL(string: url)?.host {
            configs.append(RemoteConfigModel(url: url, name: name))
            UserDefaults.standard.removeObject(forKey: "kRemoteConfigUrl")
            saveConfigs()
        }
    }

    func setupAutoUpdateTimer() {
        refreshActivity?.invalidate()
        refreshActivity = nil
        guard RemoteConfigManager.autoUpdateEnable else {
            Logger.log("autoUpdateEnable did not enable,autoUpateTimer invalidated.")
            return
        }
        Logger.log("set up autoUpateTimer")

        refreshActivity = NSBackgroundActivityScheduler(identifier: "com.ClashX.configupdate")
        refreshActivity?.repeats = true
        refreshActivity?.interval = 60 * 60 * 2 // Two hour
        refreshActivity?.tolerance = 60 * 60

        refreshActivity?.schedule { [weak self] completionHandler in
            self?.autoUpdateCheck()
            completionHandler(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    static var autoUpdateEnable: Bool {
        get {
            return UserDefaults.standard.object(forKey: "kAutoUpdateEnable") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kAutoUpdateEnable")
            RemoteConfigManager.shared.setupAutoUpdateTimer()
        }
    }

    @objc func autoUpdateCheck() {
        Task {
            await autoUpdateCheckIfNeeded()
        }
    }

    func autoUpdateCheckIfNeeded() async {
        guard RemoteConfigManager.autoUpdateEnable else { return }
        Logger.log("Tigger config auto update check")
        await updateCheck()
    }

    func updateCheck(ignoreTimeLimit: Bool = false, showNotification: Bool = false) async {
        let currentConfigName = ConfigManager.selectConfigName

        await withTaskGroup(of: Void.self) { group in
            configs.forEach { config in
                guard !config.updating else { return }
                let timeLimitNoMantians = Date().timeIntervalSince(config.updateTime ?? Date(timeIntervalSince1970: 0)) < Settings.configAutoUpdateInterval

                guard !timeLimitNoMantians || ignoreTimeLimit else {
                    Logger.log("[Auto Upgrade] Bypassing \(config.name) due to time check")
                    return
                }
                Logger.log("[Auto Upgrade] Requesting \(config.name)")
                let isCurrentConfig = config.name == currentConfigName
                config.updating = true
                group.addTask { [weak self, weak config] in
                    guard let self, let config else { return }
                    let error = await RemoteConfigManager.updateConfig(config: config)
                    await self.handleUpdateCheckResult(for: config, isCurrentConfig: isCurrentConfig, error: error, showNotification: showNotification)
                }
            }
        }

        saveConfigs()
    }

    @MainActor
    private func handleUpdateCheckResult(for config: RemoteConfigModel,
                                         isCurrentConfig: Bool,
                                         error: String?,
                                         showNotification: Bool) async {
        config.updating = false
        if error == nil {
            config.updateTime = Date()
        }

        guard isCurrentConfig else {
            Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error ?? "succeed")")
            return
        }

        if let error {
            if showNotification {
                UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update Fail", comment: ""),
                                                   info: "\(config.name): \(error)")
            }
            Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error)")
            return
        }

        if showNotification {
            let info = "\(config.name): \(NSLocalizedString("Succeed!", comment: ""))"
            UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update", comment: ""), info: info)
        }

        await ConfigReloadManager.shared.updateConfig(showNotification: false)
        Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error ?? "succeed")")
    }

    /// Session that bypasses the system proxy (direct connection only).
    /// Subscription updates can receive a stale TLS certificate chain when
    /// routed through the local proxy core, so they always go direct.
    private static let directSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    static func getRemoteConfigData(config: RemoteConfigModel) async -> (String?, String?) {
        guard let url = URL(string: config.url) else {
            assertionFailure()
            Logger.log("[getRemoteConfigData] url incorrect,\(config.name) \(config.url)")
            return (nil, nil)
        }
        
        do {
            var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData)
            // Preserve the system-default User-Agent unless a custom value is configured.
            if let userAgent = config.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !userAgent.isEmpty {
                urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            
            // Bypass the system proxy: subscription updates can receive a
            // stale TLS certificate chain when routed through the proxy core.
            let (data, response) = try await directSession.data(for: urlRequest)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                Logger.log("[getRemoteConfigData] http status \(httpResponse.statusCode), \(config.name) \(config.url)")
                return (nil, nil)
            }
            guard let configStr = String(data: data, encoding: .utf8) else {
                let preview = data.prefix(16).map { String(format: "%02x", $0) }.joined()
                let headers = (response as? HTTPURLResponse)?.allHeaderFields ?? [:]
                Logger.log("[getRemoteConfigData] decode fail, \(config.name) len=\(data.count) head=0x\(preview) headers=\(headers)", level: .error)
                return (nil, nil)
            }
            return (configStr, response.suggestedFilename)
        } catch {
            Logger.log("[getRemoteConfigData] error: \(error) url=\(config.url)", level: .error)
            return (nil, nil)
        }
    }

    static func updateConfig(config: RemoteConfigModel) async -> String? {
        let (configString, suggestedFilename) = await getRemoteConfigData(config: config)
        guard let configStr = configString else {
            return NSLocalizedString("Download fail", comment: "")
        }
        
        let (newConfig, error) = decryptConfig(string: configStr, config: config)
        
        guard let newConfig, error == nil else {
            return NSLocalizedString("Decrypt config fail", comment: "") + ", " + "\(error ?? "unknown")"
        }
        
        let verifyRes = verifyConfig(string: newConfig)
        if let error = verifyRes {
            return NSLocalizedString("Remote Config Format Error", comment: "") + ": " + error
        }

        if let suggestName = suggestedFilename, config.isPlaceHolderName {
            let name = URL(fileURLWithPath: suggestName).deletingPathExtension().lastPathComponent
            if !shared.configs.contains(where: { $0.name == name }) {
                config.name = name
            }
        }
        config.isPlaceHolderName = false

        if ICloudManager.shared.useICloudRelay.value {
            await ConfigFileManager.shared.stopWatchConfigFile()
        }
        if config.name == ConfigManager.selectConfigName {
            await ConfigFileManager.shared.pauseForNextChange()
        }

        let savePath: String?
        if ICloudManager.shared.useICloudRelay.value {
            savePath = await ICloudManager.shared.getUrl()?.appendingPathComponent(Paths.configFileName(for: config.name)).path
        } else {
            savePath = Paths.localConfigPath(for: config.name)
        }

        guard let savePath else { return NSLocalizedString("Download fail", comment: "") }

        do {
            if FileManager.default.fileExists(atPath: savePath) {
                try FileManager.default.removeItem(atPath: savePath)
            }
            try newConfig.write(to: URL(fileURLWithPath: savePath), atomically: true, encoding: .utf8)
            return nil
        } catch let err {
            return err.localizedDescription
        }
    }

    static func createCacheConfig(string: String) -> String? {
		let path = Paths.cacheConfigs()
        let confPath = path + "/\(UUID().uuidString).yaml"

        let fm = FileManager.default
        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)

        if fm.fileExists(atPath: confPath) {
            try? fm.removeItem(atPath: confPath)
        }

        guard fm.createFile(atPath: confPath, contents: string.data(using: .utf8)) else {
            return nil
        }
        return confPath
    }

    static func verifyConfig(string: String) -> ErrorString? {
        guard let confPath = createCacheConfig(string: string) else {
            return "Create verify config file failed"
        }
        
        return ClashProcess.verify(kConfigFolderPath, confFilePath: confPath)
    }
    
    static func decryptConfig(string: String, config: RemoteConfigModel) -> (config: String?, error: String?) {
        guard let key = config.ageSecretKey else {
            return (string, nil)
        }
        
        guard let confPath = createCacheConfig(string: string) else {
            return (nil, "Create verify config file failed")
        }
        
        let agePath = confPath + ".age"
        do {
            try FileManager.default.moveItem(atPath: confPath, toPath: agePath)
        } catch {
            return (nil, NSLocalizedString("Create age config file failed", comment: "") + ", \(error.localizedDescription)")
        }
        
        if let error = ClashProcess.ageDecrypt(key: key, inputPath: agePath, outputPath: confPath) {
            return (nil, error)
        }
        
        if let data = FileManager.default.contents(atPath: confPath),
           let newStr = String(data: data, encoding: .utf8) {
            return (newStr, nil)
        } else {
            return (nil, NSLocalizedString("Load decrypted config failed", comment: ""))
        }
    }

    static func showAdd() {
        let alertView = NSAlert()
        alertView.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alertView.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alertView.messageText = NSLocalizedString("Update remote config update interval", comment: "")
        let setupView = RemoteConfigUpdateIntervalSettingView()
        setupView.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
        alertView.accessoryView = setupView
        let response = alertView.runModal()

        guard response == .alertFirstButtonReturn else { return }
        let stringValue = setupView.textfield.stringValue
        guard let intValue = Int(stringValue), intValue > 0 else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.informativeText = NSLocalizedString("Should be a least 1 hour", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
            return
        }
        Settings.configAutoUpdateInterval = TimeInterval(intValue * 60 * 60)
        RemoteConfigManager.shared.autoUpdateCheck()
    }
}
