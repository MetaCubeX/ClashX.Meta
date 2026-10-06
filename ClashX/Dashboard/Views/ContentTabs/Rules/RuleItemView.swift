//
//  RuleItemView.swift
//  ClashX Dashboard
//
//

import SwiftUI

// Column widths measured from the longest string in the data (data-driven, no presets)
struct RuleColumnWidths {
	let type: CGFloat
	let size: CGFloat
	let proxy: CGFloat

	init(ruleItems: [ClashRule], buffer: CGFloat = 8) {
		let sizeTexts = ruleItems.map {
			$0.size > 0 ? String(format: NSLocalizedString("size: %lld", comment: ""), $0.size) : ""
		}
		type = TextMeasurement.maxWidth(of: ruleItems.map(\.type), font: DashboardTheme.secondaryTextNSFont) + buffer
		size = TextMeasurement.maxWidth(of: sizeTexts, font: DashboardTheme.secondaryTextNSFont) + buffer
		proxy = TextMeasurement.maxWidth(of: ruleItems.compactMap(\.proxy), font: DashboardTheme.primaryTextNSFont) + buffer
	}
}

struct RuleItemView: View {
	let index: Int
	let rule: ClashRule
	let columnWidths: RuleColumnWidths

	@State private var isHovered = false

	private var proxyColor: Color {
		switch rule.proxy {
		case "DIRECT":
			return DashboardTheme.proxyDirect
		case "REJECT", "REJECT-DROP":
			return DashboardTheme.proxyReject
		default:
			return DashboardTheme.proxyDefault
		}
	}

	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			Text(verbatim: "\(index)")
				.font(DashboardTheme.secondaryTextFont.monospacedDigit())
				.foregroundColor(.secondary)
				.frame(width: 30, alignment: .center)
			Text(rule.payload ?? "")
				.font(DashboardTheme.primaryTextFont)
				.lineLimit(1)
				.truncationMode(.tail)
				.frame(maxWidth: .infinity, alignment: .leading)
			Text(rule.type)
				.font(DashboardTheme.secondaryTextFont)
				.foregroundColor(.secondary)
				.frame(width: columnWidths.type, alignment: .leading)
			Text(rule.size > 0 ? String(format: NSLocalizedString("size: %lld", comment: ""), rule.size) : "")
				.font(DashboardTheme.secondaryTextFont)
				.foregroundColor(.secondary)
				.frame(width: columnWidths.size, alignment: .leading)
			Text(rule.proxy ?? "")
				.font(DashboardTheme.primaryTextFont)
				.foregroundColor(proxyColor)
				.lineLimit(1)
				.truncationMode(.tail)
				.frame(width: columnWidths.proxy, alignment: .leading)
				.show(isVisible: !(rule.proxy?.isEmpty ?? true))
		}
		.padding(.horizontal, DashboardTheme.spacingRowH)
		.padding(.vertical, 10)
		.background(isHovered ? DashboardTheme.cellHoverBackground : Color.clear)
		.onHover { isHovered = $0 }
	}
}

struct RulesRowView_Previews: PreviewProvider {
	static var previews: some View {
		RuleItemView(
			index: 114,
			rule: .init(type: "DIRECT", payload: "cn", proxy: "GeoSite"),
			columnWidths: RuleColumnWidths(ruleItems: [.init(type: "DIRECT", payload: "cn", proxy: "GeoSite")])
		)
	}
}