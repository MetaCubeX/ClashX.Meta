//
//  RuleProviderView.swift
//  ClashX Dashboard
//
//

import SwiftUI

// Column widths measured from the longest content; fixed spacing handled by HStack spacing
struct RuleProviderColumnWidths {
	let index: CGFloat
	let first: CGFloat
	let second: CGFloat
	let behavior: CGFloat
	// updated 覆盖列 2 + 列 3（行 2 无 behavior）
	var updated: CGFloat { second + Self.columnSpacing + behavior }

	static let columnSpacing: CGFloat = DashboardTheme.spacingColumn
	static let badgeIconSpacing: CGFloat = 3

	init(providers: [DBRuleProvider]) {
		let fontSize: CGFloat = 12
		let typeTexts = providers.map { $0.vehicleType == .HTTP ? "HTTP" : "Inline" }
		let behaviorTexts = providers.map { $0.behavior }
		let rulesTexts = providers.map { String(format: NSLocalizedString("%lld rules", comment: ""), $0.ruleCount) }

		let typeIconWidth = TextMeasurement.iconWidth("internaldrive", fontSize: fontSize)
		let behaviorIconWidth = max(
			TextMeasurement.iconWidth("globe", fontSize: fontSize),
			TextMeasurement.iconWidth("network", fontSize: fontSize)
		)

		index = 30
		first = max(
			TextMeasurement.maxWidth(of: providers.map(\.name), font: DashboardTheme.primaryTextNSFont),
			TextMeasurement.maxWidth(of: rulesTexts, font: DashboardTheme.secondaryTextNSFont)
		)
		second = TextMeasurement.maxWidth(of: typeTexts, font: DashboardTheme.secondaryTextNSFont) + typeIconWidth + Self.badgeIconSpacing
		behavior = TextMeasurement.maxWidth(of: behaviorTexts, font: DashboardTheme.secondaryTextNSFont) + behaviorIconWidth + Self.badgeIconSpacing
	}
}

struct RuleProviderView: View {
	let index: Int
	let columnWidths: RuleProviderColumnWidths
	@ObservedObject var provider: DBRuleProvider

	@State private var isHovered = false
	@State private var isUpdating = false

	var body: some View {
		HStack(spacing: RuleProviderColumnWidths.columnSpacing) {
			Text(verbatim: "\(index)")
				.font(DashboardTheme.secondaryTextFont.monospacedDigit())
				.foregroundColor(.secondary)
				.frame(width: columnWidths.index, alignment: .center)

			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: RuleProviderColumnWidths.columnSpacing) {
					Text(provider.name)
						.font(DashboardTheme.primaryTextFont)
						.lineLimit(1)
						.truncationMode(.tail)
						.frame(width: columnWidths.first, alignment: .leading)
					badge(icon: "internaldrive", text: provider.vehicleType == .HTTP ? "HTTP" : "Inline", iconFrame: TextMeasurement.iconWidth("internaldrive", fontSize: 12))
						.lineLimit(1)
						.frame(width: columnWidths.second, alignment: .leading)
					badge(icon: provider.behavior.lowercased().contains("ip") ? "network" : "globe", text: provider.behavior, iconFrame: max(
						TextMeasurement.iconWidth("globe", fontSize: 12),
						TextMeasurement.iconWidth("network", fontSize: 12)
					))
						.lineLimit(1)
						.frame(width: columnWidths.behavior, alignment: .leading)
				}
				HStack(spacing: RuleProviderColumnWidths.columnSpacing) {
					Text(verbatim: String(format: NSLocalizedString("%lld rules", comment: ""), provider.ruleCount))
						.lineLimit(1)
						.frame(width: columnWidths.first, alignment: .leading)
					Text(updatedAtText)
						.lineLimit(1)
						.truncationMode(.tail)
						.frame(width: columnWidths.updated, alignment: .leading)
				}
				.font(DashboardTheme.secondaryTextFont)
				.foregroundColor(.secondary)
			}

			Spacer()

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

	private var updatedAtText: String {
		DashboardFormatters.providerUpdateText(for: provider.updatedAt)
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

	@MainActor
	private func update() async {
		guard !isUpdating else { return }
		isUpdating = true
		defer { isUpdating = false }
		_ = await ApiRequest.updateProvider(for: .rule, name: provider.name)
		NotificationCenter.default.post(name: .ruleProvidersUpdated, object: nil)
	}
}