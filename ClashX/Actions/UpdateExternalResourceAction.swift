//
//  UpdateExternalResourceAction.swift
//  ClashX
//
//  Created by yicheng on 2023/9/4.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation
enum UpdateExternalResourceAction {
    static func run() {
        ApiRequest.requestExternalProviderNames { provider in
            let group = DispatchGroup()
            var successCount = 0
            let totalCount = provider.proxies.count + provider.rules.count
            if totalCount == 0 {
                onFinished(success: 0, total: 0, fails: [])
                return
            }
            var fails = [String]()
            for name in provider.proxies {
                group.enter()
                ApiRequest.updateProvider(name: name, type: .proxy) { success in
                    if success { successCount += 1 } else {
                        fails.append(name)
                    }
                    group.leave()
                }
            }

            for name in provider.rules {
                group.enter()
                ApiRequest.updateProvider(name: name, type: .rule) { success in
                    if success { successCount += 1 } else {
                        fails.append(name)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                onFinished(success: successCount, total: totalCount, fails: fails)
            }
        }
    }

    private static func onFinished(success: Int, total: Int, fails: [String]) {
        var info = String(format: NSLocalizedString("total: %d, success: %d", comment: ""), total, success)
        if !fails.isEmpty {
            info.append(String(format: NSLocalizedString("fails: %@", comment: ""), fails.joined(separator: " ")))
        }
        NSUserNotificationCenter.default.post(title: NSLocalizedString("Update external resource complete", comment: ""), info: info)
    }
}
