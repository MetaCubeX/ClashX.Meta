//
//  ConfigManager.swift
//  ClashX
//
//  Created by CYC on 2018/6/12.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa
import Foundation
import RxCocoa
import RxSwift

class ConfigManager {
    static let shared = ConfigManager()

    // MARK: - Basic Settings

    var apiPort = "8080"
    var allowExternalControl = false
    var apiSecret: String = ""
    var overrideApiURL: URL?
    var overrideSecret: String?

    // MARK: - State

    enum KernelState: Equatable {
        case stopped
        case checkingLaunchPath
        case checkingHelper
        case preparingConfig
        case starting
        case reloadingConfig
        case disconnected
        case running
        case failedToStart

        var isOperational: Bool {
            self == .running || self == .reloadingConfig
        }
    }

    let kernelStateRelay = BehaviorRelay<KernelState>(value: .stopped)

    var currentConfig: ClashConfig? {
        get {
            return currentConfigRelay.value
        }

        set {
            currentConfigRelay.accept(newValue)
        }
    }

    var currentConfigRelay = BehaviorRelay<ClashConfig?>(value: nil)

    @MainActor
    var kernelState: KernelState {
        get {
            return kernelStateRelay.value
        }

        set {
            let oldValue = kernelStateRelay.value
            kernelStateRelay.accept(newValue)
            Logger.log("kernelState change: \(oldValue) -> \(newValue)", level: .info)
            NotificationCenter.default.post(.init(name: .init("ClashKernelStateChanged")))
        }
    }

    // MARK: - Config Selection

    static var selectConfigName: String {
        get {
            return UserDefaults.standard.string(forKey: "selectConfigName") ?? "config"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "selectConfigName")
            Task {
                await watchCurrentConfigFile()
            }
        }
    }

    @MainActor
    static func watchCurrentConfigFile() async {
        if ICloudManager.shared.useICloudRelay.value {
            guard let url = await ICloudManager.shared.getUrl() else { return }
            let configUrl = url.appendingPathComponent(Paths.configFileName(for: selectConfigName))
            ConfigFileManager.shared.watchFile(path: configUrl.path)
        } else {
            ConfigFileManager.shared.watchFile(path: Paths.localConfigPath(for: selectConfigName))
        }
    }

    // MARK: - Preferences

    static let defaultTunDNS = "8.8.8.8"
	
	static var metaTunDNS: String = UserDefaults.standard.object(forKey: "metaTunDNS") as? String ?? defaultTunDNS {
		didSet {
			UserDefaults.standard.set(metaTunDNS, forKey: "metaTunDNS")
		}
	}

    private let showNetSpeedIndicatorRelay = BehaviorRelay<Bool>(value: UserDefaults.standard.bool(forKey: "showNetSpeedIndicator"))
    var showNetSpeedIndicator: Bool {
        get {
            return showNetSpeedIndicatorRelay.value
        }
        set {
            showNetSpeedIndicatorRelay.accept(newValue)
            UserDefaults.standard.set(newValue, forKey: "showNetSpeedIndicator")
        }
    }

    var showNetSpeedIndicatorObservable: Observable<Bool?> {
        return showNetSpeedIndicatorRelay.map { $0 as Bool? }
    }

    var benchMarkUrl: String = UserDefaults.standard.string(forKey: "benchMarkUrl") ?? "http://cp.cloudflare.com/generate_204" {
        didSet {
            UserDefaults.standard.set(benchMarkUrl, forKey: "benchMarkUrl")
        }
    }

    static var apiUrl: String {
        if let override = shared.overrideApiURL {
            return override.absoluteString
        }
        return "http://127.0.0.1:\(shared.apiPort)"
    }



    static var selectedProxyRecords = SavedProxyModel.loadsFromUserDefault() {
        didSet {
            SavedProxyModel.save(selectedProxyRecords)
        }
    }

    /// Persist a proxy group selection so it can be replayed after reload.
    static func recordProxySelection(group: String, selected: String) {
        let newModel = SavedProxyModel(group: group, selected: selected, config: selectConfigName)
        selectedProxyRecords.removeAll { $0.key == newModel.key }
        selectedProxyRecords.append(newModel)
    }

    var disableShowCurrentProxyInMenu: Bool = UserDefaults.standard.object(forKey: "kSDisableShowCurrentProxyInMenu") as? Bool ?? !AppDelegate.isAboveMacOS14 {
        didSet {
            UserDefaults.standard.set(disableShowCurrentProxyInMenu, forKey: "kSDisableShowCurrentProxyInMenu")
        }
    }

    static func getConfigPath(configName: String) async -> String? {
        if ICloudManager.shared.useICloudRelay.value {
            guard let url = await ICloudManager.shared.getUrl() else {
                return nil
            }
            return url.appendingPathComponent(Paths.configFileName(for: configName)).path
        } else {
            return Paths.localConfigPath(for: configName)
        }
    }
}

extension ConfigManager {
    static func getConfigFilesList() -> [String] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(atPath: kConfigFolderPath)
            return fileURLs
                .filter { String($0.split(separator: ".").last ?? "") == "yaml" }
                .map { $0.split(separator: ".").dropLast().joined(separator: ".") }
        } catch {
            return ["config"]
        }
    }
}

enum WebDashboard: String {
    case yacd
    case metacubexd
    case zashboard
}

extension ConfigManager {
    static var webDashboard: WebDashboard {
        get {
            guard let string = UserDefaults.standard.object(forKey: "webDashboard") as? String,
                  let dashboard = WebDashboard(rawValue: string) else {
                return .zashboard
            }
            return dashboard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "webDashboard")
        }
    }
	
	static var useSwiftUIDashboard: Bool = UserDefaults.standard.object(forKey: "useSwiftUIDashboard") as? Bool ?? false {
		didSet {
			UserDefaults.standard.set(useSwiftUIDashboard, forKey: "useSwiftUIDashboard")
		}
	}
	
	static var useAlphaCore: Bool = UserDefaults.standard.object(forKey: "useAlphaCore") as? Bool ?? false {
		didSet {
			UserDefaults.standard.set(useAlphaCore, forKey: "useAlphaCore")
		}
	}
}
