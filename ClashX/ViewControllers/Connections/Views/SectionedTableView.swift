//
//  SectionedTableView.swift
//  ClashX
//
//  Created by yicheng on 2023/7/13.
//  Copyright © 2023 Marcin Krzyzanowski. All rights reserved.
//

import Cocoa

protocol TableViewSectionDataSource: NSObject {
    func numberOfSectionsInTableView(tableView: NSTableView) -> Int
    func tableView(tableView: NSTableView, numberOfRowsInSection section: Int) -> Int
    func tableView(tableView: NSTableView, viewForHeaderInSection section: Int) -> NSView?
    func tableView(tableView: NSTableView, viewForRowAt indexPath: IndexPath, column: NSTableColumn) -> NSView?
    func tableView(tableView: NSTableView, didSelectRowAtIndexPath indexPath: IndexPath)
    func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat
}

class SectionedTableView: NSTableView {
    weak var sectionDatasource: TableViewSectionDataSource?
    private var sectionHeaders = [Int: NSView]()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        dataSource = self
        delegate = self
    }

    override func reloadData() {
        for section in 0 ..< (sectionDatasource?.numberOfSectionsInTableView(tableView: self) ?? 0) {
            if let header = sectionDatasource?.tableView(tableView: self, viewForHeaderInSection: section) {
                sectionHeaders[section] = header
            }
        }
        super.reloadData()
    }

    private func sectionForRow(row: Int, counts: [Int]) -> (section: Int?, row: Int?) {
        var c = counts[0]
        for section in 0 ..< counts.count {
            if section > 0 {
                c += counts[section]
            }
            if (row >= c - counts[section]) && row < c {
                return (section: section, row: row - (c - counts[section]))
            }
        }
        return (section: nil, row: nil)
    }

    private func sectionForRow(row: Int) -> (section: Int, row: Int) {
        if let dataSource = sectionDatasource {
            let numberOfSections = dataSource.numberOfSectionsInTableView(tableView: self)
            var counts = [Int](repeating: 0, count: numberOfSections)

            for section in 0 ..< numberOfSections {
                counts[section] = dataSource.tableView(tableView: self, numberOfRowsInSection: section) + ((sectionHeaders[section] != nil) ? 1 : 0)
            }

            let result = sectionForRow(row: row, counts: counts)
            return (section: result.section ?? 0, row: result.row ?? 0)
        }

        assertionFailure("Invalid datasource")
        return (section: 0, row: 0)
    }

    func selectRow(at indexPath: IndexPath) {
        var count = 0
        for section in 0 ... indexPath.section {
            if sectionHeaders[section] != nil {
                count += 1
            }
            if section != indexPath.section {
                count += sectionDatasource?.tableView(tableView: self, numberOfRowsInSection: section) ?? 0
            }
        }
        count += indexPath.item

        selectRowIndexes(IndexSet(integer: count), byExtendingSelection: false)
    }
}

extension SectionedTableView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        var total = 0

        if let dataSource = sectionDatasource {
            for section in 0 ..< dataSource.numberOfSectionsInTableView(tableView: tableView) {
                total += dataSource.tableView(tableView: tableView, numberOfRowsInSection: section)
                if sectionHeaders[section] != nil {
                    total += 1
                }
            }
        }

        return total
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let dataSource = sectionDatasource, let tableColumn else { return nil }
        let (section, sectionRow) = sectionForRow(row: row)

        if let headerView = sectionHeaders[section] {
            if sectionRow == 0 {
                return headerView
            }
            return dataSource.tableView(tableView: tableView, viewForRowAt: IndexPath(item: sectionRow - 1, section: section), column: tableColumn)
        }
        return dataSource.tableView(tableView: tableView, viewForRowAt: IndexPath(item: sectionRow, section: section), column: tableColumn)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        let (_, sectionRow) = sectionForRow(row: row)
        if sectionRow == 0 {
            return false
        }
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let dataSource = sectionDatasource else { return }
        let (section, sectionRow) = sectionForRow(row: selectedRow)

        if sectionHeaders[section] != nil {
            if sectionRow == 0 {
                return
            }
            dataSource.tableView(tableView: self, didSelectRowAtIndexPath: IndexPath(item: sectionRow - 1, section: section))
            return
        }
        dataSource.tableView(tableView: self, didSelectRowAtIndexPath: IndexPath(item: sectionRow, section: section))
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return sectionDatasource?.tableView(tableView: tableView, heightOfRow: row) ?? 0
    }
}
