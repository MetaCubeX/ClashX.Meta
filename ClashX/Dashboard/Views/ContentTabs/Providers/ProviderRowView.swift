//
//  ProviderRowView.swift
//  ClashX Dashboard
//
//

import SwiftUI

// Column widths measured from the longest content; fixed spacing handled by HStack spacing
struct ProxyProviderColumnWidths {
	let index: CGFloat
	let first: CGFloat
	let second: CGFloat
	let third: CGFloat
	let fourth: CGFloat
	let fifth: CGFloat
	let typeIconWidth: CGFloat
	let thirdIconWidth: CGFloat

	static let columnSpacing: CGFloat = DashboardTheme.spacingColumn
	private static let badgeIconSpacing: CGFloat = 3

	init(providers: [DBProxyProvider]) {
		let fontSize: CGFloat = 12
		let typeTexts = providers.map { $0.vehicleType.rawValue }
		let qtyTexts = providers.map { String(format: NSLocalizedString("%lld nodes", comment: ""), $0.proxies.count) }
		let usageTexts = providers.map { provider -> String in
			guard let usage = provider.subscriptionUsage else { return "—" }
			return "\(usage.usedText) / \(usage.totalText)  \(usage.percentText)"
		}
		let expireTexts = providers.map(\.expireDate)
		let updatedTexts = providers.map(\.updatedAt)

		typeIconWidth = TextMeasurement.iconWidth("internaldrive", fontSize: fontSize)
		thirdIconWidth = TextMeasurement.iconWidth("shippingbox", fontSize: fontSize)

		index = 30
		first = max(
			TextMeasurement.maxWidth(of: providers.map(\.name), font: DashboardTheme.primaryTextNSFont),
			TextMeasurement.maxWidth(of: usageTexts, font: DashboardTheme.secondaryTextNSFont) + 14
		)
		second = TextMeasurement.maxWidth(of: typeTexts, font: DashboardTheme.secondaryTextNSFont) + typeIconWidth + Self.badgeIconSpacing
		third = TextMeasurement.maxWidth(of: qtyTexts, font: DashboardTheme.secondaryTextNSFont) + thirdIconWidth + Self.badgeIconSpacing
		fourth = TextMeasurement.maxWidth(of: expireTexts, font: DashboardTheme.secondaryTextNSFont)
		fifth = TextMeasurement.maxWidth(of: updatedTexts, font: DashboardTheme.secondaryTextNSFont)
	}
}

struct ProviderRowView: View {
	let index: Int
	let columnWidths: ProxyProviderColumnWidths
	@ObservedObject var proxyProvider: DBProxyProvider

	@EnvironmentObject var hideProxyNames: HideProxyNames

	@State private var isHovered = false
	@State private var isUpdating = false

	var body: some View {
		HStack(spacing: 0) {
			NavigationLink {
				ProviderProxiesView(provider: proxyProvider)
			} label: {
				rowContent
			}
			.buttonStyle(.plain)
			.frame(maxWidth: .infinity, alignment: .leading)

			Button {
				Task { await update() }
			} label: {
				Group {
					if isUpdating {
						ProgressView()
							.controlSize(.small)
					} else {
						Image(systemName: "arrow.clockwise")
					}
				}
				.foregroundColor(.secondary)
				.frame(minWidth: 32, minHeight: 28)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.disabled(isUpdating)
		}
		.padding(.horizontal, DashboardTheme.spacingRowH)
		.padding(.vertical, 10)
		.background(isHovered ? DashboardTheme.cellHoverBackground : Color.clear)
		.onHover { isHovered = $0 }
	}

	private var rowContent: some View {
		HStack(spacing: ProxyProviderColumnWidths.columnSpacing) {
			Text(verbatim: "\(index)")
				.font(DashboardTheme.secondaryTextFont.monospacedDigit())
				.foregroundColor(.secondary)
				.frame(width: columnWidths.index, alignment: .center)

			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: ProxyProviderColumnWidths.columnSpacing) {
					Text(hideProxyNames.hide ? HiddenNameToken.token(for: proxyProvider.name) : proxyProvider.name)
						.font(DashboardTheme.primaryTextFont)
						.lineLimit(1)
						.truncationMode(.tail)
						.frame(width: columnWidths.first, alignment: .leading)
					badge(icon: "internaldrive", text: proxyProvider.vehicleType.rawValue, iconFrame: columnWidths.typeIconWidth)
						.lineLimit(1)
						.frame(width: columnWidths.second, alignment: .leading)
					badge(icon: "shippingbox", text: String(format: NSLocalizedString("%lld nodes", comment: ""), proxyProvider.proxies.count), iconFrame: columnWidths.thirdIconWidth)
						.lineLimit(1)
						.frame(width: columnWidths.third, alignment: .leading)
				}
			HStack(spacing: ProxyProviderColumnWidths.columnSpacing) {
				usageCell
					.frame(width: columnWidths.first, alignment: .leading)
				Text(proxyProvider.expireDate)
					.lineLimit(1)
					.truncationMode(.tail)
					.frame(width: columnWidths.fourth, alignment: .leading)
				Text(proxyProvider.updatedAt)
					.lineLimit(1)
					.truncationMode(.tail)
					.frame(width: columnWidths.fifth, alignment: .leading)
			}
			.font(DashboardTheme.secondaryTextFont)
			.foregroundColor(.secondary)
			}
		}
	}

	private func badge(icon: String, text: String, iconFrame: CGFloat) -> some View {
		HStack(spacing: 3) {
			Image(systemName: icon)
				.frame(width: iconFrame)
			Text(text)
		}
		.font(DashboardTheme.secondaryTextFont)
		.foregroundColor(.secondary)
	}

	// Traffic usage with the progress bar drawn behind the text, matching the
	// Overview subscription card colors (track 0.15 / solid accent fill).
	private var usageCell: some View {
		Group {
			if let usage = proxyProvider.subscriptionUsage {
				HStack(spacing: 8) {
					Text(verbatim: "\(usage.usedText) / \(usage.totalText)")
						.lineLimit(1)
						.minimumScaleFactor(0.7)
					Spacer(minLength: 0)
					Text(verbatim: usage.percentText)
						.monospacedDigit()
				}
				.padding(.horizontal, 6)
				.background {
					GeometryReader { proxy in
						ZStack(alignment: .leading) {
							RoundedRectangle(cornerRadius: 4)
								.fill(DashboardTheme.usageBarTrack)
							RoundedRectangle(cornerRadius: 4)
								.fill(DashboardTheme.usageBarFill)
								.frame(width: max(0, min(proxy.size.width, proxy.size.width * usage.ratio)))
						}
					}
				}
			} else {
				Text(verbatim: "—")
			}
		}
	}

	@MainActor
	private func update() async {
		guard !isUpdating else { return }
		isUpdating = true
		defer { isUpdating = false }
		_ = await ApiRequest.updateProvider(for: .proxy, name: proxyProvider.name)
		NotificationCenter.default.post(name: .proxyProvidersUpdated, object: nil)
	}
}
