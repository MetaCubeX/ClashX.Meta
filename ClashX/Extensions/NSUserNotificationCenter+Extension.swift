//
//  NSUserNotificationCenter+Extension.swift
//  ClashX
//
//  Created by CYC on 2018/8/6.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa
import UserNotifications

extension NSUserNotificationCenter {
    func post(title: String, info: String, identifier: String? = nil, notiOnly: Bool = true) {
        if #available(OSX 10.14, *) {
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.delegate = UserNotificationCenterDelegate.shared
            notificationCenter.getNotificationSettings {
                [weak self] settings in
                switch settings.authorizationStatus {
                case .denied:
                    guard !notiOnly else { return }
                    DispatchQueue.main.async {
                        self?.postNotificationAlert(title: title, info: info, identifier: identifier)
                    }
                case .authorized, .provisional:
                    DispatchQueue.main.async {
                        self?.postNotification(title: title, info: info, identifier: identifier)
                    }
                case .notDetermined:
                    notificationCenter.requestAuthorization(options: .alert) { granted, _ in
                        if granted {
                            DispatchQueue.main.async {
                                self?.postNotification(title: title, info: info, identifier: identifier)
                            }
                        } else {
                            guard !notiOnly else { return }
                            DispatchQueue.main.async {
                                self?.postNotificationAlert(title: title, info: info, identifier: identifier)
                            }
                        }
                    }
                @unknown default:
                    DispatchQueue.main.async {
                        self?.postNotification(title: title, info: info, identifier: identifier)
                    }
                }
            }
        } else {
            postNotification(title: title, info: info, identifier: identifier)
        }
    }

    private func postNotification(title: String, info: String, identifier: String? = nil) {
        var userInfo: [String: Any] = [:]
        if let identifier = identifier {
            userInfo = ["identifier": identifier]
        }
        if #available(OSX 10.14, *) {
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.delegate = UserNotificationCenterDelegate.shared
            notificationCenter.removeAllDeliveredNotifications()
            notificationCenter.removeAllPendingNotificationRequests()
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = info
            content.userInfo = userInfo
            let uuidString = UUID().uuidString
            let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: nil)
            notificationCenter.add(request) { error in
                if let err = error {
                    Logger.log("send noti fail: \(String(describing: err))")
                    DispatchQueue.main.async {
                        self.postNotificationAlert(title: title, info: info, identifier: identifier)
                    }
                }
            }
        } else {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = info
            notification.userInfo = userInfo
            delegate = UserNotificationCenterDelegate.shared
            deliver(notification)
        }
    }

    func postNotificationAlert(title: String, info: String, identifier: String? = nil) {
        if Settings.disableNoti {
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
        if let identifier = identifier {
            UserNotificationCenterDelegate.shared.handleNotificationActive(with: identifier)
        }
    }

    func postConfigFileChangeDetectionNotice() {
        post(title: NSLocalizedString("Config file have been changed", comment: ""),
             info: NSLocalizedString("Tap to reload config", comment: ""),
             identifier: "postConfigFileChangeDetectionNotice")
    }

    func postStreamApiConnectFail(api: String) {
        post(title: "\(api) api connect error!",
             info: NSLocalizedString("Use reload config to try reconnect.", comment: ""))
    }

    func postConfigErrorNotice(msg: String) {
        let configName = ConfigManager.selectConfigName.isEmpty ? "" :
            Paths.configFileName(for: ConfigManager.selectConfigName)

        let message = "\(configName): \(msg)"
        postNotificationAlert(title: NSLocalizedString("Config loading Fail!", comment: ""), info: message)
    }

    func postSpeedTestBeginNotice() {
        post(title: NSLocalizedString("Benchmark", comment: ""),
             info: NSLocalizedString("Benchmark has begun, please wait.", comment: ""))
    }

    func postSpeedTestingNotice() {
        post(title: NSLocalizedString("Benchmark", comment: ""),
             info: NSLocalizedString("Benchmark is processing, please wait.", comment: ""))
    }

    func postSpeedTestFinishNotice() {
        post(title: NSLocalizedString("Benchmark", comment: ""),
             info: NSLocalizedString("Benchmark Finished!", comment: ""), notiOnly: false)
    }

    func postProxyChangeByOtherAppNotice() {
        post(title: NSLocalizedString("System Proxy Changed", comment: ""),
             info: NSLocalizedString("Proxy settings are changed by another process. ClashX is no longer the default system proxy.", comment: ""), notiOnly: true)
    }
}

class UserNotificationCenterDelegate: NSObject, NSUserNotificationCenterDelegate, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationCenterDelegate()

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if let identifier = notification.userInfo?["identifier"] as? String {
            handleNotificationActive(with: identifier)
        }
        center.removeAllDeliveredNotifications()
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }

    @available(macOS 10.14, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let identifier = response.notification.request.content.userInfo["identifier"] as? String {
            handleNotificationActive(with: identifier)
        }
        center.removeAllDeliveredNotifications()
        completionHandler()
    }

    @available(macOS 10.14, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.alert)
    }

    func handleNotificationActive(with identifier: String) {
        switch identifier {
        case "postConfigFileChangeDetectionNotice":
            AppDelegate.shared.updateConfig()
        default:
            break
        }
    }
}
