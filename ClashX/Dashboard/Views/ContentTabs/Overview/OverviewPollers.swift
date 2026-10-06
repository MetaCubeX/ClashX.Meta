//
//  OverviewPollers.swift
//  ClashX Dashboard
//
//  Per-domain polling objects so that a data update in one card
//  does NOT trigger re-renders in unrelated cards.
//

import SwiftUI

// MARK: - Subscription Usage (5s, 2 API calls)

@MainActor
final class SubscriptionPoller: ObservableObject {
    @Published var display: Display?

    struct Display: Equatable {
        let totalText: String
        let ratio: CGFloat
        let percentText: String
        let helpText: String
    }

    private var task: Task<Void, Never>?

    nonisolated init() {}

    deinit { task?.cancel() }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            for await _ in DashboardRefreshTicker.shared.ticks(every: Int(OverviewRefresh.polledInterval)) {
                await self?.refresh()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func refresh() async {
        let proxies = await ApiRequest.requestProxyGroupList()
        let providers = await ApiRequest.requestProxyProviderList()
        let newDisplay = Self.resolve(proxies: proxies, providers: providers)
        if newDisplay != display { display = newDisplay }
    }

    private static func resolve(proxies: ClashProxyResp, providers: ClashProviderResp) -> Display? {
        guard var name = proxies.proxiesMap["PROXY"]?.now else { return nil }
        var visited: Set<ClashProxyName> = [name]
        for _ in 0..<8 {
            guard let node = proxies.proxiesMap[name],
                  let next = node.now,
                  !visited.contains(next) else { break }
            visited.insert(next)
            name = next
        }
        guard let provider = providers.allProviders.values.first(where: {
            $0.type == .Proxy && $0.vehicleType == .HTTP && $0.proxies.contains { $0.name == name }
        }) else { return nil }
        guard let info = provider.subscriptionInfo,
              info.upload >= 0, info.download >= 0, info.total > 0 else { return nil }
        let used = info.upload + info.download
        guard used >= 0 else { return nil }

        let ratio = min(CGFloat(used) / CGFloat(info.total), 1)
        let percent = Int((Double(used) / Double(info.total) * 100).rounded())
        let totalText = ByteFormat.quota(info.total)
        let usedText = ByteFormat.quota(used)

        var helpParts: [String] = ["\(usedText) / \(totalText)"]
        if info.expire > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(info.expire)).formatted(date: .abbreviated, time: .omitted)
            helpParts.append(String(format: NSLocalizedString("Expire: %@", comment: ""), date))
        } else {
            helpParts.append(String(format: NSLocalizedString("Expire: %@", comment: ""), NSLocalizedString("none", comment: "")))
        }

        return Display(totalText: totalText, ratio: ratio,
                        percentText: String(format: "%d%%", percent),
                        helpText: helpParts.joined(separator: " · "))
    }
}

// MARK: - Network Status (5s, 1 API call)

@MainActor
final class NetworkStatusPoller: ObservableObject {
    @Published var tunActive = false
    @Published var tunDevice = ""
    @Published var httpPort = 0
    @Published var socksPort = 0
    @Published var systemProxyActive = false
    @Published var systemProxySetByOther = false
    @Published var apiAddress = "—"

    private var task: Task<Void, Never>?

    nonisolated init() {}

    deinit { task?.cancel() }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            for await _ in DashboardRefreshTicker.shared.ticks(every: Int(OverviewRefresh.polledInterval)) {
                await self?.refresh()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func refresh() async {
        let config = await ApiRequest.requestConfig()
        tunDevice = config?.tun.device ?? ""
        httpPort = config?.usedHttpPort ?? 0
        socksPort = config?.usedSocksPort ?? 0
        tunActive = ProxyManager.shared.runtimeTunActive
        let runtime = ProxyManager.shared.state.runtime
        systemProxySetByOther = runtime.systemProxySetByOther
        systemProxyActive = runtime.systemProxyActive
        apiAddress = ConfigManager.apiUrl
    }
}

// MARK: - Top Processes (1s, local computation from connsStorage)
@MainActor
final class TopAppsPoller: ObservableObject {
    @Published var topApps: [TopApp] = []

    struct TopApp: Identifiable {
        let name: String
        let bytes: Int64
        let ratio: CGFloat
        var id: String { name }
    }

    private var connsStorage: ClashConnsStorage?
    private var task: Task<Void, Never>?

    nonisolated init() {}

    deinit { task?.cancel() }

    func start(connsStorage: ClashConnsStorage) {
        guard task == nil else { return }
        self.connsStorage = connsStorage
        task = Task { [weak self] in
            for await _ in DashboardRefreshTicker.shared.ticks(every: Int(OverviewRefresh.streamInterval)) {
                await self?.refresh()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func refresh() async {
        guard let connsStorage else { return }
        let conns = connsStorage.conns + connsStorage.closedConns
        var totals: [String: Int64] = [:]
        let resolver = DashboardManager.shared.appNameResolver
        for conn in conns {
            guard conn.metadata.type != "Inner", !conn.chains.contains("DIRECT") else { continue }
            let name = await resolver.appName(processPath: conn.metadata.processPath, process: conn.metadata.process)
            totals[name, default: 0] += conn.upload + conn.download
        }
        let sorted = totals.sorted { $0.value > $1.value }.prefix(5)
        guard let maxBytes = sorted.first?.value, maxBytes > 0 else {
            topApps = []
            return
        }
        topApps = sorted.map { TopApp(name: $0.key, bytes: $0.value, ratio: CGFloat($0.value) / CGFloat(maxBytes)) }
    }
}

// MARK: - Connections Stats (1s, local computation from connsStorage)

@MainActor
final class ConnectionsStatsPoller: ObservableObject {
    @Published var statsString = "TCP 0 · UDP 0"
    @Published var totalCount = 0

    private var connsStorage: ClashConnsStorage?
    private var task: Task<Void, Never>?

    nonisolated init() {}

    deinit { task?.cancel() }

    func start(connsStorage: ClashConnsStorage) {
        guard task == nil else { return }
        self.connsStorage = connsStorage
        task = Task { [weak self] in
            for await _ in DashboardRefreshTicker.shared.ticks(every: Int(OverviewRefresh.streamInterval)) {
                self?.refresh()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func refresh() {
        guard let connsStorage else { return }
        let conns = connsStorage.conns
        let tcp = conns.filter { $0.metadata.network.lowercased() == "tcp" }.count
        let newTotal = conns.count
        let newStats = "TCP \(tcp) · UDP \(newTotal - tcp)"
        if newTotal != totalCount { totalCount = newTotal }
        if newStats != statsString { statsString = newStats }
    }
}
