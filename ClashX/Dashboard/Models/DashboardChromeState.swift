//
//  DashboardChromeState.swift
//  ClashX Meta
//
//  Shared UI state between the AppKit toolbar layer and the SwiftUI content.
//

import Cocoa
import SwiftUI

enum ProxyContentSegment: String, CaseIterable, Identifiable {
	case proxyList = "Proxies"
	case proxyProviders = "Providers"

	var id: String { rawValue }

	var title: String { NSLocalizedString(rawValue, comment: "") }
}

enum RuleContentSegment: String, CaseIterable, Identifiable {
	case ruleList = "Rules"
	case ruleProviders = "Providers"

	var id: String { rawValue }

	var title: String { NSLocalizedString(rawValue, comment: "") }
}

@MainActor
final class DashboardChromeState: ObservableObject {
	@Published var selection: SidebarItem? = .overview
	@Published var proxyContentSegment: ProxyContentSegment = .proxyList
	@Published var ruleContentSegment: RuleContentSegment = .ruleList
	@Published var columnVisibility: NavigationSplitViewVisibility = .automatic
	@Published var isUpdatingRuleProviders = false
	@Published var isUpdatingProxyProviders = false

	var showsSegmentedToolbar: Bool {
		switch selection {
		case .proxies, .rules, .conns:
			return true
		case .overview, .config, .logs, .none:
			return false
		}
	}

	func updateAllRuleProviders() async {
		guard !isUpdatingRuleProviders else { return }
		isUpdatingRuleProviders = true
		defer { isUpdatingRuleProviders = false }
		_ = await ApiRequest.updateAllProviders(for: .rule)
		NotificationCenter.default.post(name: .ruleProvidersUpdated, object: nil)
	}

	func updateAllProxyProviders() async {
		guard !isUpdatingProxyProviders else { return }
		isUpdatingProxyProviders = true
		defer { isUpdatingProxyProviders = false }
		_ = await ApiRequest.updateAllProviders(for: .proxy)
		NotificationCenter.default.post(name: .proxyProvidersUpdated, object: nil)
	}
}
