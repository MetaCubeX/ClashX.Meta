//
//  OverviewStatCard.swift
//  ClashX Dashboard
//
//  Reusable small stat card: fixed-height title row + flexible content.
//

import SwiftUI

private let titleRowHeight = ceil(DashboardTheme.lineHeight(DashboardTheme.overviewStatTitleNSFont)) + 2

struct OverviewStatCard<Title: View, Content: View>: View {
	@ViewBuilder let title: Title
	@ViewBuilder let content: Content

	init(@ViewBuilder title: () -> Title, @ViewBuilder content: () -> Content) {
		self.title = title()
		self.content = content()
	}

	var body: some View {
		OverviewCard {
			VStack(alignment: .leading, spacing: DashboardTheme.spacingOverviewStatText) {
				title
					.font(DashboardTheme.overviewStatTitleFont)
					.foregroundColor(.secondary)
					.lineLimit(1)
					.frame(height: titleRowHeight)
				content
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		}
	}
}
