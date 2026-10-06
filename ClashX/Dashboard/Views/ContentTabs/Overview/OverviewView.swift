//
//  OverviewView.swift
//  ClashX Dashboard
//
//

import SwiftUI

// Overview card refresh tiers:
// - stream: heroes/totals follow the core push streams
// - polled: connections/top processes/subscription/network status poll local APIs
// - none: core version never refreshes
enum OverviewRefresh {
	static let streamInterval: TimeInterval = 1
	static let polledInterval: TimeInterval = 5
}

struct OverviewView: View {
	
	@EnvironmentObject var data: ClashOverviewData
	
	@State private var version: String = ""
	
    var body: some View {
		ScrollView {
			OverviewGrid {
				OverviewHeroItemView(name: "Upload", value: data.uploadString, color: DashboardTheme.chartGreen)
					.gridCell(column: 0, row: 0)
				OverviewHeroItemView(name: "Download", value: data.downloadString, color: DashboardTheme.chartBlue)
					.gridCell(column: 1, row: 0)
				OverviewTopItemView(name: "Download Total", value: data.downloadTotal)
					.gridCell(column: 2, row: 0)
				OverviewTopItemView(name: "Upload Total", value: data.uploadTotal)
					.gridCell(column: 3, row: 0)
				ConnectionsStatsCardView()
					.gridCell(column: 0, row: 1)
				SubscriptionUsageCardView()
					.gridCell(column: 1, row: 1)
				MemoryCardView()
					.gridCell(column: 2, row: 1)
				OverviewTopItemView(name: "Core", value: version)
					.gridCell(column: 3, row: 1)
				TrafficCardView()
					.gridCell(column: 0, row: 2, columnSpan: 2, rowSpan: 2)
				TopProcessesCardView()
					.gridCell(column: 2, row: 2, columnSpan: 2, rowSpan: 2)
				NetworkStatusCardView()
					.gridCell(column: 0, row: 4, columnSpan: 2, rowSpan: 2)
			}
			.padding(DashboardTheme.spacingPage)
		}
		.background(DashboardTheme.pageBackground)
		.task {
			await loadVersion()
		}
    }

	@MainActor
	func loadVersion() async {
		version = await ApiRequest.requestVersion()?.version ?? ""
	}
	
}