//
//  DashboardTheme.swift
//  ClashX Dashboard
//
//  General design values; page-specific details stay in each page
//

import SwiftUI

enum DashboardTheme {
	
	// MARK: - Page
	
	static let pageBackground = Color(nsColor: .controlBackgroundColor)
	
	// MARK: - Card
	
	static let cardCornerRadius: CGFloat = 8
	static let cardBorder = Color(nsColor: .separatorColor).opacity(0.7)
	static let cardBorderWidth: CGFloat = 1
	
	// MARK: - Feedback
	
	static let cellBackground = Color.primary.opacity(0.05)
	static let cellHoverBackground = Color.primary.opacity(0.08)
	static let cellSelectedBackground = Color.accentColor.opacity(0.15)
	static let headerHoverBackground = Color.primary.opacity(0.06)

	// MARK: - Latency

	// Dark Mode tints soften slightly (78%); Light Mode keeps full system colors.
	static let latencyGood = softened(.systemGreen)
	static let latencyNormal = softened(.systemYellow)
	static let latencySlow = softened(.systemOrange)

	// MARK: - Charts

	static let chartBlue = softened(.systemBlue)
	static let chartGreen = softened(.systemGreen)
	static let chartPurple = softened(.systemPurple)

	private static func softened(_ base: NSColor, darkAlpha: CGFloat = 0.78) -> Color {
		Color(nsColor: NSColor(name: nil) { appearance in
			let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			return dark ? base.withAlphaComponent(darkAlpha) : base
		})
	}

	// MARK: - Usage Bar

	// Light keeps the tuned soft blue/gray; Dark boosts opacity so bars read on dark cards.
	static let usageBarFill = Color(nsColor: NSColor(name: nil) { appearance in
		let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		return NSColor.controlAccentColor.withAlphaComponent(dark ? 0.4 : 0.28)
	})

	static let usageBarTrack = Color(nsColor: NSColor(name: nil) { appearance in
		let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		return dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.gray.withAlphaComponent(0.1)
	})
	
	// MARK: - Spacing
	
	static let spacingPage: CGFloat = 16
	static let spacingBetweenCards: CGFloat = 16
	static let spacingGrid: CGFloat = 10
	static let spacingHeaderH: CGFloat = 16
	static let spacingHeaderV: CGFloat = 12
	static let spacingRowH: CGFloat = 12
	static let spacingRowV: CGFloat = 8
	static let spacingRowInner: CGFloat = 6
	// Vertical gap between Text1 label and Text2 value inside overview stat cards
	static let spacingOverviewStatText: CGFloat = 8
	// Fixed node cell height (content centered; keeps grid rows deterministic)
	static let nodeRowHeight: CGFloat = 53
	// Fixed spacing between provider columns (widths are pure content, no buffer)
	static let spacingColumn: CGFloat = 20
	
	// MARK: - Semantic colors
	
	static let proxyDirect = softened(.systemOrange)
	static let proxyReject = softened(.systemRed)
	static let proxyDefault = softened(.systemBlue)
	
	// MARK: - Fonts (Font/NSFont paired, bold for card titles only, adjust size here)
	
	static let titleFont = Font.system(size: 15, weight: .medium)
	static let primaryTextFont = Font.system(size: 13)
	static let secondaryTextFont = Font.system(size: 12)
	// Overview two-tier scale: Text1 labels, Text2 values
	static let overviewLabelFont = Font.system(size: 12)
	static let overviewStatTitleFont = Font.system(size: 13)
	static let overviewValueFont = Font.system(size: 18)
	static let primaryTextNSFont = NSFont.systemFont(ofSize: 13)
	static let secondaryTextNSFont = NSFont.systemFont(ofSize: 12)
	static let overviewStatTitleNSFont = NSFont.systemFont(ofSize: 13)

	// Line height as laid out by SwiftUI (matches NSLayoutManager for system fonts)
	static func lineHeight(_ font: NSFont) -> CGFloat {
		NSLayoutManager().defaultLineHeight(for: font)
	}
}
