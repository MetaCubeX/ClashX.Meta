//
//  SubscriptionUsageCardView.swift
//  ClashX Dashboard
//

import SwiftUI

struct SubscriptionUsageCardView: View {
	@EnvironmentObject private var poller: SubscriptionPoller

	var body: some View {
		OverviewStatCard(title: {
			HStack(spacing: DashboardTheme.spacingRowInner) {
				Text("Subscription Usage")
				Text(verbatim: poller.display?.totalText ?? "—")
					.monospacedDigit()
			}
		}) {
			if let display = poller.display {
				HStack(spacing: DashboardTheme.spacingRowInner) {
					Gauge(value: display.ratio) { }
						.gaugeStyle(UsageGaugeStyle(
							height: 4.5,
							trackColor: DashboardTheme.cellBackground,
							fillColor: Color.accentColor))
						.accessibilityLabel(Text(verbatim:
							[display.percentText, display.helpText].joined(separator: ", ")))
					Text(verbatim: display.percentText)
						.font(DashboardTheme.overviewValueFont)
						.monospacedDigit()
						.layoutPriority(1)
				}
			}
		}
		.help(poller.display?.helpText ?? "")
	}
}

private struct UsageGaugeStyle: GaugeStyle {
	let height: CGFloat
	let trackColor: Color
	let fillColor: Color

	func makeBody(configuration: Configuration) -> some View {
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				Capsule().fill(trackColor)
				Capsule()
					.fill(fillColor)
					.frame(width: proxy.size.width * CGFloat(configuration.value))
			}
		}
		.frame(height: height)
	}
}
