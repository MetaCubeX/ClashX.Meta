//
//  UpdateConfigCommand.swift
//  ClashX Meta
//
//  Created by magicdawn on 2024/11/21.
//  Copyright © 2024 west2online. All rights reserved.
//

import Foundation
import AppKit

@objc class UpdateConfigCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else {
            scriptErrorNumber = -2
            scriptErrorString = "can't get application, try again later"
            return nil
        }
				delegate.actionUpdateConfig(self)
        return nil
    }
}
