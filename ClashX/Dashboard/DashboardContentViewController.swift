//
//  DashboardContentViewController.swift
//  ClashX Meta
//

import AppKit
import SwiftUI

@MainActor
final class DashboardContentViewController: DashboardPaneHostViewController {
	@IBOutlet var contentView: NSView!

	override var hostView: NSView? { contentView }

	override func makePane(model: DashboardModel) -> NSViewController {
		makeHostingController(DashboardView(
			chromeState: model.chromeState,
			toolbarState: model.toolbarState,
			apiDatasStorage: model.apiDatasStorage
		))
	}
}
