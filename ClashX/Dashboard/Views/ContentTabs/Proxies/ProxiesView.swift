//
//  ProxiesView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProxiesView: View {
	
	@StateObject private var proxyStorage = DBProxyStorage()

	@EnvironmentObject var hideProxyNames: HideProxyNames
	@EnvironmentObject var searchString: ProxiesSearchString
	
	@State private var isGlobalMode = false
	@State private var containerWidth: CGFloat = 0
	
	private var filterSegments: [String] {
		searchString.string
			.lowercased()
			.split(separator: " ")
			.map(String.init)
			.filter { !$0.isEmpty }
	}
	
	private var visibleGroups: [DBProxyGroup] {
		let groups = proxyStorage.groups.filter { !$0.hidden }
		guard !filterSegments.isEmpty else { return groups }
		return groups.filter { group in
			matchesFilter(group.name) || group.proxies.contains { matchesFilter($0.name) }
		}
	}
	
    var body: some View {
		ZStack {
			ScrollView {
				LazyVStack(spacing: DashboardTheme.spacingBetweenCards) {
					ForEach(visibleGroups) { group in
						ProxyGroupCard(proxyGroup: group, width: cardWidth)
					}
				}
				.padding(DashboardTheme.spacingPage)
			}
			.background(DashboardTheme.pageBackground)
			.task {
				await loadProxies()
			}
			.environmentObject(proxyStorage)

			GeometryReader { geometry in
				Rectangle()
					.fill(.clear)
					.frame(height: 1)
					.onChange(of: geometry.size.width) { newValue in
						containerWidth = newValue
					}
					.onAppear {
						containerWidth = geometry.size.width
					}
			}
			.frame(height: 1)
		}
    }

	private var cardWidth: CGFloat {
		containerWidth - DashboardTheme.spacingPage * 2
	}
	
	func matchesFilter(_ name: String) -> Bool {
		let lower = name.lowercased()
		return filterSegments.contains { lower.contains($0) }
	}
	
	@MainActor
	func loadProxies() async {
		self.isGlobalMode = ConfigManager.shared.currentConfig?.mode == .global
		let resp = await ApiRequest.getMergedProxyData()
		let groups = DBProxyStorage(resp).groups.filter {
			isGlobalMode ? true : $0.name != "GLOBAL"
		}
		proxyStorage.updateGroups(groups)
	}
}