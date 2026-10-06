//
//  ProxyRowView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProxyRowView: View {
	@ObservedObject var proxy: DBProxy
	let isSelectable: Bool
	let isNow: Bool
	let onSelect: () -> Void

	@EnvironmentObject var hideProxyNames: HideProxyNames

	@State private var isTesting = false
	@State private var isHovered = false

	private var isBuiltIn: Bool {
		[.pass, .direct, .reject].contains(proxy.type)
	}

	private var backgroundColor: Color {
		if isNow {
			return DashboardTheme.cellSelectedBackground
		}
		if isHovered {
			return DashboardTheme.cellHoverBackground
		}
		return DashboardTheme.cellBackground
	}

	var body: some View {
		VStack(alignment: .leading, spacing: DashboardTheme.spacingRowInner) {
			HStack(spacing: 8) {
				Text(hideProxyNames.hide ? HiddenNameToken.token(for: proxy.name) : proxy.name)
					.font(DashboardTheme.primaryTextFont)
					.lineLimit(1)
					.truncationMode(.tail)
				Spacer(minLength: 2)
				Text(proxy.udpString)
					.font(.system(size: 11))
					.foregroundColor(.secondary)
					.show(isVisible: !isBuiltIn && !proxy.udpString.isEmpty)
			}

			// Built-in rows intentionally omit the second line; the fixed outer
			// frame height keeps grid rows uniform across all node types.
			if !isBuiltIn {
				HStack(spacing: 6) {
					Text(verbatim: proxy.type.displayString)
						.font(DashboardTheme.secondaryTextFont)
						.foregroundColor(.secondary)
					Text("[TFO]")
						.font(DashboardTheme.secondaryTextFont)
						.foregroundColor(.secondary)
						.show(isVisible: proxy.tfo)
					Spacer(minLength: 6)
					ProxyLatencyView(number: proxy.delay > 0 ? proxy.delay : nil, isTesting: isTesting) {
						Task { await testLatency() }
					}
				}
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
		.frame(height: DashboardTheme.nodeRowHeight, alignment: .center)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(backgroundColor)
		.contentShape(Rectangle())
		.onTapGesture {
			guard isSelectable else { return }
			onSelect()
		}
		.onHover { isHovered = $0 }
	}

	@MainActor
	func testLatency() async {
		guard !isTesting else { return }
		isTesting = true
		defer { isTesting = false }
		let delay = await ApiRequest.getProxyDelay(proxyName: proxy.name)
		proxy.delay = delay
	}
}
