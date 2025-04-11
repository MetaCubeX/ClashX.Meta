//
//  RemoteConfigManager.swift
//  ClashX
//
//  Created by yicheng on 2018/11/6.
//  Copyright © 2018 west2online. All rights reserved.
//

import Alamofire
import Cocoa
import IOKit
import Foundation
import Darwin

class RemoteConfigManager {
    var configs: [RemoteConfigModel] = []
    var refreshActivity: NSBackgroundActivityScheduler?
    
    private static var cachedHWID: String?
    private static var cachedDeviceModel: String?

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
        guard RemoteConfigManager.autoUpdateEnable else { return }
        Logger.log("Tigger config auto update check")
        updateCheck()
    }

    func updateCheck(ignoreTimeLimit: Bool = false, showNotification: Bool = false) {
        let currentConfigName = ConfigManager.selectConfigName

        let group = DispatchGroup()

        for config in configs {
            if config.updating { continue }
            let timeLimitNoMantians = Date().timeIntervalSince(config.updateTime ?? Date(timeIntervalSince1970: 0)) < Settings.configAutoUpdateInterval

            if timeLimitNoMantians && !ignoreTimeLimit {
                Logger.log("[Auto Upgrade] Bypassing \(config.name) due to time check")
                continue
            }
            Logger.log("[Auto Upgrade] Requesting \(config.name)")
            let isCurrentConfig = config.name == currentConfigName
            config.updating = true
            group.enter()
            RemoteConfigManager.updateConfig(config: config) {
                [weak config] error in
                guard let config = config else { return }

                config.updating = false
                group.leave()
                if error == nil {
                    config.updateTime = Date()
                }

                if isCurrentConfig {
                    if let error = error {
                        // Fail
                        if showNotification {
							UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update Fail", comment: ""),
                                      info: "\(config.name): \(error)")
                        }

                    } else {
                        // Success
                        if showNotification {
                            let info = "\(config.name): \(NSLocalizedString("Succeed!", comment: ""))"
							UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update", comment: ""), info: info)
                        }
                        AppDelegate.shared.updateConfig(showNotification: false)
                    }
                }
                Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error ?? "succeed")")
            }
        }

        group.notify(queue: .main) {
            [weak self] in
            self?.saveConfigs()
        }
    }

    static func getRemoteConfigData(config: RemoteConfigModel, complete: @escaping ((String?, String?) -> Void)) {
        guard var urlRequest = try? URLRequest(url: config.url, method: .get) else {
            assertionFailure()
            Logger.log("[getRemoteConfigData] url incorrect,\(config.name) \(config.url)")
            return
        }
        urlRequest.cachePolicy = .reloadIgnoringCacheData
        
        let deviceHeaders = getDeviceHeaders()
        for (key, value) in deviceHeaders {
            urlRequest.addValue(value, forHTTPHeaderField: key)
        }
        
        Logger.log("[getRemoteConfigData] Adding device headers: \(deviceHeaders)", level: .info)

        AF.request(urlRequest)
            .validate()
            .responseString(encoding: .utf8) { res in
                complete(try? res.result.get(), res.response?.suggestedFilename)
            }
    }

    static func updateConfig(config: RemoteConfigModel, complete: ((String?) -> Void)? = nil) {
        getRemoteConfigData(config: config) { configString, suggestedFilename in
            guard let newConfig = configString else {
                complete?(NSLocalizedString("Download fail", comment: ""))
                return
            }

            let verifyRes = verifyConfig(string: newConfig)
            if let error = verifyRes {
                complete?(NSLocalizedString("Remote Config Format Error", comment: "") + ": " + error)
                return
            }

            if let suggestName = suggestedFilename, config.isPlaceHolderName {
                let name = URL(fileURLWithPath: suggestName).deletingPathExtension().lastPathComponent
                if !shared.configs.contains(where: { $0.name == name }) {
                    config.name = name
                }
            }
            config.isPlaceHolderName = false

            if ICloudManager.shared.useiCloud.value {
                ConfigFileManager.shared.stopWatchConfigFile()
            }
            if config.name == ConfigManager.selectConfigName {
                ConfigFileManager.shared.pauseForNextChange()
            }

            let saveAction: ((String) -> Void) = {
                savePath in
                do {
                    if FileManager.default.fileExists(atPath: savePath) {
                        try FileManager.default.removeItem(atPath: savePath)
                    }
                    try newConfig.write(to: URL(fileURLWithPath: savePath), atomically: true, encoding: .utf8)
                    complete?(nil)
                } catch let err {
                    complete?(err.localizedDescription)
                }
            }

            if ICloudManager.shared.useiCloud.value {
                ICloudManager.shared.getUrl { url in
                    guard let url = url else { return }
                    let saveUrl = url.appendingPathComponent(Paths.configFileName(for: config.name))
                    saveAction(saveUrl.path)
                }
            } else {
                let savePath = Paths.localConfigPath(for: config.name)
                saveAction(savePath)
            }
        }
    }

    static func createCacheConfig(string: String) -> String? {
		let path = Paths.tempPath() + "/cacheConfigs"
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
		
        return (NSApplication.shared.delegate as? AppDelegate)?.clashProcess.verify(kConfigFolderPath, confFilePath: confPath)
    }
    
    static func getDeviceHeaders() -> [String: String] {
    
        let hwid = getHardwareUUID()
        
        let processInfo = ProcessInfo.processInfo
        let osVersion = "\(processInfo.operatingSystemVersion.majorVersion).\(processInfo.operatingSystemVersion.minorVersion).\(processInfo.operatingSystemVersion.patchVersion)"
        let deviceModel = getDeviceModel()
        
        return [
            "x-hwid": hwid,
            "x-device-os": "macOS",
            "x-ver-os": osVersion,
            "x-device-model": deviceModel
        ]
    }
    
    static func getHardwareUUID() -> String {
        if let cachedID = cachedHWID {
            return cachedID
        }
        
        let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(platformExpert) }
        
        if let uuid = IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0) {
            if let uuidString = uuid.takeUnretainedValue() as? String {
                cachedHWID = uuidString
                return uuidString
            }
        }
        
        let fallbackUUID = UUID().uuidString
        cachedHWID = fallbackUUID
        Logger.log("[Hardware] Could not retrieve device hardware UUID, using generated UUID", level: .warning)
        return fallbackUUID
    }
    
    static func getDeviceModel() -> String {
        if let cachedModel = cachedDeviceModel {
            return cachedModel
        }
        
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        
        let modelString = String(cString: model)
        cachedDeviceModel = modelString
        return modelString
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
