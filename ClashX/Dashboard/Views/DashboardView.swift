//
//  DashboardView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct DashboardView: View {
	static let minimumSize = CGSize(width: 920, height: 580)

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

	var body: some View {
		NavigationSplitView(columnVisibility: $chromeState.columnVisibility) {
			SidebarView(selection: $chromeState.selection, clashApiDatasStorage: apiDatasStorage)
				.navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
		} detail: {
			detailView
		}
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
		.frame(
			minWidth: Self.minimumSize.width,
			idealWidth: Self.minimumSize.width,
			minHeight: Self.minimumSize.height,
			idealHeight: Self.minimumSize.height
		)
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
	}

	@ViewBuilder
	private var detailView: some View {
		NavigationStack {
			switch chromeState.selection {
			case .overview:
				OverviewView()
			case .proxies:
				switch chromeState.proxyContentSegment {
				case .proxyList:
					ProxiesView()
				case .proxyProviders:
					ProvidersView(mode: .proxy)
				}
			case .rules:
				switch chromeState.ruleContentSegment {
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
