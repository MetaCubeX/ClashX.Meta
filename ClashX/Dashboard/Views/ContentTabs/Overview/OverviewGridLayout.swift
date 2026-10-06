//
//  OverviewGridLayout.swift
//  ClashX Dashboard
//
//

import SwiftUI

// Layout values attached to each card: position and span within the grid
private struct GridColumnKey: LayoutValueKey {
	static let defaultValue: Int = 0
}

private struct GridRowKey: LayoutValueKey {
	static let defaultValue: Int = 0
}

private struct GridColumnSpanKey: LayoutValueKey {
	static let defaultValue: Int = 1
}

private struct GridRowSpanKey: LayoutValueKey {
	static let defaultValue: Int = 1
}

extension View {
	func gridCell(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) -> some View {
		layoutValue(key: GridColumnKey.self, value: column)
			.layoutValue(key: GridRowKey.self, value: row)
			.layoutValue(key: GridColumnSpanKey.self, value: columnSpan)
			.layoutValue(key: GridRowSpanKey.self, value: rowSpan)
	}
}

// Fixed-column grid: card spans are presets; row heights come in 1x/2x tiers
struct OverviewGridLayout: Layout {
	let columns: Int
	let rowCount: Int
	let rowHeight: CGFloat
	let spacing: CGFloat
	let baseWidth: CGFloat

	private var baseHeight: CGFloat {
		CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * spacing
	}

	struct Cache {
		var lastRealWidth: CGFloat = -1
		var lastSize: CGSize = .zero
	}

	func makeCache(subviews: Subviews) -> Cache {
		Cache()
	}

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
		let width = (proposal.width ?? baseWidth).rounded(.toNearestOrEven)
		if width <= 0 {
			return .zero
		}
		if width == cache.lastRealWidth {
			return cache.lastSize
		}
		let size = CGSize(width: width, height: baseHeight)
		cache.lastRealWidth = width
		cache.lastSize = size
		return size
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
		let columnWidth = ((bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.toNearestOrEven)

		for subview in subviews {
			let column = subview[GridColumnKey.self]
			let row = subview[GridRowKey.self]
			let columnSpan = subview[GridColumnSpanKey.self]
			let rowSpan = subview[GridRowSpanKey.self]

			let x = bounds.minX + CGFloat(column) * (columnWidth + spacing)
			let y = bounds.minY + CGFloat(row) * (rowHeight + spacing)
			let cellWidth = (CGFloat(columnSpan) * columnWidth + CGFloat(columnSpan - 1) * spacing).rounded(.toNearestOrEven)
			let cellHeight = CGFloat(rowSpan) * rowHeight + CGFloat(rowSpan - 1) * spacing

			subview.place(
				at: CGPoint(x: x, y: y),
				proposal: ProposedViewSize(width: cellWidth, height: cellHeight)
			)
		}
	}
}

// Overview page grid with preset card spans; row heights keep card proportions
struct OverviewGrid<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		OverviewGridLayout(
			columns: 4,
			rowCount: 6,
			rowHeight: 72,
			spacing: DashboardTheme.spacingBetweenCards,
			baseWidth: 680
		) {
			content
		}
	}
}
