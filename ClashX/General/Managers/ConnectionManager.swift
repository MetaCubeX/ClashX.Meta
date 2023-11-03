//
//  ConnectionManager.swift
//  ClashX
//
//  Created by yichengchen on 2019/10/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

enum ConnectionManager {
    static func closeConnection(for group: String) {
        ApiRequest.getConnections { conns in
            for conn in conns where conn.chains.contains(group) {
                ApiRequest.closeConnection(conn.id)
            }
        }
    }

    static func closeAllConnection() {
        ApiRequest.closeAllConnection()
    }
}
