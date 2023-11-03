//
//  ClashConnection.swift
//  ClashX
//
//  Created by yicheng on 2019/10/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

struct ClashConnectionBaseSnapShot: Codable {
    let connections: [Connection]
}

extension ClashConnectionBaseSnapShot {
    struct Connection: Codable {
        let id: String
        let chains: [String]
    }
}

@available(macOS 10.15, *)
class ClashConnectionSnapShot: Decodable {
    var connections: [Connection]
    let downloadTotal: Int
    let uploadTotal: Int
}

@available(macOS 10.15, *)
extension ClashConnectionSnapShot {
    class Connection: NSObject, Decodable {
        @objc enum ConnStatus: Int {
            case connecting
            case finished
            case fail

            var image: NSImage? {
                switch self {
                case .connecting: return NSImage(named: "icon_connection_inprogress")
                case .finished: return NSImage(named: "icon_connection_done")
                case .fail: return NSImage(named: "icon_connection_fail")
                }
            }

            var title: String {
                switch self {
                case .connecting: return NSLocalizedString("Connecting", comment: "")
                case .finished: return NSLocalizedString("Done", comment: "")
                case .fail: return NSLocalizedString("Fail", comment: "")
                }
            }
        }

        let id: String
        let chains: [String]
        @objc let metadata: MetaData
        @objc @Published var upload: Int
        @objc @Published var download: Int
        @objc let start: Date
        @objc let rule: String
        let rulePayload: String

        @objc @Published var status = ConnStatus.connecting
        @objc @Published var uploadSpeed = 0 {
            didSet {
                if uploadSpeed > maxUploadSpeed {
                    maxUploadSpeed = uploadSpeed
                }
            }
        }

        @objc @Published var downloadSpeed = 0 {
            didSet {
                if downloadSpeed > maxDownloadSpeed {
                    maxDownloadSpeed = downloadSpeed
                }
            }
        }

        @Published private(set) var maxUploadSpeed = 0
        @Published private(set) var maxDownloadSpeed = 0
        var error: String?

        enum CodingKeys: CodingKey {
            case id
            case chains
            case metadata
            case upload
            case download
            case start
            case rule
            case rulePayload
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            chains = try container.decode([String].self, forKey: .chains)
            metadata = try container.decode(MetaData.self, forKey: .metadata)
            upload = try container.decode(Int.self, forKey: .upload)
            download = try container.decode(Int.self, forKey: .download)
            start = try container.decode(Date.self, forKey: .start)
            rule = try container.decode(String.self, forKey: .rule)
            rulePayload = try container.decode(String.self, forKey: .rulePayload)
        }

        init(id: String, chains: [String], meta: MetaData, upload: Int, download: Int, start: Date, rule: String, rulePayload: String) {
            self.id = id
            self.chains = chains
            metadata = meta
            self.upload = upload
            self.download = download
            self.start = start
            self.rule = rule
            self.rulePayload = rulePayload
            super.init()
        }
    }

    //    {"network":"tcp","type":"HTTP Connect","sourceIP":"127.0.0.1","destinationIP":"124.72.132.104","sourcePort":"59217","destinationPort":"443","host":"slardar-bd.feishu.cn","dnsMode":"normal","processPath":"","specialProxy":""}
    class MetaData: NSObject, Codable {
        @objc let network: String
        @objc let type: String
        let sourceIP: String
        let destinationIP: String
        let sourcePort: String
        let destinationPort: String
        @objc let host: String
        let dnsMode: String
        let specialProxy: String?
        var processPath: String

        @objc var displayHost: String {
            if !host.isEmpty { return host }
            return destinationIP
        }

        var pid: String?
        var processImage: NSImage?

        @objc var processName: String?

        enum CodingKeys: CodingKey {
            case network
            case type
            case sourceIP
            case destinationIP
            case host
            case dnsMode
            case specialProxy
            case processPath
            case sourcePort
            case destinationPort
        }

        init(network: String, type: String, sourceIP: String, destinationIP: String, sourcePort: String, destinationPort: String, host: String, dnsMode: String, specialProxy: String?, processPath: String, pid: String? = nil, processImage: NSImage? = nil, processName: String? = nil) {
            self.network = network
            self.type = type
            self.sourceIP = sourceIP
            self.destinationIP = destinationIP
            self.sourcePort = sourcePort
            self.destinationPort = destinationPort
            self.host = host
            self.dnsMode = dnsMode
            self.specialProxy = specialProxy
            self.processPath = processPath
            self.pid = pid
            self.processImage = processImage
            self.processName = processName
            super.init()
        }
    }
}
