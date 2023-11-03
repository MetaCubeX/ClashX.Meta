//
//  ConnectionLeftPannelViewModel.swift
//  ClashX
//
//  Created by miniLV on 2023-07-10.
//  Copyright © 2023 west2online. All rights reserved.
//

import Combine

@available(macOS 10.15, *)
class ConnectionLeftPannelViewModel {
    enum Section: Int, CaseIterable {
        case all
        case local
        case remote
        case hosts
    }

    private(set) var currentSections = [Section.all, Section.local, Section.remote]
    private(set) var localApplications = [ConnectionApplication]()
    private(set) var sources = [String]()
    private(set) var hosts = [String]()
    private(set) var isHostMode = false
    var onReloadTable: ((IndexPath) -> Void)?
    var onSelectedFilter: ((ConnectionFilter?) -> Void)?
    var selectedFilter: ConnectionFilter?

    func accept(connections new: [ConnectionApplication]) {
        var dupSet = Set<String>()
        localApplications = new.filter { dupSet.insert($0.path ?? $0.pid).inserted }
            .sorted(by: { $0.name ?? "" < $1.name ?? "" })
        if !isHostMode {
            onReloadTable?(getSelectedIndexPath())
        }
    }

    func accept(sources new: [String]) {
        sources = new.sorted()
        if !isHostMode {
            onReloadTable?(getSelectedIndexPath())
        }
    }

    func accept(hosts new: [String]) {
        hosts = new.sorted()
        if isHostMode {
            onReloadTable?(getSelectedIndexPath())
        }
    }

    func accept(apps: [ConnectionApplication], sources: [String], hosts: [String]) {
        var dupSet = Set<String>()
        localApplications = apps.filter { dupSet.insert($0.path ?? $0.pid).inserted }
            .sorted(by: { $0.name ?? "" < $1.name ?? "" })
        self.sources = sources.sorted()
        self.hosts = hosts.sorted()
        onReloadTable?(getSelectedIndexPath())
    }

    func setHostMode(enable: Bool) {
        isHostMode = enable
        selectedFilter = nil
        onSelectedFilter?(nil)
        currentSections = enable ? [.all, .hosts] : [.all, .local, .remote]
        onReloadTable?(getSelectedIndexPath())
    }

    func getSelectedIndexPath() -> IndexPath {
        switch selectedFilter {
        case .none:
            break
        case let .application(path):
            if let idx = localApplications.firstIndex(where: { ($0.path ?? $0.pid) == path }) {
                return IndexPath(item: idx, section: 1)
            }
        case let .source(ip):
            if let idx = sources.firstIndex(where: { $0 == ip }) {
                return IndexPath(item: idx, section: 2)
            }
        case let .hosts(name):
            if let idx = hosts.firstIndex(where: { $0 == name }) {
                return IndexPath(item: idx, section: 1)
            }
        }
        return IndexPath(item: 0, section: 0)
    }

    func setSelect(indexPath: IndexPath) {
        if indexPath.item < 0 || indexPath.section < 0 {
            selectedFilter = nil
            onSelectedFilter?(nil)
            return
        }

        let type = currentSections[indexPath.section]
        switch type {
        case Section.local:
            let app = localApplications[indexPath.item]
            selectedFilter = .application(path: app.path ?? app.pid)
        case Section.remote:
            selectedFilter = .source(ip: sources[indexPath.item])
        case .hosts:
            selectedFilter = .hosts(name: hosts[indexPath.item])
        case .all:
            selectedFilter = nil
        }
        onSelectedFilter?(selectedFilter)
    }
}
