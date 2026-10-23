//
//  DashboardView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct DashboardView: View {
	@ObservedObject var chromeState: DashboardChromeState
	@ObservedObject var toolbarState: DashboardToolbarState
	@ObservedObject var apiDatasStorage: ClashApiDatasStorage

	@StateObject private var proxiesSearchString = ProxiesSearchString()
	@StateObject private var hideProxyNames = HideProxyNames()
	@StateObject private var providerStorage = DBProviderStorage()
	@StateObject private var subscriptionPoller = SubscriptionPoller()
	@StateObject private var networkStatusPoller = NetworkStatusPoller()
	@StateObject private var topAppsPoller = TopAppsPoller()
	@StateObject private var connectionsStatsPoller = ConnectionsStatsPoller()
	@State private var detailReloadID = UUID()

	init(chromeState: DashboardChromeState,
	     toolbarState: DashboardToolbarState,
	     apiDatasStorage: ClashApiDatasStorage) {
		_chromeState = ObservedObject(wrappedValue: chromeState)
		_toolbarState = ObservedObject(wrappedValue: toolbarState)
		_apiDatasStorage = ObservedObject(wrappedValue: apiDatasStorage)
	}

	var body: some View {
		DashboardSelectedPageView(
			selection: chromeState.selection,
			proxyContentSegment: chromeState.proxyContentSegment,
			ruleContentSegment: chromeState.ruleContentSegment
		)
		.id(detailReloadID)
		.environmentObject(apiDatasStorage.overviewData)
		.environmentObject(apiDatasStorage.logStorage)
		.environmentObject(apiDatasStorage.connsStorage)
		.environmentObject(toolbarState)
		.environmentObject(proxiesSearchString)
		.environmentObject(hideProxyNames)
		.environmentObject(subscriptionPoller)
		.environmentObject(networkStatusPoller)
		.environmentObject(topAppsPoller)
		.environmentObject(connectionsStatsPoller)
		.environmentObject(providerStorage)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.onAppear {
			// Re-bridge mirrored state: this view's @StateObject stores reset
			// on window recreation while toolbarState (VC-owned) keeps values.
			proxiesSearchString.string = toolbarState.searchText
			hideProxyNames.hide = toolbarState.hideProxyNames
			subscriptionPoller.start()
			networkStatusPoller.start()
			topAppsPoller.start(connsStorage: apiDatasStorage.connsStorage)
			connectionsStatsPoller.start(connsStorage: apiDatasStorage.connsStorage)
		}
		.onChange(of: chromeState.selection) { newValue in
			guard let newValue else { return }
			if newValue != .logs {
				toolbarState.logFilter = .all
			}
			if newValue == .proxies, chromeState.proxyContentSegment != .proxyList {
				chromeState.proxyContentSegment = .proxyList
			} else if newValue == .rules, chromeState.ruleContentSegment != .ruleList {
				chromeState.ruleContentSegment = .ruleList
			}
		}
		.onChange(of: toolbarState.searchText) { newValue in
			proxiesSearchString.string = newValue
		}
		.onChange(of: toolbarState.hideProxyNames) { newValue in
			hideProxyNames.hide = newValue
		}
		.onReceive(NotificationCenter.default.publisher(for: .reloadDashboard)) { _ in
			detailReloadID = UUID()
		}
	}
}

private struct DashboardSelectedPageView: View {
	let selection: SidebarItem?
	let proxyContentSegment: ProxyContentSegment
	let ruleContentSegment: RuleContentSegment

	var body: some View {
		NavigationStack {
			switch selection {
			case .overview:
				OverviewView()
			case .proxies:
				switch proxyContentSegment {
				case .proxyList:
					ProxiesView()
				case .proxyProviders:
					ProvidersView(mode: .proxy)
				}
			case .rules:
				switch ruleContentSegment {
				case .ruleList:
					RulesView()
				case .ruleProviders:
					ProvidersView(mode: .rule)
				}
			case .conns:
				ConnectionsView()
			case .config:
				ConfigView()
			case .logs:
				LogsView()
			case .none:
				EmptyView()
			}
		}
	}
}
