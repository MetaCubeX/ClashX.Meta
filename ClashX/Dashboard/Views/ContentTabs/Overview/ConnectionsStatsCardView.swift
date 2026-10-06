//
//  ConnectionsStatsCardView.swift
//  ClashX Dashboard
//

import SwiftUI

struct ConnectionsStatsCardView: View {
	@EnvironmentObject private var poller: ConnectionsStatsPoller

	var body: some View {
		OverviewStatCard(title: {
			HStack(spacing: DashboardTheme.spacingRowInner) {
				Text("Connections")
				Text(verbatim: "\(poller.totalCount)")
					.monospacedDigit()
			}
		}) {
			Text(verbatim: poller.statsString)
				.font(DashboardTheme.overviewValueFont)
				.lineLimit(1)
				.minimumScaleFactor(0.6)
		}
	}
}
