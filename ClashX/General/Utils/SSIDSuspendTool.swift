//
//  SSIDSuspendTool.swift
//  ClashX Pro
//
//  Created by yicheng on 2023/5/24.
//  Copyright © 2023 west2online. All rights reserved.
//

import CoreLocation
import CoreWLAN
import Foundation
import RxCocoa
import RxSwift

class SSIDSuspendTool: NSObject {
    static let shared = SSIDSuspendTool()
    private var ssidChangePublisher = PublishSubject<String>()
    private var disposeBag = DisposeBag()
    private lazy var locationManager = CLLocationManager()

    var showNoticeOnNotPermission = false

    func setup() {
        if AppVersionUtil.hasVersionChanged {
            showNoticeOnNotPermission = true
        }
        requestPermissionIfNeed()
        do {
            try CWWiFiClient.shared().startMonitoringEvent(with: .ssidDidChange)
            CWWiFiClient.shared().delegate = self
            ssidChangePublisher
                .observe(on: MainScheduler.instance)
                .debounce(.seconds(1), scheduler: MainScheduler.instance)
                .delay(.seconds(1), scheduler: MainScheduler.instance)
                .bind { [weak self] _ in
                    self?.update()
                }.disposed(by: disposeBag)
        } catch let err {
            Logger.log(String(describing: err), level: .warning)
            NotificationCenter
                .default
                .rx
                .notification(.systemNetworkStatusDidChange)
                .observe(on: MainScheduler.instance)
                .delay(.seconds(2), scheduler: MainScheduler.instance)
                .bind { [weak self] _ in
                    self?.update()
                }.disposed(by: disposeBag)
        }
        ConfigManager.shared
            .proxyShouldPaused
            .asObservable()
            .distinctUntilChanged()
            .filter { _ in ConfigManager.shared.proxyPortAutoSet }
            .bind { pause in
                if pause {
                    SystemProxyManager.shared.disableProxy()
                } else {
                    SystemProxyManager.shared.enableProxy()
                }
            }.disposed(by: disposeBag)

        update()
    }

    func requestPermissionIfNeed() {
        defer {
            showNoticeOnNotPermission = false
        }
        if #available(macOS 14, *) {
            if Settings.disableSSIDList.isEmpty { return }
            if locationManager.authorizationStatus == .notDetermined {
                Logger.log("request location permission")
                locationManager.desiredAccuracy = kCLLocationAccuracyReduced
                locationManager.delegate = self
                locationManager.requestAlwaysAuthorization()
            } else if locationManager.authorizationStatus != .authorized {
                if showNoticeOnNotPermission {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.openLocationSettings()
                    }
                }
            }
        }
    }

    func update() {
        if shouldSuspend() {
            ConfigManager.shared.proxyShouldPaused.accept(true)
        } else {
            ConfigManager.shared.proxyShouldPaused.accept(false)
        }
    }

    func shouldSuspend() -> Bool {
        if let currentSSID = getCurrentSSID() {
            return Settings.disableSSIDList.contains(currentSSID)
        } else {
            return false
        }
    }

    private func getCurrentSSID() -> String? {
        if #available(macOS 14, *) {
            if locationManager.authorizationStatus != .authorized {
                let info = Command(cmd: "/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport", args: ["-I"]).run()
                let ssid = info.components(separatedBy: "\n")
                    .lazy
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { $0.starts(with: "SSID:") }?
                    .components(separatedBy: ":")
                    .last?.trimmingCharacters(in: .whitespacesAndNewlines)
                return ssid
            }
        }
        return CWWiFiClient.shared().interface()?.ssid()
    }

    private func openLocationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Location")!)
        NSApp.activate(ignoringOtherApps: true)
        NSAlert.alert(with: NSLocalizedString("Please enable the location service for ClashX to detect your current WiFi network's SSID name and provide the auto-suspend services.", comment: ""))
    }
}

extension SSIDSuspendTool: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Logger.log("Location status: \(status.rawValue)")
        if status != .authorized, showNoticeOnNotPermission {
            openLocationSettings()
        }
        showNoticeOnNotPermission = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension SSIDSuspendTool: CWEventDelegate {
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        ssidChangePublisher.onNext(interfaceName)
    }
}
