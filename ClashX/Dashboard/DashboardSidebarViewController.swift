//
//  DashboardSidebarViewController.swift
//  ClashX Meta
//

import AppKit
import SwiftUI

@MainActor
final class DashboardSidebarViewController: DashboardPaneHostViewController {
	@IBOutlet var listView: NSView!

	override var hostView: NSView? { listView }

	override func makePane(model: DashboardModel) -> NSViewController {
		let chromeState = model.chromeState
		let selection = Binding(
			get: { chromeState.selection },
			set: { chromeState.selection = $0 }
		)
		return makeHostingController(SidebarView(
			selection: selection,
			clashApiDatasStorage: model.apiDatasStorage
		))
	}
}
