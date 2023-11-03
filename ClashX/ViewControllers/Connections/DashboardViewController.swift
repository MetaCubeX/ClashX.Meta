//
//  DashboardViewController.swift
//  ClashX
//
//  Created by yicheng on 2023/7/14.
//  Copyright © 2023 west2online. All rights reserved.
//

import Cocoa

enum DashboardContentType: Int, CaseIterable {
    case allConnection
    case activeConnection

    var title: String {
        switch self {
        case .allConnection:
            return NSLocalizedString("Recent Connections", comment: "")
        case .activeConnection:
            return NSLocalizedString("Active Connections", comment: "")
        }
    }
}

@available(macOS 10.15, *)
class DashboardViewController: NSViewController {
    private let toolbar = NSToolbar()
    private var segmentControl: NSSegmentedControl!
    private let searchField = NSSearchField()

    private let connectionVC = ConnectionsViewController()

    private var currentContentVC: DashboardSubViewControllerProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        segmentControl = NSSegmentedControl(labels: DashboardContentType.allCases.map(\.title),
                                            trackingMode: .selectOne,
                                            target: self,
                                            action: #selector(actionSwitchSegmentControl(sender:)))
        segmentControl.selectedSegment = 0
        searchField.delegate = self
        setCurrentVC(connectionVC)
    }

    override func loadView() {
        view = NSView()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        toolbar.delegate = self
        view.window?.toolbar = toolbar
        view.window?.backgroundColor = NSColor.clear
        if #available(macOS 11.0, *) {
            view.window?.toolbarStyle = .unifiedCompact
        } else {
            view.window?.toolbar?.sizeMode = .small
        }
    }

    func setCurrentVC(_ vc: DashboardSubViewControllerProtocol) {
        currentContentVC?.removeFromParent()
        currentContentVC?.view.removeFromSuperview()
        addChild(vc)
        view.addSubview(vc.view)
        vc.view.makeConstraintsToBindToSuperview()
        currentContentVC = vc
    }

    @objc func actionSwitchSegmentControl(sender: NSSegmentedControl) {
        guard let contentType = DashboardContentType(rawValue: sender.selectedSegment) else { return }
        switch contentType {
        case .allConnection:
            connectionVC.setActiveMode(enable: false)
        case .activeConnection:
            connectionVC.setActiveMode(enable: true)
        }
    }
}

@available(macOS 10.15, *)
extension DashboardViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            currentContentVC?.actionSearch(string: textField.stringValue)
        }
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        currentContentVC?.actionSearch(string: sender.stringValue)
    }
}

extension NSToolbarItem.Identifier {
    static let toolbarSearchItem = NSToolbarItem.Identifier("ToolbarSearchItem")
    static let toolbarSegmentItem = NSToolbarItem.Identifier("toolbarSegmentItem")
}

@available(macOS 10.15, *)
extension DashboardViewController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toolbarSegmentItem, .flexibleSpace, .toolbarSearchItem]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toolbarSegmentItem, .flexibleSpace, .toolbarSearchItem]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        if itemIdentifier == .toolbarSearchItem {
            item.maxSize = NSSize(width: 200, height: 40)
            searchField.sizeToFit()
            item.view = searchField
        } else if itemIdentifier == .toolbarSegmentItem {
            if #available(macOS 11.0, *) {
                item.isNavigational = true
            }
            item.minSize = CGSize(width: 300, height: 34)
            item.view = segmentControl
        }

        return item
    }
}
