//
//  ProxySettingCommand.swift
//  ClashXX
//
//  Created by Vince-hz on 2022/1/25.
//  Copyright © 2022 west2online. All rights reserved.
//

import AppKit
import Foundation

@objc class ProxySettingCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else {
            scriptErrorNumber = -2
            scriptErrorString = "can't get application, try again later"
            return nil
        }
        delegate.actionSetSystemProxy(self)
        return nil
    }
}
