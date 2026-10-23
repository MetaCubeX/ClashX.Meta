//
//  DashboardWindowController.swift
//  ClashX
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

@MainActor
final class DashboardModel {
	let chromeState = DashboardChromeState()
	let toolbarState = DashboardToolbarState()
	let apiDatasStorage = ClashApiDatasStorage()
}

@MainActor
class DashboardPaneHostViewController: NSViewController {
	var hostView: NSView? { nil }

	private var model: DashboardModel?
	private var pane: NSViewController?

	func makePane(model: DashboardModel) -> NSViewController {
		fatalError("\(type(of: self)) must override makePane(model:)")
	}

	func makeHostingController<Content: View>(_ rootView: Content) -> NSViewController {
		let hostingController = NSHostingController(rootView: rootView)
		hostingController.sizingOptions = []
		return hostingController
	}

	func configure(model: DashboardModel) {
		precondition(pane == nil || self.model === model,
		             "pane is already mounted with another model; use replacePane(model:)")
		self.model = model
		mountIfNeeded()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		mountIfNeeded()
	}

	private func mountIfNeeded() {
		guard pane == nil, let model, isViewLoaded else { return }
		guard let hostView else {
			assertionFailure("Dashboard pane host outlet is not connected")
			return
		}

		let pane = makePane(model: model)
		addChild(pane)
		pane.view.translatesAutoresizingMaskIntoConstraints = false
		hostView.addSubview(pane.view)
		NSLayoutConstraint.activate([
			pane.view.topAnchor.constraint(equalTo: hostView.topAnchor),
			pane.view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
			pane.view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
			pane.view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
		])
		self.pane = pane
	}

	func detachPane() {
		guard let pane else { return }
		pane.removeFromParent()
		pane.view.removeFromSuperview()
		self.pane = nil
	}

	func replacePane(model: DashboardModel) {
		detachPane()
		configure(model: model)
	}
}

@MainActor
final class DashboardSplitViewController: NSSplitViewController {
	let dashboardModel = DashboardModel()

	private var toolbarController: DashboardToolbarController?
	private var didAttachToolbar = false

	override func viewDidLoad() {
		super.viewDidLoad()
		for item in splitViewItems {
			guard let paneHost = item.viewController as? DashboardPaneHostViewController else {
				assertionFailure("Dashboard split item is missing a DashboardPaneHostViewController")
				continue
			}
			paneHost.configure(model: dashboardModel)
		}
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
			chromeState: dashboardModel.chromeState,
			toolbarState: dashboardModel.toolbarState,
			connsStorage: dashboardModel.apiDatasStorage.connsStorage
		)
		controller.attach(to: window)
		toolbarController = controller
	}
}
