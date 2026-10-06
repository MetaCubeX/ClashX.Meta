//
//  ProxyLatencyView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProxyLatencyView: View {
	let number: Int?
	let isTesting: Bool
	var onClick: (() -> Void)?

	private var label: String {
		if isTesting { return NSLocalizedString("Testing", comment: "") }
		guard let number else { return "--" }
		return "\(number) ms"
	}

	var body: some View {
		Text(verbatim: label)
			.font(DashboardTheme.secondaryTextFont)
			.foregroundColor(number.map { DBProxy.delayColor($0) } ?? Color.secondary)
			.contentShape(Rectangle())
			.onTapGesture {
				guard !isTesting else { return }
				onClick?()
			}
			.help(label)
	}
}
