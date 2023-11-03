//
//  ConnectionTopListViewModel.swift
//  ClashX
//
//  Created by yicheng on 2023/7/8.
//  Copyright © 2023 west2online. All rights reserved.
//

import Combine

@available(macOS 10.15, *)
class ConnectionTopListViewModel {
    private var fullConnections = [ClashConnectionSnapShot.Connection]()
    private(set) var connections = [ClashConnectionSnapShot.Connection]()
    private var selectedUUIDs = [String]()
    private var updateDebounceDate = Date()

    var onReloadTable: (() -> Void)?
    var onSelectedConnection: ((ClashConnectionSnapShot.Connection?) -> Void)?
    var applicationFilter: ConnectionFilter? {
        didSet {
            updateData()
        }
    }

    var textFilter: String? {
        didSet {
            updateData()
        }
    }

    var currentSortDescriptor: NSSortDescriptor? {
        didSet {
            updateData()
        }
    }

    func accept(connections new: [ClashConnectionSnapShot.Connection]) {
        fullConnections = new
        updateData()
    }

    func connectionDidUpdate() {
        if let key = currentSortDescriptor?.key, ConnectionColume.isDynamicSort(for: key) {
            updateData(applyDebounce: true)
        }
    }

    func currentSelection() -> IndexSet {
        let indexs = selectedUUIDs.compactMap { uuid in connections.firstIndex(where: { $0.id == uuid }) }
        return IndexSet(indexs)
    }

    func closeConnection(for indexs: IndexSet) {
        for idx in indexs {
            let conn = connections[idx]
            ApiRequest.closeConnection(conn.id)
        }
    }

    private func updateData(applyDebounce: Bool = false) {
        let current = Date()
        if applyDebounce, current.timeIntervalSince(updateDebounceDate) < 0.2 {
            return
        }
        updateDebounceDate = current
        connections = fullConnections

        switch applicationFilter {
        case .none:
            break
        case let .application(pathOrPid):
            connections = connections.filter { conn in
                conn.metadata.processPath == pathOrPid || conn.metadata.pid == pathOrPid
            }

        case let .source(ip):
            connections = connections.filter { conn in
                conn.metadata.sourceIP == ip
            }
        case let .hosts(name):
            connections = connections.filter { conn in
                conn.metadata.displayHost == name
            }
        }

        if let textFilter = textFilter?.lowercased(), !textFilter.isEmpty {
            connections = connections.filter { conn in
                conn.metadata.displayHost.contains(textFilter) ||
                    conn.metadata.network.contains(textFilter) ||
                    conn.chains.joined().lowercased().contains(textFilter) ||
                    conn.metadata.processName?.lowercased().contains(textFilter) ?? false ||
                    conn.rule.lowercased().contains(textFilter)
            }
        }

        connections = (connections as NSArray).sortedArray(using: [currentSortDescriptor].compactMap { $0 }) as! [ClashConnectionSnapShot.Connection]
        onReloadTable?()
    }

    func setSelect(row: IndexSet) {
        selectedUUIDs = row.map { connections[$0].id }
        if selectedUUIDs.count == 1, let idx = row.first {
            onSelectedConnection?(connections[idx])
        } else {
            onSelectedConnection?(nil)
        }
    }

    func sortSortDescriptor(for columnType: ConnectionColume) -> NSSortDescriptor? {
        if let keypath = columnType.compareKeyPath {
            let sort = NSSortDescriptor(key: keypath, ascending: true)
            if columnType == .date {
                currentSortDescriptor = sort
            }
            return sort
        }
        return nil
    }
}
