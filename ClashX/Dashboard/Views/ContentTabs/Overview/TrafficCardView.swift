//
//  TrafficCardView.swift
//  ClashX Dashboard
//
//

import SwiftUI

// Traffic chart card: title, legend, and Up/Down history charts
struct TrafficCardView: View {
	@EnvironmentObject private var overview: ClashOverviewData

	var body: some View {
		OverviewCard {
			VStack(alignment: .leading, spacing: 2) {
				Text("Traffic")
					.font(DashboardTheme.titleFont)

				legendItem(color: DashboardTheme.chartGreen, name: "Up")
				TrafficGraphView(values: .constant(overview.uploadHistories),
								 graphColor: DashboardTheme.chartGreen)

				legendItem(color: DashboardTheme.chartBlue, name: "Down")
					.padding(.top, 16)
				TrafficGraphView(values: .constant(overview.downloadHistories),
								 graphColor: DashboardTheme.chartBlue)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		}
	}

	private func legendItem(color: Color, name: LocalizedStringKey) -> some View {
		HStack(spacing: DashboardTheme.spacingRowInner) {
			RoundedRectangle(cornerRadius: 2)
				.fill(color)
				.frame(width: 14, height: 9)
			Text(name)
				.font(DashboardTheme.overviewLabelFont)
				.foregroundColor(.secondary)
		}
	}
}
