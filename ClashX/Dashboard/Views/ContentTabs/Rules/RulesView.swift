//
//  RulesView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct RulesView: View {
	
	@State var ruleItems = [ClashRule]()
	@State private var columnWidths = RuleColumnWidths(ruleItems: [])
	
	@EnvironmentObject var toolbarState: DashboardToolbarState
	@State private var searchString: String = ""
	
	
	var rules: [EnumeratedSequence<[ClashRule]>.Element] {
		if searchString.isEmpty {
			return Array(ruleItems.enumerated())
		} else {
			return Array(ruleItems.filtered(searchString, for: ["type", "payload", "proxy"]).enumerated())
		}
	}
	
	
	var body: some View {
		ScrollView {
			LazyVStack(spacing: 0) {
				ForEach(rules, id: \.element.id) { item in
					RuleItemView(index: item.offset + 1, rule: item.element, columnWidths: columnWidths)
					if item.offset < rules.count - 1 {
						Divider().opacity(0.3)
					}
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius))
			.overlay(
				RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius)
					.stroke(DashboardTheme.cardBorder, lineWidth: DashboardTheme.cardBorderWidth)
			)
			.padding(DashboardTheme.spacingPage)
		}
		.background(DashboardTheme.pageBackground)
		.onAppear {
			searchString = toolbarState.searchText
		}
		.onChange(of: toolbarState.searchText) { newValue in
			searchString = newValue
		}
		.task {
			await loadRules()
		}
	}
	
	func loadRules() async {
		async let providerResponse = ApiRequest.requestRuleProviderList()
		async let rulesResponse = ApiRequest.getRules()
		
		let providerRuleCounts = await providerResponse.allProviders.values.reduce(into: [ClashProviderName: Int]()) {
			$0[$1.name] = $1.ruleCount
		}
		let items = await rulesResponse
		
		items.indices.forEach { index in
			guard let payload = items[index].payload,
				  let ruleCount = providerRuleCounts[payload] else { return }
			items[index].size = ruleCount
		}
		
		guard !Task.isCancelled else { return }
		columnWidths = RuleColumnWidths(ruleItems: items)
		ruleItems = items
	}
}