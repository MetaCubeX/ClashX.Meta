//
//  AutoUpgardeManager.swift
//  ClashX
//
//  Created by yicheng on 2019/10/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa
import Sparkle

class AutoUpgardeManager: NSObject {
    var checkForUpdatesMenuItem: NSMenuItem?
    static let shared = AutoUpgardeManager()
    private var controller: SPUStandardUpdaterController?
    private var current: Channel = {
        if let value = UserDefaults.standard.object(forKey: "AutoUpgardeManager.current") as? Int,
           let channel = Channel(rawValue: value) { return channel }
        #if PRO_VERSION
            return .appcenter
        #else
            return .stable
        #endif
    }() {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: "AutoUpgardeManager.current")
        }
    }

    private var allowSelectChannel: Bool {
        return Bundle.main.object(forInfoDictionaryKey: "SUDisallowSelectChannel") as? Bool != true
    }

    // MARK: Public

    func setup() {
        controller = SPUStandardUpdaterController(updaterDelegate: self, userDriverDelegate: nil)
    }

    func setupCheckForUpdatesMenuItem(_ item: NSMenuItem) {
        checkForUpdatesMenuItem = item
        checkForUpdatesMenuItem?.target = controller
        checkForUpdatesMenuItem?.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    }

    func addChannelMenuItem(_ button: NSPopUpButton) {
        for channel in Channel.allCases {
            button.addItem(withTitle: channel.title)
            button.lastItem?.tag = channel.rawValue
        }
        button.target = self
        button.action = #selector(didselectChannel(sender:))
        button.selectItem(withTag: current.rawValue)
    }

    @objc func didselectChannel(sender: NSPopUpButton) {
        guard let tag = sender.selectedItem?.tag, let channel = Channel(rawValue: tag) else { return }
        current = channel
    }
}

extension AutoUpgardeManager: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard WebPortalManager.hasWebProtal == false, allowSelectChannel else { return nil }
        return current.urlString
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        SystemProxyManager.shared.disableProxy(port: 0, socksPort: 0, forceDisable: true)
    }
}

// MARK: - Channel Enum

extension AutoUpgardeManager {
    enum Channel: Int, CaseIterable {
        #if !PRO_VERSION
            case stable
            case prelease
        #endif
        case appcenter
    }
}

extension AutoUpgardeManager.Channel {
    var title: String {
        switch self {
        #if !PRO_VERSION
            case .stable:
                return NSLocalizedString("Stable", comment: "")
            case .prelease:
                return NSLocalizedString("Prelease", comment: "")
        #endif
        case .appcenter:
            return "Appcenter"
        }
    }

    var urlString: String {
        switch self {
        #if !PRO_VERSION
            case .stable:
                return "https://yichengchen.github.io/clashX/appcast.xml"
            case .prelease:
                return "https://yichengchen.github.io/clashX/appcast_pre.xml"
        #endif
        case .appcenter:
            #if PRO_VERSION
                return "https://api.appcenter.ms/v0.1/public/sparkle/apps/1cd052f7-e118-4d13-87fb-35176f9702c1"
            #else
                return "https://api.appcenter.ms/v0.1/public/sparkle/apps/dce6e9a3-b6e3-4fd2-9f2d-35c767a99663"
            #endif
        }
    }
}
