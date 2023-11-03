//
//  ConnectionLeftPannelView.swift
//  ClashX
//
//  Created by yicheng on 2023/7/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

private extension NSUserInterfaceItemIdentifier {
    static let mainColumn = NSUserInterfaceItemIdentifier("mainColumn")
    static let localApplication = NSUserInterfaceItemIdentifier("localApplication")
    static let remoteApplication = NSUserInterfaceItemIdentifier("remoteApplication")
    static let hosts = NSUserInterfaceItemIdentifier("hosts")
    static let all = NSUserInterfaceItemIdentifier("all")
}

@available(macOS 10.15, *)
class ConnectionLeftPannelView: NSView {
    let viewModel: ConnectionLeftPannelViewModel
    let columnIdentifier = NSUserInterfaceItemIdentifier(rawValue: "column")
    let effectView = NSVisualEffectView()

    private let tableView: SectionedTableView = {
        let table = SectionedTableView()
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.backgroundColor = NSColor.clear
        table.allowsColumnSelection = false
        table.usesAutomaticRowHeights = true
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    init(viewModel: ConnectionLeftPannelViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        addSubview(effectView)
        effectView.makeConstraintsToBindToSuperview()

        let segmentControl = NSSegmentedControl(labels: [NSLocalizedString("Client", comment: ""), NSLocalizedString("Host", comment: "")],
                                                trackingMode: .selectOne,
                                                target: self,
                                                action: #selector(actionSelectSegment(sender:)))
        addSubview(segmentControl)
        segmentControl.makeConstraints { [
            $0.leftAnchor.constraint(equalTo: leftAnchor, constant: 12),
            $0.rightAnchor.constraint(equalTo: rightAnchor, constant: -12),
            $0.heightAnchor.constraint(equalToConstant: 20),
            $0.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        ] }
        segmentControl.selectedSegment = 0

        let v = NSScrollView()
        v.drawsBackground = false
        v.backgroundColor = .clear
        v.contentView.documentView = tableView
        addSubview(v)
        v.makeConstraints { [
            $0.leftAnchor.constraint(equalTo: leftAnchor),
            $0.rightAnchor.constraint(equalTo: rightAnchor),
            $0.bottomAnchor.constraint(equalTo: bottomAnchor),
            $0.topAnchor.constraint(equalTo: segmentControl.bottomAnchor, constant: 2)
        ] }
        v.hasHorizontalScroller = false

        let column = NSTableColumn(identifier: .mainColumn)
        column.minWidth = 60
        column.maxWidth = .greatestFiniteMagnitude
        tableView.addTableColumn(column)
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.sectionDatasource = self
        tableView.allowsEmptySelection = false
        tableView.sizeLastColumnToFit()
        tableView.reloadData()

        viewModel.onReloadTable = { [weak self] in
            guard let self else { return }
            tableView.reloadData()
            tableView.selectRow(at: $0)
        }
    }

    @objc func actionSelectSegment(sender: NSSegmentedControl?) {
        viewModel.setHostMode(enable: sender?.selectedSegment == 1)
    }
}

// MARK: - section map to cell logic.

@available(macOS 10.15, *)
private extension ConnectionLeftPannelView {
    func getIdentifier(section: Int) -> NSUserInterfaceItemIdentifier {
        var identifier = NSUserInterfaceItemIdentifier("")
        switch viewModel.currentSections[section] {
        case .local:
            identifier = .localApplication
        case .remote:
            identifier = .remoteApplication
        case .hosts:
            identifier = .hosts
        case .all:
            identifier = .all
        }
        return identifier
    }
}

@available(macOS 10.15, *)
extension ConnectionLeftPannelView: TableViewSectionDataSource {
    func numberOfSectionsInTableView(tableView: NSTableView) -> Int {
        return viewModel.currentSections.count
    }

    func tableView(tableView: NSTableView, numberOfRowsInSection section: Int) -> Int {
        switch viewModel.currentSections[section] {
        case .local:
            return viewModel.localApplications.count
        case .remote:
            return viewModel.sources.count
        case .hosts:
            return viewModel.hosts.count
        case .all:
            return 1
        }
    }

    func tableView(tableView: NSTableView, viewForHeaderInSection section: Int) -> NSView? {
        switch viewModel.currentSections[section] {
        case .local:
            let sectionView = ApplicationClientSectionCell()
            sectionView.setup(with: NSLocalizedString("Local Clients", comment: ""))
            return sectionView
        case .remote:
            let sectionView = ApplicationClientSectionCell()
            sectionView.setup(with: NSLocalizedString("Sources", comment: ""))
            return sectionView
        case .all:
            let sectionView = ApplicationClientSectionCell()
            sectionView.setup(with: NSLocalizedString("Requests", comment: ""))
            return sectionView
        case .hosts:
            let sectionView = ApplicationClientSectionCell()
            sectionView.setup(with: NSLocalizedString("Hosts", comment: ""))
            return sectionView
        }
    }

    func tableView(tableView: NSTableView, viewForRowAt indexPath: IndexPath, column: NSTableColumn) -> NSView? {
        let type = viewModel.currentSections[indexPath.section]
        let identifier = getIdentifier(section: indexPath.section)
        var view = tableView.makeView(withIdentifier: identifier, owner: self)
        if view == nil {
            switch type {
            case .local:
                view = ConnectionApplicationCellView()
            case .remote, .all, .hosts:
                view = ConnectionLeftTextCellView()
            }
            view?.identifier = identifier
        }

        switch type {
        case .local:
            (view as! ConnectionApplicationCellView).setup(with: viewModel.localApplications[indexPath.item])
        case .remote:
            (view as! ConnectionLeftTextCellView).setup(with: viewModel.sources[indexPath.item])
        case .all:
            (view as! ConnectionLeftTextCellView).setup(with: viewModel.isHostMode ? NSLocalizedString("All Hosts", comment: "") : NSLocalizedString("All Clients", comment: ""))
        case .hosts:
            (view as! ConnectionLeftTextCellView).setup(with: viewModel.hosts[indexPath.item])
        }
        return view
    }

    func tableView(tableView: NSTableView, didSelectRowAtIndexPath indexPath: IndexPath) {
        viewModel.setSelect(indexPath: indexPath)
    }

    func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 36
    }
}
