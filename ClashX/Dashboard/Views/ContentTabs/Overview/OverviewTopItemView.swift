//
//  OverviewTopItemView.swift
//  ClashX Dashboard
//

import SwiftUI

// Shared card shell for Overview; matches the card look used across the dashboard
struct OverviewCard<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		content
			.padding(DashboardTheme.spacingRowH)
			.background(DashboardTheme.pageBackground)
			.cornerRadius(DashboardTheme.cardCornerRadius)
			.overlay(
				RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius)
					.stroke(DashboardTheme.cardBorder, lineWidth: DashboardTheme.cardBorderWidth)
			)
	}
}

// Small stat card: label above value
struct OverviewTopItemView: View {

	let name: LocalizedStringKey
	let value: String

	var body: some View {
		OverviewStatCard(title: { Text(name) }) {
			Text(value)
				.font(DashboardTheme.overviewValueFont)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
		}
	}
}

// Large stat card: colored dot, label and hero value
struct OverviewHeroItemView: View {

	let name: LocalizedStringKey
	let value: String
	let color: Color

	var body: some View {
		OverviewStatCard(title: {
			HStack(spacing: DashboardTheme.spacingRowInner) {
				Circle()
					.fill(color)
					.frame(width: 8, height: 8)
				Text(name)
			}
		}) {
			Text(value)
				.font(DashboardTheme.overviewValueFont)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
		}
	}
}

struct OverviewTopItemView_Previews: PreviewProvider {
	static var previews: some View {
		VStack(spacing: 12) {
			OverviewTopItemView(name: "Active Connections", value: "12")
			OverviewHeroItemView(name: "Download", value: "12.3 MB/s", color: Color(nsColor: .systemBlue))
		}
		.padding()
		.frame(width: 240)
	}
}
