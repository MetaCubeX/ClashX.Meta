//
//  ConnectionDetailViewModel.swift
//  ClashX
//
//  Created by yicheng on 2023/7/8.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Combine

@available(macOS 10.15, *)
class ConnectionDetailViewModel {
    @Published var processName = ""
    @Published var processImage: NSImage?
    @Published var remoteHost = ""

    @Published var entry = ""
    @Published var networkType = ""
    @Published var totalUpload = ""
    @Published var totalDownload = ""
    @Published var maxUpload = ""
    @Published var maxDownload = ""
    @Published var currentUpload = ""
    @Published var currentDownload = ""
    @Published var rule = ""
    @Published var chain = ""
    @Published var sourceIP = ""
    @Published var destination = ""
    @Published var applicationPath: String? = ""
    @Published var otherText = ""
    @Published var showCloseButton = false

    private var uuid = ""
    var cancellable = Set<AnyCancellable>()

    func accept(connection: ClashConnectionSnapShot.Connection?) {
        cancellable.removeAll()
        guard let connection else { return }
        if let pid = connection.metadata.pid {
            processName = "\(connection.metadata.processName ?? NSLocalizedString("Unknown", comment: "")) (\(pid))"
        } else {
            processName = connection.metadata.processName ?? NSLocalizedString("Unknown", comment: "")
        }
        uuid = connection.id
        showCloseButton = connection.status == .connecting
        processImage = connection.metadata.processImage
        applicationPath = connection.metadata.processPath
        let area = clash_getCountryForIp(connection.metadata.destinationIP.goStringBuffer()).toString()
        let areaString = "\(flag(from: area))\(area)"
        if connection.metadata.host.isEmpty {
            remoteHost = "\(connection.metadata.destinationIP):\(connection.metadata.destinationPort) \(areaString)"
        } else {
            remoteHost = "\(connection.metadata.host):\(connection.metadata.destinationPort) \(areaString)"
        }

        entry = connection.metadata.type
        networkType = connection.metadata.network

        connection.$download.map { SpeedUtils.getNetString(for: $0) }.weakAssign(to: \.totalDownload, on: self).store(in: &cancellable)
        connection.$upload.map { SpeedUtils.getNetString(for: $0) }.weakAssign(to: \.totalUpload, on: self).store(in: &cancellable)

        connection.$maxUploadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.maxUpload, on: self).store(in: &cancellable)
        connection.$maxDownloadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.maxDownload, on: self).store(in: &cancellable)

        connection.$uploadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.currentUpload, on: self).store(in: &cancellable)
        connection.$downloadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.currentDownload, on: self).store(in: &cancellable)

        rule = connection.rule + "\n" + connection.rulePayload
        chain = connection.chains.joined(separator: "\n")
        sourceIP = connection.metadata.sourceIP.appending(":").appending(connection.metadata.sourcePort)
        destination = connection.metadata.destinationIP.appending(":").appending(connection.metadata.destinationPort)
        if let error = connection.error {
            otherText = error
        } else {
            otherText = ""
        }
    }

    func flag(from country: String) -> String {
        if country.isEmpty { return "" }
        let base: UInt32 = 127397
        var s = ""
        for v in country.uppercased().unicodeScalars {
            s.unicodeScalars.append(UnicodeScalar(base + v.value)!)
        }
        return s
    }

    func closeConnection() {
        ApiRequest.closeConnection(uuid)
    }
}
