//
//  DashboardViewContoller.swift
//  ClashX
//
//  Created by yicheng on 2018/8/28.
//  Copyright © 2018年 west2online. All rights reserved.
//

import Cocoa
import SwiftUI

public class DashboardWindowController: NSWindowController {
    private static let storyboardName = NSStoryboard.Name("Dashboard")

    public var onWindowClose: (() -> Void)?

	public static func create() -> DashboardWindowController {
		let controller = NSStoryboard(name: storyboardName, bundle: Bundle.main)
			.instantiateInitialController()

		guard let controller = controller as? DashboardWindowController else {
			fatalError("Failed to instantiate DashboardWindowController from Dashboard.storyboard")
		}

		return controller
    }

	public override func windowDidLoad() {
		super.windowDidLoad()

		guard let window else { return }
		window.delegate = self
		window.styleMask.insert(.fullSizeContentView)
		window.isOpaque = false
		window.title = "Dashboard"
	}

	public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(self)
    }
	
	public func set(_ apiURL: String, secret: String? = nil) {
		ConfigManager.shared.overrideApiURL = .init(string: apiURL)
		ConfigManager.shared.overrideSecret = secret
	}
}

extension DashboardWindowController: NSWindowDelegate {
	public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onWindowClose?()
    }
}

final class DashboardViewContoller: NSViewController {
	let chromeState = DashboardChromeState()
	let toolbarState = DashboardToolbarState()
	let apiDatasStorage = ClashApiDatasStorage()

	private var toolbarController: DashboardToolbarController?
	private var didAttachToolbar = false

	override func loadView() {
		view = NSHostingView(rootView: DashboardView(
			chromeState: chromeState,
			toolbarState: toolbarState,
			apiDatasStorage: apiDatasStorage
		))
    }

	override func viewWillAppear() {
		super.viewWillAppear()
		if NSApp.activationPolicy() == .accessory {
			NSApp.setActivationPolicy(.regular)
		}
		attachToolbarIfNeeded()
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		// Retry if viewWillAppear ran before the view had a window.
		attachToolbarIfNeeded()
	}

	private func attachToolbarIfNeeded() {
		guard !didAttachToolbar else { return }
		guard let window = view.window else {
			Logger.log("[Dashboard] attachToolbar skipped: view.window is NIL", level: .warning)
			return
		}
		didAttachToolbar = true
		let controller = DashboardToolbarController(
			chromeState: chromeState,
			toolbarState: toolbarState,
			connsStorage: apiDatasStorage.connsStorage
		)
		controller.attach(to: window)
		toolbarController = controller
	}

    deinit {
        NSApp.setActivationPolicy(.accessory)
    }
}
