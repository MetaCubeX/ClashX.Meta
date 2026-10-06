//
//  ProxyGroupCard.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProxyGroupCard: View {
	@ObservedObject var proxyGroup: DBProxyGroup
	let width: CGFloat
	@EnvironmentObject var hideProxyNames: HideProxyNames
	@EnvironmentObject var searchString: ProxiesSearchString
	@EnvironmentObject var proxyStorage: DBProxyStorage

	@State private var isTesting = false
	@State private var isUpdatingSelect = false
	@State private var collapseOverride = false
	@State private var isHeaderHover = false

	private var isSelectable: Bool {
		[.select, .fallback].contains(proxyGroup.type)
	}

	private var nowLatency: Int? {
		guard let delay = proxyGroup.currentProxy?.delay, delay > 0 else { return nil }
		return delay
	}

	private var filterSegments: [String] {
		searchString.string
			.lowercased()
			.split(separator: " ")
			.map(String.init)
			.filter { !$0.isEmpty }
	}

	private var nameMatched: Bool {
		matchesFilter(proxyGroup.name)
	}

	private var forceOpen: Bool {
		!filterSegments.isEmpty && !nameMatched && !collapseOverride
	}

	private var effectiveIsOpen: Bool {
		proxyGroup.isOpen || forceOpen
	}

	private var visibleProxies: [DBProxy] {
		if nameMatched || filterSegments.isEmpty {
			return proxyGroup.proxies
		}
		return proxyGroup.proxies.filter { matchesFilter($0.name) }
	}

	private var nowChain: String {
		guard let now = proxyGroup.now else { return "" }
		var parts = [displayName(now)]
		var current = proxyStorage.groups.first { $0.name == now }
		var depth = 0
		while let group = current, let next = group.now, depth < 3 {
			parts.append(displayName(next))
			current = proxyStorage.groups.first { $0.name == next }
			depth += 1
		}
		return parts.joined(separator: " / ")
	}

	var body: some View {
		VStack(spacing: 0) {
			headerView
			bodyView
		}
		.cornerRadius(DashboardTheme.cardCornerRadius)
		.overlay(
			RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius)
				.stroke(DashboardTheme.cardBorder, lineWidth: DashboardTheme.cardBorderWidth)
		)
		.onChange(of: searchString.string) { _ in
			collapseOverride = false
		}
		.animation(.easeInOut(duration: 0.2), value: effectiveIsOpen)
	}

	var bodyView: some View {
		ZStack(alignment: .top) {
			nodeListView
				.opacity(effectiveIsOpen ? 1 : 0)
				.allowsHitTesting(effectiveIsOpen)
			summaryView
				.opacity(effectiveIsOpen ? 0 : 1)
				.allowsHitTesting(!effectiveIsOpen)
		}
		.frame(height: width > 0 ? bodyHeight : nil, alignment: .top)
		.clipped()
	}

	var headerView: some View {
		HStack(alignment: .center, spacing: 8) {
			Text(hideProxyNames.hide ? HiddenNameToken.token(for: proxyGroup.name) : proxyGroup.name)
				.font(DashboardTheme.titleFont)
				.lineLimit(1)
				.truncationMode(.tail)
			Text(verbatim: proxyGroup.type.displayString)
				.font(DashboardTheme.secondaryTextFont)
				.foregroundColor(.secondary)
			Button {
				Task { await startBenchmark() }
			} label: {
				Group {
					if isTesting {
						ProgressView()
							.controlSize(.small)
					} else {
						Image(systemName: "bolt.fill")
							.font(DashboardTheme.secondaryTextFont)
					}
				}
				.frame(minWidth: 28, minHeight: 24)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.foregroundColor(isHeaderHover ? .accentColor : .secondary)
			.disabled(isTesting)
			.help("Test Latency")
			Spacer()
			Image(systemName: "chevron.down")
				.font(DashboardTheme.secondaryTextFont)
				.foregroundColor(.secondary)
				.rotationEffect(.degrees(effectiveIsOpen ? 0 : -90))
		}
		.padding(.horizontal, DashboardTheme.spacingHeaderH)
		.padding(.vertical, DashboardTheme.spacingHeaderV)
		.background(isHeaderHover ? DashboardTheme.headerHoverBackground : Color.clear)
		.contentShape(Rectangle())
		.onTapGesture {
			toggle()
		}
		.onHover { isHeaderHover = $0 }
	}

	var nodeListView: some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.columnMinWidth), spacing: DashboardTheme.spacingGrid)], alignment: .leading, spacing: DashboardTheme.spacingGrid) {
			ForEach(visibleProxies, id: \.name) { proxy in
				ProxyRowView(
					proxy: proxy,
					isSelectable: isSelectable,
					isNow: proxy.name == proxyGroup.now
				) {
					Task { await updateSelect(proxy.name) }
				}
				.clipShape(RoundedRectangle(cornerRadius: 6))
			}
		}
		.padding(.vertical, 12)
		.padding(.horizontal, 12)
	}

	var summaryView: some View {
		HStack(spacing: 6) {
			Text(nowChain)
				.font(DashboardTheme.secondaryTextFont)
				.lineLimit(1)
				.truncationMode(.tail)
			if let latency = nowLatency {
				Text(verbatim: "\(latency) ms")
					.font(DashboardTheme.secondaryTextFont)
					.foregroundColor(DBProxy.delayColor(latency))
			}
			Spacer()
		}
		.padding(16)
	}

	// MARK: - Deterministic height (no measurement; constants calibrated to SwiftUI layout)

	private var columnCount: Int {
		guard width > 0 else { return 1 }
		let available = width - Metrics.nodePaddingHorizontal * 2
		let divisor = Metrics.columnMinWidth + DashboardTheme.spacingGrid
		return max(1, Int(floor((available + DashboardTheme.spacingGrid) / divisor)))
	}

	private var rowCount: Int {
		Int(ceil(Double(visibleProxies.count) / Double(columnCount)))
	}

	private var gridHeight: CGFloat {
		let rows = rowCount
		return CGFloat(rows) * Metrics.rowHeight
			+ CGFloat(max(0, rows - 1)) * DashboardTheme.spacingGrid
			+ Metrics.nodePaddingVertical * 2
	}

	private var bodyHeight: CGFloat {
		effectiveIsOpen ? gridHeight : Metrics.summaryHeight
	}

	private enum Metrics {
		static let columnMinWidth: CGFloat = 160
		static let nodePaddingHorizontal: CGFloat = 12
		static let nodePaddingVertical: CGFloat = 12

		static let rowHeight = DashboardTheme.nodeRowHeight
		static let summaryHeight = 16 * 2 + DashboardTheme.lineHeight(DashboardTheme.secondaryTextNSFont)
	}

	func toggle() {
		if forceOpen {
			collapseOverride = true
		} else {
			proxyGroup.isOpen.toggle()
		}
	}

	func matchesFilter(_ name: String) -> Bool {
		let lower = name.lowercased()
		return filterSegments.contains { lower.contains($0) }
	}

	func displayName(_ name: String) -> String {
		guard hideProxyNames.hide else { return name }
		if let group = proxyStorage.groups.first(where: { $0.name == name }) {
			return HiddenNameToken.token(for: group.name)
		}
		for group in proxyStorage.groups {
			if let proxy = group.proxies.first(where: { $0.name == name }) {
				return HiddenNameToken.token(for: proxy.name)
			}
		}
		return name
	}

	@MainActor
	func startBenchmark() async {
		guard !isTesting else { return }
		isTesting = true
		defer { isTesting = false }
		let delays = await ProxyHealthCheckManager.shared.getGroupDelay(groupName: proxyGroup.name)
		proxyGroup.proxies.enumerated().forEach {
			var delay = 0
			if let d = delays[$0.element.name], d != 0 {
				delay = d
			}
			guard $0.offset < proxyGroup.proxies.count,
				  proxyGroup.proxies[$0.offset].name == $0.element.name
			else { return }
			proxyGroup.proxies[$0.offset].delay = delay

			if proxyGroup.currentProxy?.name == $0.element.name {
				proxyGroup.currentProxy = proxyGroup.proxies[$0.offset]
			}
		}
	}

	@MainActor
	func updateSelect(_ name: String) async {
		guard isSelectable, !isUpdatingSelect else { return }
		isUpdatingSelect = true
		let success = await ApiRequest.updateProxyGroup(group: proxyGroup.name, selectProxy: name)
		isUpdatingSelect = false
		guard success else { return }
		ConfigManager.recordProxySelection(group: proxyGroup.name, selected: name)
		await ConnectionManager.closeConnection(for: proxyGroup.name)
		proxyGroup.now = name
	}
}
