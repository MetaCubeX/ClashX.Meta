//
//  ClashApiDatasStorage.swift
//  ClashX Dashboard
//
//

import Cocoa
import SwiftUI
import CocoaLumberjackSwift

@MainActor
class ClashApiDatasStorage: NSObject, ObservableObject {
	private static let memoryFormatter = ByteCountFormatter()
	
	@Published var overviewData = ClashOverviewData()
	
	@Published var logStorage = ClashLogStorage()
	@Published var connsStorage = ClashConnsStorage()

	private var pendingTraffic: (up: Int, down: Int)?
	private var pendingLogs = [(level: String, log: String)]()
	private var uiUpdateTask: Task<Void, Never>?

	override init() {
		super.init()
		uiUpdateTask = Task { @MainActor [weak self] in
			let clock = ContinuousClock()
			while !Task.isCancelled {
				try? await clock.sleep(for: .seconds(1))
				guard let self else { return }
				self.flushPendingUpdates()
			}
		}
	}

	deinit {
		uiUpdateTask?.cancel()
	}
	
	func resetStreamApi() {
		let needsStreamStart = !ApiRequestStream.shared.hasObservers
		ApiRequestStream.shared.addObserver(self)
		if needsStreamStart {
			ApiRequestStream.shared.resetStreamApis()
		}
	}

	// Seed history from ApiRequestStream so the dashboard opens with recent data instead of zeros
	func seedHistoryFromStore() {
		let store = ApiRequestStream.shared.trafficHistoryStore
		overviewData.downloadHistories = store.down
		overviewData.uploadHistories = store.up
		overviewData.memoryHistories = store.memory.map(CGFloat.init)
		if let memory = store.latestMemory {
			overviewData.memory = Self.memoryFormatter.string(fromByteCount: memory)
		}
		Logger.log("seed memory history: first=\(store.memory.first ?? -1) last=\(store.memory.last ?? -1) count=\(store.memory.count)", level: .debug)
	}
}

extension ClashApiDatasStorage: ApiRequestStreamDelegate {
    func streamStatusChanged() async {
    }

	func didUpdateTraffic(up: Int, down: Int) async {
        enqueueTrafficUpdate(up: up, down: down)
	}
	
	func didGetLog(log: String, level: String) async {
        enqueueLog(level: level, log: log)
	}
	
	func didUpdateMemory(memory: Int64) async {
		// Store handles sampling and history; nothing to do here
	}

	func enqueueTrafficUpdate(up: Int, down: Int) {
		pendingTraffic = (up: up, down: down)
	}

	func enqueueLog(level: String, log: String) {
		pendingLogs.append((level: level, log: log))
	}

	func flushPendingUpdates() {
		if let traffic = pendingTraffic {
			overviewData.down = traffic.down
			overviewData.up = traffic.up
			pendingTraffic = nil
		}

		if !pendingLogs.isEmpty {
			logStorage.logs.append(contentsOf: pendingLogs.map { .init(level: $0.level, log: $0.log) })
			pendingLogs.removeAll(keepingCapacity: true)

			if logStorage.logs.count > 1000 {
				logStorage.logs.removeFirst(100)
			}
		}

		// Sync history straight from the store; all sampling happens there.
		// Skip identical values so idle sessions don't invalidate cards every tick.
		let store = ApiRequestStream.shared.trafficHistoryStore
		let down = store.down
		if overviewData.downloadHistories != down { overviewData.downloadHistories = down }
		let up = store.up
		if overviewData.uploadHistories != up { overviewData.uploadHistories = up }
		let memoryHistory = store.memory.map(CGFloat.init)
		if overviewData.memoryHistories != memoryHistory { overviewData.memoryHistories = memoryHistory }
		if let memory = store.latestMemory {
			let text = Self.memoryFormatter.string(fromByteCount: memory)
			if overviewData.memory != text { overviewData.memory = text }
		}
	}
	
}

fileprivate let TrafficHistoryLimit = 30
fileprivate let MemoryHistoryLimit = 15

class ClashOverviewData: ObservableObject, Identifiable {
	let id = UUID().uuidString

	private static let memoryFormatter = ByteCountFormatter()
	
	@Published var uploadString = "N/A"
	@Published var downloadString = "N/A"
	
	@Published var downloadTotal = "N/A"
	@Published var uploadTotal = "N/A"
	
	@Published var activeConns = "0"
	
	@Published var memory = "0 MB"
	
	@Published var downloadHistories = [CGFloat](repeating: 0, count: TrafficHistoryLimit)
	@Published var uploadHistories = [CGFloat](repeating: 0, count: TrafficHistoryLimit)
	@Published var memoryHistories = [CGFloat](repeating: 0, count: MemoryHistoryLimit)

	var down: Int = 0 {
		didSet {
			downloadString = ByteFormat.rate(down)
		}
	}

	var up: Int = 0 {
		didSet {
			uploadString = ByteFormat.rate(up)
		}
	}

	var downTotal: Int = 0 {
		didSet {
			downloadTotal = ByteFormat.total(Int64(downTotal))
		}
	}

	var upTotal: Int = 0 {
		didSet {
			uploadTotal = ByteFormat.total(Int64(upTotal))
		}
	}
}

class ClashLogStorage: ObservableObject {
	@Published var logs = [ClashLog]()
	
	class ClashLog: NSObject, ObservableObject {
		let id: String
		
		let date: Date
		let level: ClashLogLevel
		@objc let log: String
		
		let levelColor: NSColor
		@objc let levelString: String
		
		init(level: String, log: String) {
			id = UUID().uuidString
			date = Date()
			
			self.level = .init(rawValue: level) ?? .unknow
			self.log = log
			
			self.levelString = level
			switch self.level {
			case .info:
				levelColor = .systemBlue
			case .warning:
				levelColor = .systemYellow
			case .error:
				levelColor = .systemRed
			case .debug:
				levelColor = .systemGreen
			default:
				levelColor = .white
			}
		}
	}
}

@MainActor
class ClashConnsStorage: ObservableObject {
	static let maxClosedConnections = 200

	@Published var conns = [DBConnection]()
	/// Closed connections, newest first, capped at `maxClosedConnections`.
	@Published private(set) var closedConns = [DBConnection]()
	/// While paused all processing is skipped (aligned with upstream yacd); the next resume diffs across the whole gap.
	@Published var isPaused = false

	/// Last applied snapshot; the closed-detection diff runs against this.
	private var trackedConns = [DBConnection]()

    /// Nonisolated so an empty instance can be built from nonisolated contexts (e.g. EnvironmentKey.defaultValue).
    nonisolated init() {}

	func apply(_ snapshot: DBConnectionSnapShot) {
		guard !isPaused else { return }
		defer { trackedConns = snapshot.connections }

		let activeIDs = Set(snapshot.connections.map(\.id))
		let newlyClosed = trackedConns.filter { !activeIDs.contains($0.id) }
		if !newlyClosed.isEmpty {
			var seen = Set(newlyClosed.map(\.id))
			var merged = newlyClosed
			for old in closedConns where seen.insert(old.id).inserted {
				merged.append(old)
			}
			closedConns = Array(merged.prefix(Self.maxClosedConnections))
		}

		conns = snapshot.connections
	}

	func reset() {
		conns.removeAll()
		closedConns.removeAll()
		trackedConns.removeAll()
	}
}

extension ClashConnsStorage {
	/// Unique sorted source IPs across active + closed connections.
	var allSourceIPs: [String] {
		var set = Set(conns.map(\.metadata.sourceIP))
		set.formUnion(closedConns.map(\.metadata.sourceIP))
		return set.filter { !$0.isEmpty }.sorted()
	}
}

extension DBConnection {
	/// Keyword + source IP filter matching the table's filter keys.
	func matches(keyword: String, sourceIP: String) -> Bool {
		if !sourceIP.isEmpty, metadata.sourceIP != sourceIP { return false }
		let trimmed = keyword.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return true }
		let key = trimmed.lowercased()
		let candidates: [String] = [
			metadata.host,
			metadata.sniffHost,
			metadata.process,
			chains.reversed().joined(separator: "/"),
			rulePayload.isEmpty ? rule : "\(rule) :: \(rulePayload)",
			"\(metadata.sourceIP):\(metadata.sourcePort)",
			metadata.remoteDestination,
			metadata.destinationIP,
			"\(metadata.type)(\(metadata.network))",
		]
		return candidates.contains { $0.lowercased().contains(key) }
	}
}
