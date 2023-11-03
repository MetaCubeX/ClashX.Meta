//
//  ConnectionDetailInfoGeneralView.swift
//  ClashX
//
//  Created by yicheng on 2023/7/8.
//  Copyright © 2023 west2online. All rights reserved.
//

import Cocoa

class ConnectionDetailInfoGeneralView: NSView, NibLoadable {
    @IBOutlet var entryLabel: NSTextField!
    @IBOutlet var networkTypeLabel: NSTextField!
    @IBOutlet var totalUploadLabel: NSTextField!
    @IBOutlet var totalDownloadLabel: NSTextField!
    @IBOutlet var maxUploadLabel: NSTextField!
    @IBOutlet var maxDownloadLabel: NSTextField!
    @IBOutlet var currentUploadLabel: NSTextField!
    @IBOutlet var currentDownloadLabel: NSTextField!

    @IBOutlet var ruleLabel: NSTextField!
    @IBOutlet var proxyChainLabel: NSTextField!
    @IBOutlet var otherTextView: NSTextView!
    @IBOutlet var sourceIpLabel: NSTextField!
    @IBOutlet var destLabel: NSTextField!
    override func awakeFromNib() {
        super.awakeFromNib()
        otherTextView.backgroundColor = NSColor.clear
        otherTextView.font = NSFont.systemFont(ofSize: 10)
    }
}
