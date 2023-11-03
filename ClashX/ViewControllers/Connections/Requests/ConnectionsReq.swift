//
//  ConnectionsReq.swift
//  ClashX
//
//  Created by yicheng on 2023/7/14.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation
import Starscream

@available(macOS 10.15, *)
class ConnectionsReq: WebSocketDelegate {
    private var socket: WebSocket?

    let decoder = JSONDecoder()
    var onSnapshotUpdate: ((ClashConnectionSnapShot) -> Void)?
    init() {
        if let url = URL(string: ConfigManager.apiUrl.appending("/connections")) {
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
                let info = try decoder.decode(ClashConnectionSnapShot.self, from: data)
                onSnapshotUpdate?(info)
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
