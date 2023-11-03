//
//  StructedLogReq.swift
//  ClashX
//
//  Created by yicheng on 2023/7/14.
//  Copyright © 2023 west2online. All rights reserved.
//

import Combine
import Foundation
import Starscream

class StructedLog: Codable {
    class Pairs: Codable {
        let key: String
        let value: String
    }

    let time: String
    let level: String
    let message: String
    let fields: [Pairs]

    func convertToConn() -> LogConn? {
        let isTCP = message.starts(with: "[TCP]")
        let isUDP = message.starts(with: "[UDP]")
        if isTCP || isUDP {
            let conn = LogConn()
            conn.network = isTCP ? "tcp" : "udp"
            for field in fields {
                switch field.key {
                case "lAddr":
                    conn.localAddr = field.value
                case "rAddr":
                    conn.remoteAddr = field.value
                case "mode":
                    conn.mode = field.value
                case "rule":
                    conn.rule = field.value
                case "proxy":
                    conn.proxy = field.value
                case "rulePayload":
                    conn.rulePayload = field.value
                case "error":
                    conn.error = field.value
                default:
                    break
                }
            }
            return conn
        }
        return nil
    }
}

class LogConn {
    let time = Date()
    var localAddr: String = ""
    var remoteAddr: String = ""
    var mode: String = ""
    var rule: String = ""
    var proxy: String = ""
    var rulePayload: String = ""
    var error: String = ""
    var network: String = ""

    @available(macOS 10.15, *)
    func toConn() -> ClashConnectionSnapShot.Connection {
        let sourceInfos = localAddr.split(separator: ":")
        let remoteInfos = remoteAddr.split(separator: ":")
        let metaData = ClashConnectionSnapShot.MetaData(network: network,
                                                        type: "log",
                                                        sourceIP: String(sourceInfos.first ?? ""),
                                                        destinationIP: String(remoteInfos.first ?? ""),
                                                        sourcePort: String(sourceInfos.last ?? ""),
                                                        destinationPort: String(remoteInfos.last ?? ""),
                                                        host: String(remoteInfos.first ?? ""),
                                                        dnsMode: "",
                                                        specialProxy: nil,
                                                        processPath: "")

        let conn = ClashConnectionSnapShot.Connection(id: UUID().uuidString, chains: [proxy], meta: metaData, upload: 0, download: 0, start: time, rule: rule, rulePayload: rulePayload)
        if !error.isEmpty {
            conn.status = .fail
            conn.error = error
        } else {
            conn.status = .finished
        }
        return conn
    }
}

@available(macOS 10.15, *)
class StructedLogReq: WebSocketDelegate {
    /*
        {"time":"22:44:32","level":"warn","message":"[TCP] dial failed",
        "fields":[{"key":"error","value":"dial tcp4 1.2.4.6:80: i/o timeout"},
                 {"key":"proxy","value":"Domestic"},
                 {"key":"lAddr","value":"127.0.0.1:49790"},
                 {"key":"rAddr","value":"1.2.4.6:80"},
                 {"key":"rule","value":"GeoIP"},
                 {"key":"rulePayload","value":"CN"}]
        }
        {"time":"22:42:09","level":"debug","message":"[TUN] hijack udp dns","fields":[{"key":"addr","value":"198.18.0.2:53"}]}
     */
    let logLevel = ClashLogLevel.info
    private var socket: WebSocket?

    let decoder = JSONDecoder()

    let onLogUpdate = PassthroughSubject<StructedLog, Never>()
    init(level: ClashLogLevel = .warning) {
        if let url = URL(string: ConfigManager.apiUrl.appending("/logs?format=structured&level=\(logLevel.rawValue)")) {
            socket = WebSocket(url: url)
        }
        for header in ApiRequest.authHeader() {
            socket?.request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        socket?.delegate = self
        decoder.dateDecodingStrategy = .formatted(DateFormatter.js)
    }

    func connect() {
        socket?.connect()
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        if let data = text.data(using: .utf8) {
            do {
                let info = try decoder.decode(StructedLog.self, from: data)
                onLogUpdate.send(info)
            } catch let err {
                Logger.log("decode fail: \(err)", level: .warning)
            }
        }
    }

    func websocketDidConnect(socket: Starscream.WebSocketClient) {
        Logger.log("websocketDidConnect")
    }

    func websocketDidDisconnect(socket: Starscream.WebSocketClient, error: Error?) {
        Logger.log("websocketDidDisconnect: \(String(describing: error))", level: .warning)
    }

    func websocketDidReceiveData(socket: Starscream.WebSocketClient, data: Data) {}
}
