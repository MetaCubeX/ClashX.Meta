//
//  SidebarView.swift
//  ClashX Dashboard
//
//

import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

struct SidebarView: View {
	
	@Binding var selection: SidebarItem?
	
	let clashApiDatasStorage: ClashApiDatasStorage
	
	@State private var reloadID = UUID().uuidString
	@State private var updateConnectionsTask: Task<Void, Never>?
	@State private var pollingTask: Task<Void, Never>?
	@State private var localSelection: SidebarItem?
	// Chained in-flight tasks outlive onDisappear cancellation; this gates apply.
	@State private var isActive = false
	
    var body: some View {
		List(selection: $localSelection) {
			SidebarLabel(item: .overview)
				.tag(SidebarItem.overview)
			
			SidebarLabel(item: .proxies)
				.tag(SidebarItem.proxies)
			
			SidebarLabel(item: .rules)
				.tag(SidebarItem.rules)
			
			SidebarLabel(item: .conns)
				.tag(SidebarItem.conns)
			
			SidebarLabel(item: .config)
				.tag(SidebarItem.config)
			
			SidebarLabel(item: .logs)
				.tag(SidebarItem.logs)
		}
		.introspect(.table, on: .macOS(.v12...)) {
			$0.refusesFirstResponder = true
			$0.allowsEmptySelection = false
		}
		.listStyle(.sidebar)
		.id(reloadID)
		.onAppear { localSelection = selection }
		.onChange(of: selection) { newValue in
			if newValue != localSelection {
				localSelection = newValue
			}
		}
		.onChange(of: localSelection) { newValue in
			Task { @MainActor in
				if newValue != selection {
					selection = newValue
				}
			}
		}
		.onAppear {
			isActive = true
			if ConfigOverride.shared.logLevel == .unknow {
				ConfigOverride.shared.logLevel = .info
			}
			
			clashApiDatasStorage.resetStreamApi()
			clashApiDatasStorage.seedHistoryFromStore()
			clashApiDatasStorage.connsStorage.reset()
			
			updateConnections()
			startPollingConnections()
		}
		.onReceive(NotificationCenter.default.publisher(for: .reloadDashboard)) { _ in
			reloadID = UUID().uuidString
		}
		.onDisappear {
			isActive = false
			pollingTask?.cancel()
			pollingTask = nil
			updateConnectionsTask?.cancel()
			updateConnectionsTask = nil
		}
	}

	func startPollingConnections() {
		pollingTask?.cancel()
		pollingTask = Task { @MainActor in
			let clock = ContinuousClock()
			while !Task.isCancelled {
				try? await clock.sleep(for: .seconds(1))
				guard !Task.isCancelled else { return }
				updateConnections()
			}
		}
	}
	
	func updateConnections() {
		let previousTask = updateConnectionsTask
		updateConnectionsTask = Task { @MainActor in
			await previousTask?.value
			guard !Task.isCancelled, isActive,
				  let snap = await ApiRequest.getConnectionsSnapshot(),
				  !Task.isCancelled else { return }
			applyConnectionsSnapshot(snap)
		}
	}

	func applyConnectionsSnapshot(_ snap: DBConnectionSnapShot) {
		// While paused, skip everything (aligned with upstream yacd).
		guard !clashApiDatasStorage.connsStorage.isPaused else { return }
		clashApiDatasStorage.overviewData.upTotal = snap.uploadTotal
		clashApiDatasStorage.overviewData.downTotal = snap.downloadTotal
		clashApiDatasStorage.overviewData.activeConns = "\(snap.connections.count)"
		clashApiDatasStorage.connsStorage.apply(snap)
	}
}
