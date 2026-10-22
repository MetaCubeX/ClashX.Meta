//
//  DebugSettingViewController.swift
//  ClashX Pro
//
//  Created by yicheng on 2023/5/25.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import RxSwift

class DebugSettingViewController: NSViewController {
    @IBOutlet var useBuiltinApiButton: NSButton!
    @IBOutlet var revertProxyButton: NSButton!
    @IBOutlet var updateChannelPopButton: NSPopUpButton!
    var disposeBag = DisposeBag()
    override func viewDidLoad() {
        super.viewDidLoad()
        useBuiltinApiButton.state = Settings.builtInApiMode ? .on : .off
        revertProxyButton.state = Settings.disableRestoreProxy ? .off : .on
    }

    @IBAction func actionUnInstallProxyHelper(_ sender: Any) {
        Task { @MainActor in
            do {
                try await PrivilegedHelperManager.shared.removeInstallHelper()
            } catch PrivilegedHelperManager.HelperInstallationError.cancelled {
                return
            } catch {
                Logger.log("Remove helper failed: \(error.localizedDescription)", level: .error)
                NSAlert.alert(with: error.localizedDescription)
            }
        }
    }

    @IBAction func actionOpenLogFolder(_ sender: Any) {
        NSWorkspace.shared.openFilePath(Logger.shared.logFolder())
        if FileManager.default.fileExists(atPath: Logger.shared.coreLogFolder) {
            NSWorkspace.shared.openFilePath(Logger.shared.coreLogFolder)
        }
    }

    @IBAction func actionOpenLocalConfig(_ sender: Any) {
        NSWorkspace.shared.openFilePath(kConfigFolderPath)
    }

    @IBAction func actionOpenIcloudConfig(_ sender: Any) {
        if ICloudManager.shared.icloudAvailable {
            Task { @MainActor in
                guard let url = await ICloudManager.shared.getUrl() else { return }
                NSWorkspace.shared.open(url)
            }
        } else {
            NSAlert.alert(with: NSLocalizedString("iCloud not available", comment: ""))
        }
    }

    @IBAction func actionResetUserDefault(_ sender: Any) {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Reset User Defaults", comment: "")
        alert.informativeText = NSLocalizedString("This will remove all app settings and quit ClashX. Continue?", comment: "")
        let resetButton = alert.addButton(withTitle: NSLocalizedString("Reset", comment: ""))
        resetButton.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        ExitManager.shared.requestQuit(force: true)
    }

    @IBAction func actionSetUseApiMode(_ sender: Any) {
        let alert = NSAlert()
        alert.informativeText = NSLocalizedString("Need to Restart the ClashX to Take effect, Please start clashX manually", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Apply and Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            Settings.builtInApiMode = !Settings.builtInApiMode
            NSApp.terminate(nil)
        } else {
            useBuiltinApiButton.state = Settings.builtInApiMode ? .on : .off
        }
    }

    @IBAction func actionRevertProxy(_ sender: Any) {
        Settings.disableRestoreProxy.toggle()
        revertProxyButton.state = Settings.disableRestoreProxy ? .off : .on
    }

    @IBAction func actionOpenCrashLogFolder(_ sender: Any) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Logs/DiagnosticReports", isDirectory: true))
    }
}
