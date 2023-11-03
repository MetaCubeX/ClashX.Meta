//
//  ConnectionTopListView.swift
//  ClashX
//
//  Created by yicheng on 2023/7/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

@available(macOS 10.15, *)
class ConnectionTopListView: NSView {
    private let viewModel: ConnectionTopListViewModel

    private let tableView: NSTableView = {
        let table = NSTableView()
        table.allowsColumnSelection = false
        return table
    }()

    let closeConnectionMenuItem = NSMenuItem()

    init(viewModel: ConnectionTopListViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        let v = NSScrollView()
        v.contentView.documentView = tableView
        addSubview(v)
        v.makeConstraintsToBindToSuperview()
        v.hasVerticalScroller = true
        v.hasHorizontalScroller = true

        for columnType in ConnectionColume.allCases {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: columnType.rawValue))
            column.title = columnType.columeTitle
            column.minWidth = columnType.minWidth
            column.maxWidth = columnType.maxWidth
            column.width = columnType.width
            column.sortDescriptorPrototype = viewModel.sortSortDescriptor(for: columnType)
            tableView.addTableColumn(column)
        }
        tableView.autosaveName = className.appending("tableAutoSave")
        tableView.autosaveTableColumns = true
        tableView.sortDescriptors = [viewModel.currentSortDescriptor].compactMap { $0 }
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.sizeLastColumnToFit()
        tableView.reloadData()
        closeConnectionMenuItem.title = NSLocalizedString("Close Connection", comment: "")
        closeConnectionMenuItem.target = self
        closeConnectionMenuItem.action = #selector(actionCloseConnection)
        tableView.menu = NSMenu()
        tableView.menu?.autoenablesItems = false
        tableView.menu?.addItem(closeConnectionMenuItem)
        tableView.menu?.delegate = self

        viewModel.onReloadTable = { [weak self] in
            guard let self else { return }
            tableView.reloadData()
            tableView.selectRowIndexes(viewModel.currentSelection(), byExtendingSelection: false)
        }
    }

    @objc func actionCloseConnection() {
        if tableView.selectedRowIndexes.contains(tableView.clickedRow) {
            viewModel.closeConnection(for: tableView.selectedRowIndexes)
        } else {
            viewModel.closeConnection(for: [tableView.clickedRow])
        }
    }
}

@available(macOS 10.15, *)
extension ConnectionTopListView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        closeConnectionMenuItem.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }
}

@available(macOS 10.15, *)
extension ConnectionTopListView: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        viewModel.setSelect(row: tableView.selectedRowIndexes)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        viewModel.currentSortDescriptor = tableView.sortDescriptors.first
        tableView.sortDescriptors = [viewModel.currentSortDescriptor].compactMap { $0 }
    }
}

@available(macOS 10.15, *)
extension ConnectionTopListView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return viewModel.connections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let type = ConnectionColume(rawValue: tableColumn.identifier.rawValue) else { return nil }
        var view = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? ConnectionCellProtocol
        if view == nil {
            switch type {
            case .process:
                view = ConnectionProxyClientCellView()
            case .statusIcon:
                view = ConnectionStatusIconCellView()
            default:
                view = ConnectionTextCellView()
            }
            view?.identifier = tableColumn.identifier
        }
        let c = viewModel.connections[row]
        view?.setup(with: c, type: type)
        return view
    }
}
