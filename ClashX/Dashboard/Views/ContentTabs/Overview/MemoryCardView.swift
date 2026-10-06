//
//  MemoryCardView.swift
//  ClashX Dashboard
//

import SwiftUI

struct MemoryCardView: View {
	@EnvironmentObject private var overview: ClashOverviewData

	private let color = DashboardTheme.chartPurple

	var body: some View {
		OverviewStatCard(title: {
			HStack(spacing: DashboardTheme.spacingRowInner) {
				RoundedRectangle(cornerRadius: 2)
					.fill(color)
					.frame(width: 14, height: 9)
				Text("Memory")
				Text(verbatim: overview.memory)
					.monospacedDigit()
			}
		}) {
			TrafficGraphView(values: .constant(overview.memoryHistories),
							 graphColor: color,
							 showYAxis: false,
							 graphType: .size)
		}
	}
}
