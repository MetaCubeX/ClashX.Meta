//
//  StatusItemViewProtocol.swift
//  ClashX Pro
//
//  Created by yicheng on 2023/3/1.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit

protocol StatusItemViewProtocol: AnyObject {
    func updateViewStatus(enableProxy: Bool)
    func updateSpeedLabel(up: Int, down: Int)
    func showSpeedContainer(show: Bool)
    func updateSize(width: CGFloat)
}
