//
//  TerminalCleanUpAction.swift
//  ClashX
//
//  Created by yicheng on 2023/9/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Foundation
import RxSwift

enum TerminalConfirmAction {
    static func run() -> NSApplication.TerminateReply {
        guard confirmAction() else {
            return .terminateCancel
        }
        let group = DispatchGroup()
        var shouldWait = false

        if ConfigManager.shared.proxyPortAutoSet && !ConfigManager.shared.isProxySetByOtherVariable.value || NetworkChangeNotifier.isCurrentSystemSetToClash(looser: true) ||
            NetworkChangeNotifier.hasInterfaceProxySetToClash() {
            Logger.log("ClashX quit need clean proxy setting")
            shouldWait = true
            group.enter()

            SystemProxyManager.shared.disableProxy(forceDisable: ConfigManager.shared.isProxySetByOtherVariable.value) {
                group.leave()
            }
        }

        if !shouldWait {
            Logger.log("ClashX quit without clean waiting")
            return .terminateNow
        }

        if let statusItem = AppDelegate.shared.statusItem, statusItem.menu != nil {
            statusItem.menu = nil
        }
        AppDelegate.shared.disposeBag = DisposeBag()

        DispatchQueue.global(qos: .default).async {
            let res = group.wait(timeout: .now() + 5)
            switch res {
            case .success:
                Logger.log("ClashX quit after clean up finish")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            case .timedOut:
                Logger.log("ClashX quit after clean up timeout")
                DispatchQueue.main.async {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }

        Logger.log("ClashX quit wait for clean up")
        return .terminateLater
    }

    static func confirmAction() -> Bool {
        if NSApp.activationPolicy() == .regular {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Quit ClashX?", comment: "")
            alert.informativeText = NSLocalizedString("The active connections will be interrupted.", comment: "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
            return alert.runModal() == .alertFirstButtonReturn
        }
        return true
    }
}
