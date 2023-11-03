//
//  ConnectionColume.swift
//  ClashX
//
//  Created by yicheng on 2023/7/6.
//  Copyright © 2023 west2online. All rights reserved.
//

enum ConnectionFilter {
    case application(path: String)
    case source(ip: String)
    case hosts(name: String)
}

@available(macOS 10.15, *)
enum ConnectionColume: String, CaseIterable {
    case statusIcon
    case process
    case status
    case date
    case url
    case rule
    case currentUpload
    case currentDownload
    case upload
    case download
    case type

    var columeTitle: String {
        switch self {
        case .statusIcon: return ""
        case .process: return NSLocalizedString("Client", comment: "")
        case .status: return NSLocalizedString("Status", comment: "")
        case .rule: return NSLocalizedString("Rule", comment: "")
        case .url: return NSLocalizedString("Host", comment: "")
        case .date: return NSLocalizedString("Date", comment: "")
        case .upload: return NSLocalizedString("Upload", comment: "")
        case .download: return NSLocalizedString("Download", comment: "")
        case .currentUpload: return NSLocalizedString("Upload speed", comment: "")
        case .currentDownload: return NSLocalizedString("Download speed", comment: "")
        case .type: return NSLocalizedString("Type", comment: "")
        }
    }

    var compareKeyPath: String? {
        switch self {
        case .statusIcon, .status: return "status"
        case .process: return "metadata.processName"
        case .rule: return "rule"
        case .url: return "metadata.displayHost"
        case .date: return "start"
        case .upload: return "upload"
        case .download: return "download"
        case .currentUpload: return "uploadSpeed"
        case .currentDownload: return "downloadSpeed"
        case .type: return "metadata.network"
        }
    }

    static func isDynamicSort(for keypath: String) -> Bool {
        return keypath == "upload" || keypath == "download" || keypath == "uploadSpeed" || keypath == "downloadSpeed" || keypath == "done"
    }

    var minWidth: CGFloat {
        switch self {
        case .statusIcon: return 16
        case .status: return 30
        default: return 60
        }
    }

    var width: CGFloat {
        switch self {
        case .upload, .download, .currentUpload, .currentDownload: return 80
        case .status: return 50
        default: return 100
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .statusIcon: return 16
        default: return CGFloat.greatestFiniteMagnitude
        }
    }
}
