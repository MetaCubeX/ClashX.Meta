//
//  ApiRequest.swift
//  ClashX
//
//  Created by CYC on 2018/7/30.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa

import SwiftyJSON
import Foundation
import NIOHTTP1
import AsyncHTTPClient

protocol ApiRequestStreamDelegate: AnyObject {
    func didUpdateTraffic(up: Int, down: Int) async
    func didGetLog(log: String, level: String) async
    func didUpdateMemory(memory: Int64) async
    func streamStatusChanged() async
}

typealias ErrorString = String

struct ClashVersion: Decodable {
	let version: String
	let meta: Bool?
}

class ApiRequest {
    static let shared = ApiRequest()

    private var proxyRespCache: ClashProxyResp?
    
    @MainActor
    private var isTerminating = false

    private lazy var logQueue = DispatchQueue(label: "com.ClashX.core.log")

    @objc enum ProviderType: Int {
        case rule, proxy

        func apiString() -> String {
            self == .proxy ? "proxies" : "rules"
        }

        func logString() -> String {
            self == .proxy ? "Proxy" : "Rule"
        }
    }

    private init() {
    }

    @discardableResult
    private static func req(
        _ url: String,
        method: HTTPMethod = .GET,
        parameters: [String: Any]? = nil,
        encoding: ApiParameterEncoding = .default,
        requiresCoreRunning: Bool = true
    ) async -> ApiRequestTransport.Handle {
        await ApiRequestTransport.req(
            url,
            method: method,
            parameters: parameters,
            encoding: encoding,
            requiresCoreRunning: requiresCoreRunning
        )
    }

    static func findConfigPath(configName: String) async -> String? {
        if ICloudManager.shared.useICloudRelay.value {
            guard let url = await ICloudManager.shared.getUrl() else {
                return nil
            }
            return url.appendingPathComponent(Paths.configFileName(for: configName)).path
        } else {
            return Paths.localConfigPath(for: configName)
        }
    }

    private static func flushFakeipCacheResult() async -> Bool {
        Logger.log("FlushFakeipCache")

        let success: Bool

        let response = await req("/cache/fakeip/flush", method: .POST)
            .response
        success = response.httpResponse?.statusCode == 204

        Logger.log("FlushFakeipCache \(success ? "success" : "failed")")
        return success
    }

    private static func flushDNSCacheResult() async -> Bool {
        Logger.log("FlushDNSCache")

        let success: Bool

        let response = await req("/cache/dns/flush", method: .POST)
            .response
        success = response.httpResponse?.statusCode == 204

        Logger.log("FlushDNSCache \(success ? "success" : "failed")")
        return success
    }

    weak var delegate: ApiRequestStreamDelegate?
	weak var dashboardDelegate: ApiRequestStreamDelegate?

	enum StreamType: CaseIterable {
		case traffic, logging, memory
	}

	@MainActor
    private var streamTasks: [StreamType: Task<Void, Never>] = [:]
	@MainActor
    private var streamRetryTasks: [StreamType: Task<Void, Never>] = [:]
	@MainActor
    private var streamRetryDelays: [StreamType: TimeInterval] = [.traffic: 1, .logging: 1, .memory: 1]
	@MainActor
    private var didTrafficStreamEverConnect = false
	@MainActor
    private var isCoreProcessAlive = true
    
    private var logRateLimiter = LogRateLimiter {
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

    static func requestVersion() async -> ClashVersion? {
        do {
            return try await req("/version", requiresCoreRunning: false)
                .validate()
                .responseDecodable(ClashVersion.self)
        } catch {
            Logger.log("Request Version failed, \(error)", level: .error)
            return nil
        }
    }

    static func requestConfig() async -> ClashConfig? {
        do {
            return try await req("/configs")
                .validate()
                .responseDecodable(ClashConfig.self)
        } catch {
            Logger.log(error.localizedDescription)
            await MainActor.run {
                UserNotificationCenter.shared.post(title: "Error", info: error.localizedDescription)
            }
            return nil
        }
    }

    static func requestConfigUpdate(configName: String) async -> ErrorString? {
        guard let path = await findConfigPath(configName: configName) else {
            return "icloud error"
        }

        guard ICloudManager.shared.useICloudRelay.value else {
            return await requestConfigUpdate(configPath: path)
        }

        #warning("icloud operation not permitted")

        let tempPath = Paths.localConfigPath(for: kSafeConfigName)

        try? FileManager.default.removeItem(atPath: tempPath)

        do {
            try FileManager.default.copyItem(atPath: path, toPath: tempPath)
        } catch {
            return "clashx_meta_config error \(error)"
        }

        return await requestConfigUpdate(configPath: tempPath)
    }

    static func requestConfigUpdate(configPath: String) async -> ErrorString? {
        let placeHolderErrorDesp = "Error occoured, Please try to fix it by restarting ClashX. "

        let response = await req(
                "/configs",
                method: .PUT,
                parameters: ["Path": configPath],
                encoding: .json
            )
            .response

        if response.httpResponse?.statusCode == 204 {
            return nil
        }

        let err = JSON(response.data ?? Data())["message"].string
            ?? response.error?.localizedDescription
            ?? placeHolderErrorDesp
        Logger.log(err)
        return err
    }

    static func updateOutBoundMode(mode: ClashProxyMode) async -> Bool {
        let response = await req(
            "/configs",
            method: .PATCH,
            parameters: ["mode": mode.rawValue],
            encoding: .json
        )
        .validate()
        .response
        return response.error == nil
    }

    static func updateLogLevel(level: ClashLogLevel) async -> Bool {
        let response = await req(
            "/configs",
            method: .PATCH,
            parameters: ["log-level": level.rawValue],
            encoding: .json
        )
        .validate()
        .response
        return response.error == nil
    }

    static func requestProxyGroupList() async -> ClashProxyResp {
        let proxies: ClashProxyResp

        do {
            let data = try await req("/proxies")
                .validate()
                .responseData
            proxies = ClashProxyResp(data)
        } catch {
            Logger.log(error.localizedDescription)
            proxies = ClashProxyResp(nil)
        }

        ApiRequest.shared.proxyRespCache = proxies
        return proxies
    }

    static func requestProxyProviderList() async -> ClashProviderResp {
        do {
            return try await req("/providers/proxies")
                .validate()
                .responseDecodable(ClashProviderResp.self)
        } catch {
            Logger.log("requestProxyProviderList error \(error.localizedDescription)")
            return ClashProviderResp()
        }
    }

    static func getAllProxyList() async -> [ClashProxyName] {
        let proxyInfo = await requestProxyGroupList()
        return proxyInfo.proxiesMap["GLOBAL"]?.all ?? []
    }

    static func updateAllowLan(allow: Bool) async {
        Logger.log("update allow lan:\(allow)", level: .debug)
        do {
            _ = try await req(
                "/configs",
                method: .PATCH,
                parameters: ["allow-lan": allow],
                encoding: .json
            )
            .validate()
            .responseData
        } catch {
            Logger.log("update allow lan failed: \(error.localizedDescription)", level: .error)
        }
    }

    static func updateProxyGroup(group: String, selectProxy: String) async -> Bool {
        let response = await req(
            "/proxies/\(group.encoded)",
            method: .PUT,
            parameters: ["name": selectProxy],
            encoding: .json
        )
        .response
        return response.httpResponse?.statusCode == 204
    }

    static func getMergedProxyData() async -> ClashProxyResp {
        async let provider = requestProxyProviderList()
        async let proxyInfo = requestProxyGroupList()

        let mergedProxyInfo = await proxyInfo
        mergedProxyInfo.updateProvider(await provider)
        return mergedProxyInfo
    }

    static func getProxyDelay(proxyName: String) async -> Int {
        do {
            let data = try await req(
                "/proxies/\(proxyName.encoded)/delay",
                method: .GET,
                parameters: ["timeout": 2500, "url": ConfigManager.shared.benchMarkUrl]
            )
            .validate()
            .responseData
            return JSON(data)["delay"].intValue
        } catch {
            return 0
        }
    }

    static func getGroupDelay(groupName: String) async -> [String: Int] {
        do {
            return try await req(
                "/group/\(groupName.encoded)/delay",
                method: .GET,
                parameters: ["timeout": 2500, "url": ConfigManager.shared.benchMarkUrl]
            )
            .validate()
            .responseDecodable([String: Int].self)
        } catch {
            return [:]
        }
    }

    static func getRules() async -> [ClashRule] {
        do {
            let data = try await req("/rules")
                .validate()
                .responseData
            return ClashRuleResponse.fromData(data).rules ?? []
        } catch {
            return []
        }
    }

    static func healthCheck(proxy: ClashProviderName) async {
        Logger.log("HeathCheck for \(proxy) started")
        let response = await req("/providers/proxies/\(proxy.encoded)/healthcheck")
            .response
        if response.httpResponse?.statusCode == 204 {
            Logger.log("HeathCheck for \(proxy) finished")
        } else {
            Logger.log("HeathCheck for \(proxy) failed:\(response.httpResponse?.statusCode ?? -1)")
        }
    }
}

// MARK: - Connections

extension ApiRequest {
    static func getConnections() async -> [ClashConnectionBaseSnapShot.Connection] {
        do {
            let snapshot = try await req("/connections")
                .validate()
                .responseDecodable(ClashConnectionBaseSnapShot.self)
            return snapshot.connections
        } catch {
            assertionFailure()
            return []
        }
    }

    static func closeConnection(_ id: String) async {
            _ = try? await req("/connections/\(id)", method: .DELETE)
                .validate()
                .responseData
    }
	
	static func getConnectionsSnapshot() async -> DBConnectionSnapShot? {
		do {
			return try await req("/connections")
				.validate()
				.responseDecodable(DBConnectionSnapShot.self)
		} catch {
			return nil
		}
	}

	static func closeConnection(_ conn: ClashConnectionSnapShot.Connection) async {
            _ = try? await req("/connections/".appending(conn.id), method: .DELETE)
                .validate()
                .responseData
	}

	static func closeAllConnection() async {
            _ = try? await req("/connections", method: .DELETE)
                .validate()
                .responseData
	}
}

// MARK: - Meta

extension ApiRequest {
    static func updateAllProviders(for type: ProviderType) async -> Int {
        let providerNames: [String]

        if type == .proxy {
            let response = await requestProxyProviderList()
            providerNames = response.allProviders
                .filter { $0.value.vehicleType == .HTTP }
                .map(\.key)
        } else {
            let response = await requestRuleProviderList()
            providerNames = response.allProviders.map(\.key)
        }

        return await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for name in providerNames {
                group.addTask {
                    await !updateProvider(for: type, name: name)
                }
            }

            var failuresCount = 0
            for await didFail in group {
                if didFail {
                    failuresCount += 1
                }
            }
            return failuresCount
        }
    }

    static func updateProvider(for type: ProviderType, name: String) async -> Bool {
        let logTitle = "Update \(type.logString()) Provider"

        Logger.log("\(logTitle) \(name)")

        let response = await req("/providers/\(type.apiString())/\(name)", method: .PUT)
            .response
        let success = response.httpResponse?.statusCode == 204

        Logger.log("\(logTitle) \(name) \(success ? "success" : "failed")")
        return success
    }

    static func requestRuleProviderList() async -> ClashRuleProviderResp {
        do {
            return try await req("/providers/rules")
                .validate()
                .responseDecodable(ClashRuleProviderResp.self)
        } catch {
            Logger.log("Get Rule providers error \(error.localizedDescription)")
            return ClashRuleProviderResp()
        }
    }

    static func flushDNSCache() async {
        async let flushFakeipCache = flushFakeipCacheResult()
        async let flushDNSCache = flushDNSCacheResult()

        let flushFakeipCacheResult = await flushFakeipCache
        let flushDNSCacheResult = await flushDNSCache
        let info = (flushFakeipCacheResult && flushDNSCacheResult) ? "Success" : "Failed"

        await MainActor.run {
            UserNotificationCenter.shared.post(title: NSLocalizedString("Flush dns cache", comment: ""), info: info)
        }
    }

    static func updateGEO() async -> Bool {
        Logger.log("UpdateGEO")
        let response = await req("/configs/geo", method: .POST)
            .response
        let success = response.httpResponse?.statusCode == 204
        Logger.log("Updating GEO Databases...")
        return success
    }

    static func updateTun(enable: Bool) async {
        Logger.log("update tun:\(enable)", level: .debug)
        do {
            _ = try await req(
                "/configs",
                method: .PATCH,
                parameters: ["tun": ["enable": enable]],
                encoding: .json
            )
            .validate()
            .responseData
        } catch {
            Logger.log("update tun failed: \(error.localizedDescription)", level: .error)
        }
    }

    static func updateSniffing(enable: Bool) async {
        Logger.log("update sniffing:\(enable)", level: .debug)
        do {
            _ = try await req(
                "/configs",
                method: .PATCH,
                parameters: ["sniffing": enable],
                encoding: .json
            )
            .validate()
            .responseData
        } catch {
            Logger.log("update sniffing failed: \(error.localizedDescription)", level: .error)
        }
    }
    
    // MARK: - Providers

    struct AllProviders {
        var proxies = [String]()
        var rules = [String]()
    }

    static func requestExternalProviderNames() async -> AllProviders {
        async let proxyNamesTask: [String] = {
            do {
                let data = try await req("/providers/proxies")
                    .validate()
                    .responseData
                let json = JSON(data)
                return json["providers"].dictionaryValue
                    .filter { $0.value["vehicleType"] == "HTTP" }
                    .map(\.key)
            } catch {
                Logger.log(error.localizedDescription, level: .warning)
                return []
            }
        }()


        return AllProviders(proxies: await proxyNamesTask, rules: [])
    }

	/*
    enum ProviderType {
        case proxy
        case rule
    }
	 */

    static func resetFakeIpCache() async {
        let response = await req("/cache/fakeip/flush", method: .POST)
            .response
        Logger.log("flush fake ip: \(response.httpResponse?.statusCode ?? -1)")
    }
}

// MARK: - Stream Apis

extension ApiRequest {
	@MainActor
	func resetStreamApis() {
		didTrafficStreamEverConnect = false
		isCoreProcessAlive = true
		StreamType.allCases.forEach { resetStreamApi(for: $0) }
	}

	@MainActor
	func resetStreamApi(for type: StreamType) {
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

		streamTasks[type] = Task { @MainActor [weak self] in
			do {
                let requiresCoreRunning = type != .traffic
                
				let stream = await ApiRequest.req(uri, requiresCoreRunning: requiresCoreRunning).stream
				var didConnect = false
				for try await line in stream {
					if !didConnect {
						didConnect = true
						await self?.streamDidConnect(type)
					}
					await self?.streamDidReceiveMessage(type, text: line)
				}
				await self?.streamDidDisconnect(type, error: nil)
			} catch {
				await self?.streamDidDisconnect(type, error: error)
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

	// MARK: Notify Delegates

	private func notifyStreamStatusChanged() async {
		await delegate?.streamStatusChanged()
		await dashboardDelegate?.streamStatusChanged()
	}

	private func notifyTrafficUpdate(up: Int, down: Int) async {
		await delegate?.didUpdateTraffic(up: up, down: down)
		await dashboardDelegate?.didUpdateTraffic(up: up, down: down)
	}

	private func notifyLog(log: String, level: String) async {
		await delegate?.didGetLog(log: log, level: level)
		await dashboardDelegate?.didGetLog(log: log, level: level)
	}

	private func notifyMemoryUpdate(memory: Int64) async {
		await delegate?.didUpdateMemory(memory: memory)
		await dashboardDelegate?.didUpdateMemory(memory: memory)
	}

	// MARK: Stream Event Handlers

    @MainActor
    private func streamDidConnect(_ type: StreamType) async {
        streamRetryDelays[type] = 1

        if type == .traffic {
            didTrafficStreamEverConnect = true
            ConfigManager.shared.kernelState = .running
            await notifyStreamStatusChanged()
        }
    }

	@MainActor
	private func streamDidDisconnect(_ type: StreamType, error: Error?) async {
        streamTasks[type]?.cancel()
        if type == .traffic {
            let kernelState = ConfigManager.shared.kernelState
            let shouldTreatAsStartupFailure: Bool
            switch kernelState {
            case .stopped, .checkingLaunchPath, .checkingHelper, .preparingConfig, .starting:
                shouldTreatAsStartupFailure = true
            case .reloadingConfig, .running, .disconnected, .failedToStart:
                shouldTreatAsStartupFailure = false
            }

            if error == nil || (error as? HTTPParserError) == .invalidEOFState || !shouldTreatAsStartupFailure {
                ConfigManager.shared.kernelState = .disconnected
            } else {
                ConfigManager.shared.kernelState = .failedToStart
            }
            await notifyStreamStatusChanged()

            if didTrafficStreamEverConnect, !isTerminating,
               (error as? CancellationError) == nil {
                if isCoreProcessAlive {
                    let alive = await ClashProcess.isMetaProcessRunning()
                    if alive {
                        UserNotificationCenter.shared.postCoreDisconnectedNotice()
                        scheduleRetry(for: type)
                        return
                    }
                    isCoreProcessAlive = false
                }
                await UserNotificationCenter.shared.postCoreCrashNotice()
                return
            }
        }
        
        if let err = error,
           (err as? HTTPParserError) != .invalidEOFState,
           !(err is CancellationError) {
            Logger.log("stream error type=\(type) \(Self.describeStreamError(err))", level: .error)
        }

		scheduleRetry(for: type)
	}

	private static func describeStreamError(_ error: Error) -> String {
		var parts: [String] = ["desc=\(error)"]
		let ns = error as NSError
		parts.append("domain=\(ns.domain)")
		parts.append("code=\(ns.code)")
		if let http = error as? HTTPClientError {
			parts.append("httpClientError=\(http)")
		}
		return parts.joined(separator: " | ")
	}

	private func streamDidReceiveMessage(_ type: StreamType, text: String) async {
		let json = JSON(parseJSON: text)

		switch type {
		case .traffic:
			await notifyTrafficUpdate(up: json["up"].intValue, down: json["down"].intValue)
		case .logging:
			guard await logRateLimiter.processLog() else { return }
			await notifyLog(log: json["payload"].stringValue, level: json["type"].string ?? "info")
		case .memory:
			await notifyMemoryUpdate(memory: json["inuse"].int64Value)
		}
	}
}
