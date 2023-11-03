//
//  ConnectionCellProtocol.swift
//  ClashX
//
//  Created by yicheng on 2023/7/6.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

@available(macOS 10.15, *)
protocol ConnectionCellProtocol: NSView {
    func setup(with connection: ClashConnectionSnapShot.Connection, type: ConnectionColume)
}
