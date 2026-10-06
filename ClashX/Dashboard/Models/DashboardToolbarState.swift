//
//  DashboardToolbarState.swift
//  ClashX Dashboard
//
//

import Foundation

@MainActor
final class DashboardToolbarState: ObservableObject {
    enum LogFilter: String, CaseIterable {
        case all = "All"
        case rule = "Rule"
        case dns = "DNS"
        case others = "Others"
    }

    // App-lifecycle in-memory store (not UserDefaults, not per-dashboard)
    // MainActor-isolated: only accessed from didSet/init on MainActor
    @MainActor private static var storedConnShowClosed = false
    @MainActor private static var storedConnSourceIPFilter = ""
    @MainActor private static var storedConnAppFilter = ""
    @MainActor private static var storedConnInternalFilter = false

    @Published var searchText = ""
    @Published var hideProxyNames = false
    @Published var logLevel = ConfigOverride.shared.logLevel
    @Published var logFilter = LogFilter.all
    @Published var connShowClosed = storedConnShowClosed {
        didSet { Self.storedConnShowClosed = connShowClosed }
    }
    @Published var connSourceIPFilter = storedConnSourceIPFilter {
        didSet { Self.storedConnSourceIPFilter = connSourceIPFilter }
    }
    @Published var connAppFilter = storedConnAppFilter {
        didSet { Self.storedConnAppFilter = connAppFilter }
    }
    @Published var connInternalFilter = storedConnInternalFilter {
        didSet { Self.storedConnInternalFilter = connInternalFilter }
    }

    func stopConns() {
        NotificationCenter.default.post(name: .stopConns, object: nil)
    }

    func hideNamesToggled() {
        hideProxyNames.toggle()
    }

    func updateLogLevel(_ level: ClashLogLevel) {
        guard logLevel != level else { return }
        logLevel = level
    }

    func updateLogFilter(_ filter: LogFilter) {
        guard logFilter != filter else { return }
        logFilter = filter
    }
}
