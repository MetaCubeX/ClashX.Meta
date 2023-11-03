//
//  GlobalShortCutViewController.swift
//  ClashX Pro
//
//  Created by yicheng on 2023/5/26.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleSystemProxyMode = Self("shortCut.toggleSystemProxyMode")
    static let copyShellCommand = Self("shortCut.copyShellCommand")
    static let copyExternalShellCommand = Self("shortCut.copyExternalShellCommand")

    static let modeDirect = Self("shortCut.modeDirect")
    static let modeRule = Self("shortCut.modeRule")
    static let modeGlobal = Self("shortCut.modeGlobal")

    static let log = Self("shortCut.log")
    static let dashboard = Self("shortCut.dashboard")
    static let openMenu = Self("shortCut.openMenu")
    static let nativeDashboard = Self("shortCut.nativeDashboard")
}

enum KeyboardShortCutManager {
    static func setup() {
        KeyboardShortcuts.onKeyUp(for: .toggleSystemProxyMode) {
            AppDelegate.shared.actionSetSystemProxy(nil)
        }

        KeyboardShortcuts.onKeyUp(for: .copyShellCommand) {
            AppDelegate.shared.actionCopyExportCommand(AppDelegate.shared.copyExportCommandMenuItem)
        }

        KeyboardShortcuts.onKeyUp(for: .copyExternalShellCommand) {
            AppDelegate.shared.actionCopyExportCommand(AppDelegate.shared.copyExportCommandExternalMenuItem)
        }

        KeyboardShortcuts.onKeyUp(for: .modeDirect) {
            AppDelegate.shared.switchProxyMode(mode: .direct)
        }

        KeyboardShortcuts.onKeyUp(for: .modeRule) {
            AppDelegate.shared.switchProxyMode(mode: .rule)
        }

        KeyboardShortcuts.onKeyUp(for: .modeGlobal) {
            AppDelegate.shared.switchProxyMode(mode: .global)
        }

        KeyboardShortcuts.onKeyUp(for: .log) {
            AppDelegate.shared.actionShowLog(nil)
        }

        KeyboardShortcuts.onKeyUp(for: .dashboard) {
            AppDelegate.shared.actionDashboard(nil)
        }

        KeyboardShortcuts.onKeyUp(for: .openMenu) {
            AppDelegate.shared.statusItem.button?.performClick(nil)
        }
        if #available(macOS 10.15, *) {
            KeyboardShortcuts.onKeyUp(for: .nativeDashboard) {
                ClashWindowController<DashboardViewController>.create().showWindow(self)
            }
        }
    }
}

class GlobalShortCutViewController: NSViewController {
    @IBOutlet var proxyBox: NSBox!
    @IBOutlet var modeBoxView: NSView!
    @IBOutlet var otherBoxView: NSView!

    override func viewDidLoad() {
        super.viewDidLoad()
        let systemProxy = getRecoder(for: .toggleSystemProxyMode)
        let copyShellCommand = getRecoder(for: .copyShellCommand)
        let copyShellCommandExternal = getRecoder(for: .copyExternalShellCommand)
        addGridView(in: proxyBox.contentView!, with: [
            [NSTextField(labelWithString: NSLocalizedString("System Proxy", comment: "")), systemProxy],
            [NSTextField(labelWithString: NSLocalizedString("Copy Shell Command", comment: "")), copyShellCommand],
            [NSTextField(labelWithString: NSLocalizedString("Copy Shell Command (External)", comment: "")), copyShellCommandExternal]
        ])

        addGridView(in: modeBoxView, with: [
            [NSTextField(labelWithString: NSLocalizedString("Direct Mode", comment: "")), getRecoder(for: .modeDirect)],
            [NSTextField(labelWithString: NSLocalizedString("Rule Mode", comment: "")), getRecoder(for: .modeRule)],
            [NSTextField(labelWithString: NSLocalizedString("Global Mode", comment: "")), getRecoder(for: .modeGlobal)]
        ])

        var otherItems: [[NSView]] = [
            [NSTextField(labelWithString: NSLocalizedString("Open Menu", comment: "")), getRecoder(for: .openMenu)],
            [NSTextField(labelWithString: NSLocalizedString("Open Log", comment: "")), getRecoder(for: .log)],
            [NSTextField(labelWithString: NSLocalizedString("Open Dashboard", comment: "")), getRecoder(for: .dashboard)]
        ]
        if #available(macOS 10.15, *) {
            otherItems.append([NSTextField(labelWithString: NSLocalizedString("Open Connection Details", comment: "")), getRecoder(for: .nativeDashboard)])
        }
        addGridView(in: otherBoxView, with: otherItems)
    }

    private func getRecoder(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.RecorderCocoa {
        let view = KeyboardShortcuts.RecorderCocoa(for: name)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    private func addGridView(in superView: NSView, with views: [[NSView]]) {
        let gridView = NSGridView(views: views)
        gridView.rowSpacing = 10
        superView.addSubview(gridView)
        gridView.makeConstraintsToBindToSuperview(NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        gridView.setContentHuggingPriority(.required, for: .vertical)
        gridView.setContentCompressionResistancePriority(.required, for: .vertical)
        gridView.xPlacement = .trailing
        gridView.column(at: 0).xPlacement = .leading
    }
}
