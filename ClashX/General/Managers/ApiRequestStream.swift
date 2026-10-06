//
//  ApiRequestStream.swift
//  ClashX
//
//  Created by CYC on 2018/7/30.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa

import NIOHTTP1
import NIOCore

protocol ApiRequestStreamDelegate: AnyObject {
    func didUpdateTraffic(up: Int, down: Int) async
    func didGetLog(log: String, level: String) async
    func didUpdateMemory(memory: Int64) async
    func streamStatusChanged() async
}

final class ApiRequestStream {
	static let shared = ApiRequestStream()

	// App-level traffic/memory history so the dashboard opens with recent data instead of zeros
	@MainActor lazy var trafficHistoryStore = TrafficHistoryStore()

	enum StreamType: CaseIterable {
		case traffic, logging, memory
	}

	private struct TrafficMessage: Decodable {
		let up: Int
		let down: Int
	}

	private struct LogMessage: Decodable {
		let payload: String
		let type: String?
	}

	private struct MemoryMessage: Decodable {
		let inuse: Int64
	}

	private static let decoder = JSONDecoder()

	@MainActor
	private struct WeakObserver {
		weak var value: ApiRequestStreamDelegate?
	}

	@MainActor
	private var observers: [WeakObserver] = []

	@MainActor
	var hasObservers: Bool {
		observers.contains { $0.value != nil }
	}

	@MainActor
	func addObserver(_ observer: ApiRequestStreamDelegate) {
		removeObserver(observer)
		observers.append(WeakObserver(value: observer))
	}

	@MainActor
	func removeObserver(_ observer: ApiRequestStreamDelegate) {
		observers.removeAll { $0.value === observer || $0.value == nil }
	}

	private init() {}

	@MainActor
	private var streamTasks: [StreamType: Task<Void, Never>] = [:]
	@MainActor
	private var streamGenerations: [StreamType: UUID] = [:]
	@MainActor
	private var streamRetryTasks: [StreamType: Task<Void, Never>] = [:]
	@MainActor
	private var streamRetryDelays: [StreamType: TimeInterval] = [.traffic: 1, .logging: 1, .memory: 1]
	@MainActor
	private var isCoreProcessAlive = true
	@MainActor
	private var isTerminating = false

	private let logRateLimiter = LogRateLimiter {
		let alert = NSAlert()
		alert.messageText = NSLocalizedString("Log system crashed.", comment: "")
		alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
		let response = alert.runModal()
		if response == .alertFirstButtonReturn {
			Task {
				await ExitManager.shared.requestQuit(force: true)
			}
		}
	}

	@MainActor
	func resetStreamApis() {
		isCoreProcessAlive = true
		StreamType.allCases.forEach { resetStreamApi(for: $0) }
	}

	@MainActor
	func resetStreamApi(for type: StreamType) {
		let requiresCoreRunning = type != .traffic || ConfigManager.shared.kernelState.isOperational
		guard requiresCoreRunning else { return }
		cancelRetryTask(for: type)
		streamRetryDelays[type] = 1
		startStream(for: type)
	}

	private func streamUri(for type: StreamType) -> String {
		switch type {
		case .traffic:
			"/traffic"
		case .logging:
			"/logs?level=\(ConfigOverride.shared.logLevel.rawValue)"
		case .memory:
			"/memory"
		}
	}

	@MainActor
	private func startStream(for type: StreamType) {
		cancelRetryTask(for: type)
		streamTasks[type]?.cancel()

		let uri = streamUri(for: type)
		let generation = UUID()
		streamGenerations[type] = generation

		streamTasks[type] = Task { @MainActor [weak self] in
			do {
				let requiresCoreRunning = ConfigManager.shared.kernelState.isOperational

				let stream = await ApiRequestTransport.req(uri, requiresCoreRunning: requiresCoreRunning).stream
				var didConnect = false
				for try await line in stream {
					if !didConnect {
						didConnect = true
						await self?.streamDidConnect(type)
					}
					await self?.streamDidReceiveMessage(type, text: line)
				}
				await self?.streamDidDisconnect(type, error: nil, generation: generation)
			} catch {
				await self?.streamDidDisconnect(type, error: error, generation: generation)
			}
		}
	}

	@MainActor
	private func cancelRetryTask(for type: StreamType) {
		streamRetryTasks[type]?.cancel()
		streamRetryTasks[type] = nil
	}

	@MainActor
	private func scheduleRetry(for type: StreamType) {
		guard !isTerminating else { return }
		let delay = streamRetryDelays[type] ?? 1
		cancelRetryTask(for: type)
		streamRetryTasks[type] = Task { @MainActor [weak self] in
			try? await Task.sleep(seconds: delay)
			guard let self, !Task.isCancelled, !self.isTerminating else { return }
			self.startStream(for: type)
		}
		streamRetryDelays[type] = delay * 2
	}

	@MainActor
	func prepareForTermination() {
		isTerminating = true
		streamTasks.values.forEach { $0.cancel() }
		streamRetryTasks.values.forEach { $0.cancel() }
		streamTasks.removeAll()
		streamRetryTasks.removeAll()
	}

	// MARK: Notify Observers

	@MainActor
	private func forEachObserver(_ body: (ApiRequestStreamDelegate) async -> Void) async {
		var remaining: [WeakObserver] = []
		for observer in observers {
			if let value = observer.value {
				await body(value)
				remaining.append(observer)
			}
		}
		observers = remaining
	}

	@MainActor
	private func notifyStreamStatusChanged() async {
		if !ConfigManager.shared.kernelState.isOperational {
			trafficHistoryStore.reset()
		}
		await forEachObserver { await $0.streamStatusChanged() }
	}

	@MainActor
	private func notifyTrafficUpdate(up: Int, down: Int) async {
		trafficHistoryStore.appendTraffic(up: up, down: down)
		await forEachObserver { await $0.didUpdateTraffic(up: up, down: down) }
	}

	private func notifyLog(log: String, level: String) async {
		await forEachObserver { await $0.didGetLog(log: log, level: level) }
	}

	@MainActor
	private func notifyMemoryUpdate(memory: Int64) async {
		trafficHistoryStore.appendMemory(memory)
		await forEachObserver { await $0.didUpdateMemory(memory: memory) }
	}

	// MARK: Stream Event Handlers

	@MainActor
	private func streamDidConnect(_ type: StreamType) async {
		streamRetryDelays[type] = 1
		Logger.log("\(type)Stream did Connect", level: .debug)

		if type == .traffic {
			await notifyStreamStatusChanged()
		}
	}

	@MainActor
	private func streamDidDisconnect(_ type: StreamType, error: Error?, generation: UUID) async {
		guard streamGenerations[type] == generation else { return }

		if let err = error, (err as? HTTPParserError) != .invalidEOFState {
			Logger.log("\(type)Stream did disconnect with error: \(err.localizedDescription)", level: .error)
		}

		Logger.log("\(type)Stream did disconnect", level: .debug)

		// A dropped traffic/memory stream means the core stopped; history is stale
		if type == .traffic || type == .memory {
			trafficHistoryStore.reset()
		}

		if type == .logging {
			await verifyCoreHealthAfterStreamDisconnect()
		} else if type == .traffic {
			await notifyTrafficUpdate(up: 0, down: 0)
		}
		scheduleRetry(for: type)
	}

	// MARK: Core Health Verification
	// Stream events only trigger the check; kernel state is decided by /version + launchctl.

	private enum CoreHealth {
		case alive
		case crashed
		case unknown
	}

	@MainActor
	private func verifyCoreHealthAfterStreamDisconnect() async {
		guard !isTerminating else { return }
		let state = ConfigManager.shared.kernelState
		guard state.isOperational || state == .disconnected else { return }

		let health = await verifyCoreHealth()

		// Ignore the result if the core was restarted during verification.
		let currentState = ConfigManager.shared.kernelState
		guard !isTerminating, currentState.isOperational || currentState == .disconnected else { return }
		Logger.log("Core health verdict: \(health). kernelState: \(currentState)", level: .info)

		switch health {
		case .alive:
			if currentState == .disconnected {
				ConfigManager.shared.kernelState = .running
				await notifyStreamStatusChanged()
			}
		case .crashed:
			guard isCoreProcessAlive else { return }
			isCoreProcessAlive = false
			await UserNotificationCenter.shared.postCoreCrashNotice()
		case .unknown:
			if currentState.isOperational {
				ConfigManager.shared.kernelState = .disconnected
				await notifyStreamStatusChanged()
			}
		}
	}

	@MainActor
	private func verifyCoreHealth() async -> CoreHealth {
		// Layer 1: pick by mode, not fallback chain.
		let isRestfulMode = RemoteControlManager.selectConfig != nil || ApiRequestTransport.debugUseHttpApi

		if isRestfulMode {
			if await ApiRequest.requestVersion(timeout: .seconds(2)) != nil {
				return .alive
			}
		} else {
			if let socketPath = ApiRequestTransport.unixSocketPath,
			   await Self.probeUnixSocket(socketPath) {
				return .alive
			}
		}

		// Remote control mode: the core is not local, launchd is meaningless.
		guard RemoteControlManager.selectConfig == nil else {
			return .unknown
		}

		guard let status = await ClashProcess.metaLaunchdStatus() else {
			Logger.log("Core health: launchd status unavailable", level: .error)
			return .unknown
		}

		Logger.log("Core health: launchd pid=\(status.pid.map(String.init) ?? "nil") lastExitCode=\(status.lastExitCode ?? "nil") lastSignal=\(status.lastTerminatingSignal ?? "nil")", level: .info)

		if status.isRunning {
			return .alive
		}

		if let exitCode = status.lastExitCode, exitCode != "(never exited)" {
			Logger.log("Core process exited with code \(exitCode)", level: .error)
			return .crashed
		}

		if let signal = status.lastTerminatingSignal, !signal.isEmpty {
			Logger.log("Core process terminated by \(signal)", level: .error)
			return .crashed
		}

		return .unknown
	}

	private static func probeUnixSocket(_ path: String) async -> Bool {
		await withCheckedContinuation { continuation in
			DispatchQueue.global().async {
				let fd = socket(AF_UNIX, SOCK_STREAM, 0)
				guard fd >= 0 else {
					continuation.resume(returning: false)
					return
				}
				defer { close(fd) }

				var addr = sockaddr_un()
				addr.sun_family = sa_family_t(AF_UNIX)
				let pathBytes = Array(path.utf8)
				guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
					continuation.resume(returning: false)
					return
				}
				pathBytes.withUnsafeBufferPointer { buf in
					withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
						buf.baseAddress?.withMemoryRebound(to: Int8.self, capacity: buf.count) { src in
							memcpy(sunPath, src, buf.count)
						}
					}
				}

				let result = withUnsafePointer(to: &addr) { ptr in
					ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
						connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
					}
				}
				continuation.resume(returning: result == 0)
			}
		}
	}

	@MainActor
	private func streamDidReceiveMessage(_ type: StreamType, text: String) async {
		switch type {
		case .traffic:
			guard let message = try? Self.decoder.decode(TrafficMessage.self, from: Data(text.utf8)) else { return }
			await notifyTrafficUpdate(up: message.up, down: message.down)
		case .logging:
			guard await logRateLimiter.processLog() else { return }
			guard let message = try? Self.decoder.decode(LogMessage.self, from: Data(text.utf8)) else { return }
			await notifyLog(log: message.payload, level: message.type ?? "info")
		case .memory:
			guard let message = try? Self.decoder.decode(MemoryMessage.self, from: Data(text.utf8)) else { return }
			await notifyMemoryUpdate(memory: message.inuse)
		}
	}
}
