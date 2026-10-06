//
//  DashboardManagerSwiftUI.swift
//  ClashX Meta
//
//  Copyright © 2023 west2online. All rights reserved.
//

import Cocoa
import RxSwift


class DashboardManager: NSObject {
	
	static let shared = DashboardManager()

	let appNameResolver = AppNameResolver()

	override init() {
	}
	
	var useSwiftUI: Bool {
		get {
			return ConfigManager.useSwiftUIDashboard
		}
		set {
			ConfigManager.useSwiftUIDashboard = newValue
			
			if newValue {
				clashWebWindowController?.close()
			} else {
				dashboardWindowController?.close()
			}
		}
	}
	var dashboardWindowController: DashboardWindowController?
	
	var clashWebWindowController: ClashWebViewWindowController?

	func show(_ sender: NSMenuItem?) {
		if useSwiftUI {
			clashWebWindowController = nil
			showSwiftUIWindow(sender)
		} else {
			dashboardWindowController = nil
			showWebWindow(sender)
		}
	}
	
	func showWebWindow(_ sender: NSMenuItem?) {
		if clashWebWindowController == nil {
			clashWebWindowController = ClashWebViewWindowController.create()
			clashWebWindowController?.onWindowClose = {
				[weak self] in
				self?.clashWebWindowController = nil
			}
		}
		clashWebWindowController?.showWindow(sender)
	}
	
}

extension DashboardManager {
	func showSwiftUIWindow(_ sender: NSMenuItem?) {
		if dashboardWindowController == nil {
			dashboardWindowController = DashboardWindowController.create()
			dashboardWindowController?.onWindowClose = {
				[weak self] in
				self?.dashboardWindowController = nil
			}
		}
		
		dashboardWindowController?.set(ConfigManager.apiUrl, secret: ConfigManager.shared.overrideSecret ?? ConfigManager.shared.apiSecret)
		
		dashboardWindowController?.showWindow(sender)
	}
	
}
