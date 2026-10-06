//
//  ProvidersView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProvidersView: View {
	enum Mode {
		case proxy
		case rule
	}

	@EnvironmentObject var providerStorage: DBProviderStorage
	@EnvironmentObject var hideProxyNames: HideProxyNames
	@State private var columnWidths = RuleProviderColumnWidths(providers: [])
	@State private var proxyColumnWidths = ProxyProviderColumnWidths(providers: [])

	var mode: Mode = .rule

	var httpRuleProviders: [DBRuleProvider] {
		guard mode == .rule else { return [] }
		return providerStorage.ruleProviders.filter({ $0.vehicleType == .HTTP })
	}

	var inlineRuleProviders: [DBRuleProvider] {
		guard mode == .rule else { return [] }
		return providerStorage.ruleProviders.filter({ $0.vehicleType == .Inline })
	}

	var body: some View {
		Group {
			if mode == .rule {
				ruleProvidersView
			} else {
				proxyProvidersView
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: .ruleProvidersUpdated)) { _ in
			Task { await loadRuleProviders() }
		}
		.onReceive(NotificationCenter.default.publisher(for: .proxyProvidersUpdated)) { _ in
			Task { await loadProxyProviders() }
		}
		.task {
			await loadProviders()
		}
	}

	private var ruleProvidersView: some View {
		ScrollView {
			if httpRuleProviders.isEmpty && inlineRuleProviders.isEmpty {
				Text("Empty")
					.foregroundColor(.secondary)
					.padding(DashboardTheme.spacingPage)
			} else {
				let providers = httpRuleProviders + inlineRuleProviders
				VStack(spacing: 0) {
				ForEach(Array(providers.enumerated()), id: \.element.name) { index, provider in
					RuleProviderView(index: index + 1, columnWidths: columnWidths, provider: provider)
						if index < providers.count - 1 {
							Divider()
								.opacity(0.3)
						}
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius))
				.overlay(
					RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius)
						.stroke(DashboardTheme.cardBorder, lineWidth: DashboardTheme.cardBorderWidth)
				)
				.padding(DashboardTheme.spacingPage)
			}
		}
		.background(DashboardTheme.pageBackground)
	}

	private var proxyProvidersView: some View {
		ScrollView {
			if httpProxyProviders.isEmpty && inlineProxyProviders.isEmpty {
				Text("Empty")
					.foregroundColor(.secondary)
					.padding(DashboardTheme.spacingPage)
			} else {
				let providers = httpProxyProviders + inlineProxyProviders
				VStack(spacing: 0) {
					ForEach(Array(providers.enumerated()), id: \.element.name) { index, provider in
						ProviderRowView(index: index + 1, columnWidths: proxyColumnWidths, proxyProvider: provider)
						if index < providers.count - 1 {
							Divider()
								.opacity(0.3)
						}
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius))
				.overlay(
					RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius)
						.stroke(DashboardTheme.cardBorder, lineWidth: DashboardTheme.cardBorderWidth)
				)
				.padding(DashboardTheme.spacingPage)
			}
		}
		.background(DashboardTheme.pageBackground)
	}

	private var httpProxyProviders: [DBProxyProvider] {
		providerStorage.proxyProviders.filter({ $0.vehicleType == .HTTP })
	}

	private var inlineProxyProviders: [DBProxyProvider] {
		providerStorage.proxyProviders.filter({ $0.vehicleType == .Inline })
	}

	@MainActor
	func loadProviders() async {
		if mode != .rule {
			await loadProxyProviders()
		}
		if mode == .rule {
			await loadRuleProviders()
		}
	}

	@MainActor
	func loadProxyProviders() async {
		let proxyResp = await ApiRequest.requestProxyProviderList()
		let providers = proxyResp.allProviders.values
			.filter { $0.vehicleType == .HTTP || $0.vehicleType == .Inline }
			.sorted {
			$0.name < $1.name
		}
		.map(DBProxyProvider.init)
		proxyColumnWidths = ProxyProviderColumnWidths(providers: providers)
		providerStorage.proxyProviders = providers
	}

	@MainActor
	func loadRuleProviders() async {
		let ruleResp = await ApiRequest.requestRuleProviderList()
		let providers = ruleResp.allProviders.values.sorted {
			$0.name < $1.name
		}
		.map(DBRuleProvider.init)
		columnWidths = RuleProviderColumnWidths(providers: providers)
		providerStorage.ruleProviders = providers
	}
}
