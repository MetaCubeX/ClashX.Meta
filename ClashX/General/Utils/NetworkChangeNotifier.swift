//
//  NetworkChangeNotifier.swift
//  ClashX
//
//  Created by yicheng on 2019/10/15.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa
import CoreWLAN
import SystemConfiguration

class NetworkChangeNotifier {
    static func proxyChangeStream() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .systemNetworkStatusDidChange,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(())
            }

            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    static func ipAddressStream(allowIPV6: Bool = false) -> AsyncStream<String?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .systemNetworkStatusIPUpdate,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(getPrimaryIPAddress(allowIPV6: allowIPV6))
            }

            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: - SCDynamicStore via DispatchQueue (no CFRunLoopRun)

    private static let proxyQueue = DispatchQueue(label: "com.clashx.proxy.networknotification", qos: .utility)
    private static let ipQueue = DispatchQueue(label: "com.clashx.ipv4.networknotification", qos: .utility)
    private static var proxyStore: SCDynamicStore?
    private static var ipStore: SCDynamicStore?
    private static var proxyDebounceWork: DispatchWorkItem?
    private static var ipDebounceWork: DispatchWorkItem?
    // Verification counters
    private static var proxyRawCount = 0
    private static var proxyPostCount = 0
    private static var ipRawCount = 0
    private static var ipPostCount = 0

    static func start() {
        guard proxyStore == nil, ipStore == nil else { return }
        Logger.log("[Notifier] start proxy/ip stores (utility qos)", level: .info)
        let proxyCallback: SCDynamicStoreCallBack = { _, _, _ in
            NetworkChangeNotifier.handleProxyStoreChange()
        }
        if let store = SCDynamicStoreCreate(nil, "com.clashx.proxy.networknotification" as CFString, proxyCallback, nil) {
            SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Global/Proxies" as CFString] as CFArray)
            SCDynamicStoreSetDispatchQueue(store, proxyQueue)
            proxyStore = store
        } else {
            Logger.log("Failed to create SCDynamicStore for Proxies", level: .warning)
        }
        let ipCallback: SCDynamicStoreCallBack = { _, _, _ in
            NetworkChangeNotifier.handleIPStoreChange()
        }
        if let store = SCDynamicStoreCreate(nil, "com.clashx.ipv4.networknotification" as CFString, ipCallback, nil) {
            SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Global/IPv4" as CFString] as CFArray)
            SCDynamicStoreSetDispatchQueue(store, ipQueue)
            ipStore = store
        } else {
            Logger.log("Failed to create SCDynamicStore for IPv4", level: .warning)
        }
    }

    static func stop() {
        if let store = proxyStore {
            SCDynamicStoreSetNotificationKeys(store, nil, nil)
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        if let store = ipStore {
            SCDynamicStoreSetNotificationKeys(store, nil, nil)
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        proxyQueue.sync {
            proxyDebounceWork?.cancel()
            proxyDebounceWork = nil
        }
        ipQueue.sync {
            ipDebounceWork?.cancel()
            ipDebounceWork = nil
        }
        proxyStore = nil
        ipStore = nil
        Logger.log("[Notifier] stop", level: .info)
    }

    private static func handleProxyStoreChange() {
        // Already on proxyQueue via SCDynamicStoreSetDispatchQueue
        proxyRawCount += 1
        proxyDebounceWork?.cancel()
        var work: DispatchWorkItem!
        work = DispatchWorkItem {
            proxyPostCount += 1
            let coalesced = proxyRawCount - proxyPostCount
            if coalesced > 0 {
                Logger.log("[Notifier] proxy coalesced \(coalesced) raw=\(proxyRawCount) → POST #\(proxyPostCount)", level: .info)
            }
            NotificationCenter.default.post(name: .systemNetworkStatusDidChange, object: nil)
            if proxyDebounceWork === work { proxyDebounceWork = nil }
        }
        proxyDebounceWork = work
        proxyQueue.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
    }

    private static func handleIPStoreChange() {
        // Already on ipQueue
        ipRawCount += 1
        ipDebounceWork?.cancel()
        var work: DispatchWorkItem!
        work = DispatchWorkItem {
            ipPostCount += 1
            let coalesced = ipRawCount - ipPostCount
            if coalesced > 0 {
                Logger.log("[Notifier] ip coalesced \(coalesced) raw=\(ipRawCount) → POST #\(ipPostCount)", level: .info)
            }
            NotificationCenter.default.post(name: .systemNetworkStatusIPUpdate, object: nil)
            if ipDebounceWork === work { ipDebounceWork = nil }
        }
        ipDebounceWork = work
        ipQueue.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
    }

    @objc static func onWakeNote(note: NSNotification) {
        NotificationCenter.default.post(name: .systemNetworkStatusIPUpdate, object: nil)

        Task { @MainActor in
            try? await Task.sleep(seconds: 1)
            NotificationCenter.default.post(name: .systemNetworkStatusDidChange, object: nil)
        }
    }

    static func getRawProxySetting() -> [String: AnyObject] {
        return CFNetworkCopySystemProxySettings()?.takeRetainedValue() as! [String: AnyObject]
    }

    static func currentSystemProxySetting() -> (UInt, UInt, UInt) {
        let proxiesSetting = getRawProxySetting()
        let httpProxy = proxiesSetting[kCFNetworkProxiesHTTPPort as String] as? UInt ?? 0
        let socksProxy = proxiesSetting[kCFNetworkProxiesSOCKSPort as String] as? UInt ?? 0
        let httpsProxy = proxiesSetting[kCFNetworkProxiesHTTPSPort as String] as? UInt ?? 0
        return (httpProxy, httpsProxy, socksProxy)
    }

    static func isCurrentSystemSetToClash(looser: Bool = false) -> Bool {
        let (http, https, socks) = NetworkChangeNotifier.currentSystemProxySetting()
        let currentPort = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let currentSocks = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        if currentPort == currentSocks, currentPort == 0 {
            return false
        }
        if looser {
            return http == currentPort || https == currentPort || socks == currentSocks
        } else {
            return http == currentPort && https == currentPort && socks == currentSocks
        }
    }

    static func hasInterfaceProxySetToClash() -> Bool {
        let currentPort = ConfigManager.shared.currentConfig?.usedHttpPort
        let currentSocks = ConfigManager.shared.currentConfig?.usedSocksPort
        if let prefRef = SCPreferencesCreate(nil, "ClashX" as CFString, nil),
           let sets = SCPreferencesGetValue(prefRef, kSCPrefNetworkServices) {
            for key in sets.allKeys {
                let dict = sets[key] as? NSDictionary
                let proxySettings = dict?["Proxies"] as? [String: Any]
                if currentPort != nil {
                    if proxySettings?[kCFNetworkProxiesHTTPPort as String] as? Int == currentPort ||
                        proxySettings?[kCFNetworkProxiesHTTPSPort as String] as? Int == currentPort {
                        return true
                    }
                }
                if currentSocks != nil {
                    if proxySettings?[kCFNetworkProxiesSOCKSPort as String] as? Int == currentSocks {
                        return true
                    }
                }
            }
        }
        return false
    }

    static func getPrimaryInterface() -> String? {
        let store = SCDynamicStoreCreate(nil, "ClashX" as CFString, nil, nil)
        if store == nil {
            return nil
        }

        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)
        let dict = SCDynamicStoreCopyValue(store, key) as? [String: String]
        return dict?[kSCDynamicStorePropNetPrimaryInterface as String]
    }

    static func getPrimaryIsDhcp() -> Bool {
        let store = SCDynamicStoreCreate(nil, "ClashX" as CFString, nil, nil)
        if store == nil {
            return false
        }

        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)
        let dict = SCDynamicStoreCopyValue(store, key) as? [String: String]

        guard let serviceID = dict?[kSCDynamicStorePropNetPrimaryService as String] else { return false }
        let dhcpInfoKey = SCDynamicStoreKeyCreateNetworkServiceEntity(nil,
                                                                      kSCDynamicStoreDomainState,
                                                                      serviceID as CFString,
                                                                      kSCEntNetDHCP)
        let dhcpInfo = SCDynamicStoreCopyValue(store, dhcpInfoKey) as? [String: Any]
        return dhcpInfo != nil
    }

    static func getCurrentDns() -> [String] {
        let store = SCDynamicStoreCreate(nil, "ClashX" as CFString, nil, nil)
        if store == nil {
            return []
        }

        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetDNS)
        let dnsArr = SCDynamicStoreCopyValue(store, key) as? [String: Any]
        return (dnsArr?[kSCPropNetDNSServerAddresses as String] as? [String]) ?? []
    }

    static func getPrimaryIPAddress(allowIPV6: Bool = false) -> String? {
        guard let primary = getPrimaryInterface() else {
            return nil
        }

        var ipv6: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        defer {
            freeifaddrs(ifaddr)
        }
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    let name = String(cString: interface.ifa_name)
                    if name == primary {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr,
                                    socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname,
                                    socklen_t(hostname.count),
                                    nil,
                                    socklen_t(0),
                                    NI_NUMERICHOST)

                        let ip = String(cString: hostname)
                        if addrFamily == UInt8(AF_INET) {
                            return ip
                        } else {
                            ipv6 = "[\(ip)]"
                        }
                    }
                }
            }
        }
        return allowIPV6 ? ipv6 : nil
    }
}
