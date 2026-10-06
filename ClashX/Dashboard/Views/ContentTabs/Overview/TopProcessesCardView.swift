//
//  TopProcessesCardView.swift
//  ClashX Dashboard
//
//

import SwiftUI

// Per-app traffic ranking aggregated from the live connection list
struct TopProcessesCardView: View {
	@EnvironmentObject private var poller: TopAppsPoller

	var body: some View {
		OverviewCard {
			VStack(alignment: .leading, spacing: DashboardTheme.spacingRowInner) {
				Text("Top Processes")
					.font(DashboardTheme.titleFont)
				ForEach(poller.topApps) { app in
					rowView(app)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		}
	}

	private func rowView(_ app: TopAppsPoller.TopApp) -> some View {
		HStack(spacing: DashboardTheme.spacingRowInner) {
			Text(verbatim: app.name)
				.font(DashboardTheme.overviewLabelFont)
				.lineLimit(1)
				.frame(maxWidth: .infinity, alignment: .leading)
			GeometryReader { proxy in
				Capsule()
					.fill(DashboardTheme.usageBarFill)
					.frame(width: proxy.size.width * app.ratio, height: 4)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(width: 90, height: 4)
			Text(verbatim: ByteFormat.total(app.bytes, precision: .integer))
				.font(DashboardTheme.overviewLabelFont)
				.foregroundColor(.secondary)
				.monospacedDigit()
				.lineLimit(1)
				.frame(width: 60, alignment: .trailing)
		}
	}
}
