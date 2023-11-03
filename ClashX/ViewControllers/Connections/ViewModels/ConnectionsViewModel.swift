//
//  ConnectionsViewModel.swift
//  ClashX
//
//  Created by yicheng on 2023/7/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Combine
import Foundation

struct ConnectionApplication {
    let pid: String
    let image: NSImage?
    let name: String?
    let path: String?
}

@available(macOS 10.15, *)
class ConnectionsViewModel {
    @Published private(set) var applicationMap = [String: ConnectionApplication]()
    @Published private(set) var connections = [String: ClashConnectionSnapShot.Connection]()
    @Published var selectedConnection: ClashConnectionSnapShot.Connection? {
        didSet {
            showBottomView = selectedConnection != nil
        }
    }

    @Published private(set) var sourceIPs = Set<String>()
    @Published private(set) var hosts = Set<String>()
    @Published var showBottomView = false
    let connectionDataDidRefresh = PassthroughSubject<Void, Never>()
    var activeOnlyMode = false {
        didSet {
            if activeOnlyMode, let currentSnapShot {
                updateForActiveMode(snapShot: currentSnapShot)
            }
        }
    }

    private let unknownApplicationPlaceHolder = ConnectionApplication(pid: "-1", image: nil, name: NSLocalizedString("Unknown", comment: ""), path: "")

    private var cancellable = Set<AnyCancellable>()
    private(set) var currentApplications = [ConnectionApplication]()
    private(set) var currentSourceIPs = [String]()
    private(set) var currentHosts = [String]()
    private(set) var currentConnections = [ClashConnectionSnapShot.Connection]()
    private var currentSnapShot: ClashConnectionSnapShot?
    private let req = ConnectionsReq()
    private let logReq = StructedLogReq()
    private var verifyConnList = [LogConn]()
    init() {
        req.connect()
        logReq.connect()
        req.onSnapshotUpdate = {
            [weak self] snap in
            self?.update(snapShot: snap)
        }
        logReq.onLogUpdate.compactMap { $0.convertToConn() }.sink { [weak self] conn in
            self?.verifyConnList.append(conn)
        }.store(in: &cancellable)
    }

    func update(snapShot: ClashConnectionSnapShot) {
        currentSnapShot = snapShot
        defer {
            connectionDataDidRefresh.send()
        }
        let keys = Set(snapShot.connections.map(\.id))
        for key in connections.keys where !keys.contains(key) {
            if let conn = connections[key] {
                if conn.status == .connecting {
                    conn.status = .finished
                }
                conn.uploadSpeed = 0
                conn.downloadSpeed = 0
            }
        }
        let lAddrs = Set(snapShot.connections.map { $0.metadata.sourceIP.appending(":").appending($0.metadata.sourcePort) })

        for logCon in verifyConnList where !lAddrs.contains(logCon.localAddr) {
            snapShot.connections.append(logCon.toConn())
        }
        var processMap: [String: String]?
        for conn in snapShot.connections {
            if let oldConn = connections[conn.id] {
                oldConn.uploadSpeed = conn.upload - oldConn.upload
                oldConn.downloadSpeed = conn.download - oldConn.download
                oldConn.upload = conn.upload
                oldConn.download = conn.download
            } else {
                if processMap == nil {
                    processMap = getProcessList()
                }
                let key = conn.metadata.sourceIP.appending(conn.metadata.sourcePort)
                if let pid = processMap![key],
                   let info = getProgressInfo(pid: pid) {
                    conn.metadata.pid = pid
                    conn.metadata.processPath = info.path ?? ""
                    conn.metadata.processName = info.name
                    conn.metadata.processImage = info.image
                } else if !conn.metadata.processPath.isEmpty {
                    conn.metadata.processName = conn.metadata.processPath.components(separatedBy: "/").last
                    conn.metadata.processImage = NSWorkspace.shared.icon(forFile: conn.metadata.processPath)
                } else {
                    if applicationMap["-1"] == nil {
                        applicationMap["-1"] = unknownApplicationPlaceHolder
                    }
                    conn.metadata.pid = unknownApplicationPlaceHolder.pid
                    conn.metadata.processName = unknownApplicationPlaceHolder.name
                }

                connections[conn.id] = conn
                if !sourceIPs.contains(conn.metadata.sourceIP) {
                    sourceIPs.insert(conn.metadata.sourceIP)
                }
                if !hosts.contains(conn.metadata.displayHost) {
                    hosts.insert(conn.metadata.displayHost)
                }
            }
        }

        if activeOnlyMode {
            updateForActiveMode(snapShot: snapShot)
        }

        verifyConnList.removeAll()
    }

    private func updateForActiveMode(snapShot: ClashConnectionSnapShot) {
        currentConnections = snapShot.connections.compactMap { [weak self] in self?.connections[$0.id] }
        currentHosts = Array(Set(currentConnections.map(\.metadata.displayHost)))
        currentSourceIPs = Array(Set(currentConnections.map(\.metadata.sourceIP)))
        currentApplications = Array(Set(currentConnections.compactMap(\.metadata.pid)).compactMap { [weak self] in self?.applicationMap[$0] })
    }

    private func getProcessList() -> [String: String] {
        let tableString: String = clash_getProggressInfo().toString().trimmingCharacters(in: .whitespacesAndNewlines)
        if tableString.isEmpty { return [:] }
        let processList = tableString.components(separatedBy: "\n")
        var map = [String: String]()
        for process in processList {
            let infos = process.components(separatedBy: " ")
            // fmt.Sprintf("%s %d %d\n", srcIP, srcPort, pid)
            let srcIp = infos[0]
            let srcPort = infos[1]
            let pid = infos[2]
            map[srcIp.appending(srcPort)] = pid
        }
        return map
    }

    private func getProcessPath(pid: Int32) -> String? {
        let pathBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
        defer {
            pathBuffer.deallocate()
        }
        let pathLength = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            return path
        }
        return nil
    }

    private func getProgressInfo(pid: String) -> ConnectionApplication? {
        if let info = applicationMap[pid] {
            return info
        }
        guard let pidValue = Int32(pid) else { return nil }

        if let application = NSRunningApplication(processIdentifier: pidValue) {
            let info = ConnectionApplication(pid: pid,
                                             image: application.icon,
                                             name: application.localizedName,
                                             path: application.executableURL?.absoluteString)
            applicationMap[pid] = info
            return info
        }

        guard let path = getProcessPath(pid: pidValue) else { return nil }
        let info = ConnectionApplication(pid: pid,
                                         image: NSWorkspace.shared.icon(forFile: path),
                                         name: path.components(separatedBy: "/").last,
                                         path: path)
        applicationMap[pid] = info
        return info
    }
}
