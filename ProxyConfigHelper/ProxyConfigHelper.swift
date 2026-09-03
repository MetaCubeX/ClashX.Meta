//
//  ProxyConfigHelper.swift
//  com.metacubex.ClashX.ProxyConfigHelper
//
//  Copyright © 2024 west2online. All rights reserved.
//

import Cocoa
import os.log
import Security

class ProxyConfigHelper: NSObject, NSXPCListenerDelegate {
	private typealias RequestHandler = @Sendable (ProxyConfigHelperRequestEnvelope) async throws -> Data

	private struct MessageHandlerStore {
		var handlers: [String: RequestHandler] = [:]

		mutating func register<Message: ProxyConfigHelperXPCMessage>(
			_: Message.Type,
			handler: @Sendable @escaping (Message) async throws -> Message.Response
		) {
			handlers[Message.kind] = { envelope in
				let message = try ProxyConfigHelperXPCCodec.decodeMessage(Message.self, from: envelope)
				let response = try await handler(message)
				return try ProxyConfigHelperXPCCodec.encodeResponse(response, for: Message.self)
			}
		}
	}
	
	private var listener: NSXPCListener
	private var connections = [NSXPCConnection]()
	private var shouldQuitCheckInterval = 2.0
	private var shouldQuit = false
	private lazy var requestHandlers = makeRequestHandlers()
	
	private let metaTask = MetaTask()
	private let metaDNS = MetaDNS()
	
	override init() {
		shouldQuit = false
		listener = NSXPCListener(machServiceName: "com.metacubex.ClashX.ProxyConfigHelper")
		super.init()
		listener.delegate = self
	}
	
	func run() {
		listener.resume()
		os_log("ProxyConfigHelper running")
		while !shouldQuit {
			RunLoop.current.run(until: Date(timeIntervalSinceNow: shouldQuitCheckInterval))
		 }
	}
	
	
	// MARK: - NSXPCListenerDelegate
	
	func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		
		guard Self.authorize(connection: newConnection) else {
			os_log("ProxyConfigHelper rejected an unauthorized XPC connection", type: .error)
			return false
		}
		
		newConnection.exportedInterface = NSXPCInterface(with: ProxyConfigRemoteProcessProtocol.self)
		newConnection.exportedObject = self
		newConnection.invalidationHandler = {
			guard let index = self.connections.firstIndex(of: newConnection) else { return }
			self.connections.remove(at: index)
			
			if self.connections.isEmpty {
				self.shouldQuit = true
				os_log("ProxyConfigHelper shouldQuit")
			}
		}
		
		connections.append(newConnection)
		newConnection.resume()
		
		return true
	}
	
	private static let clientBundleIdentifier = "com.metacubex.ClashX.meta"

	private static func authorize(connection: NSXPCConnection) -> Bool {
		let requirement = clientCodeSigningRequirement()

		if #available(macOS 13.0, *) {
			connection.setCodeSigningRequirement(requirement)
			return true
		}

		return validateByAuditToken(connection, requirement: requirement)
	}

	private static func clientCodeSigningRequirement() -> String {
		if let team = ownTeamIdentifier(), !team.isEmpty {
			return "anchor apple generic and identifier \"\(clientBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(team)\""
		}
		os_log("ProxyConfigHelper is not Team-ID signed; using a best-effort client requirement. Sign the app for full protection.", type: .error)
		return "identifier \"\(clientBundleIdentifier)\""
	}

	private static func ownTeamIdentifier() -> String? {
		var codeRef: SecCode?
		guard SecCodeCopySelf([], &codeRef) == errSecSuccess, let codeRef else { return nil }

		var staticRef: SecStaticCode?
		guard SecCodeCopyStaticCode(codeRef, [], &staticRef) == errSecSuccess, let staticRef else { return nil }

		var infoRef: CFDictionary?
		let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
		guard SecCodeCopySigningInformation(staticRef, flags, &infoRef) == errSecSuccess,
			  let info = infoRef as? [String: Any] else { return nil }

		return info[kSecCodeInfoTeamIdentifier as String] as? String
	}

	private static func validateByAuditToken(_ connection: NSXPCConnection, requirement: String) -> Bool {
		guard var token = auditToken(of: connection) else { return false }

		let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
		var codeRef: SecCode?
		let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
		guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &codeRef) == errSecSuccess,
			  let codeRef else { return false }

		var requirementRef: SecRequirement?
		guard SecRequirementCreateWithString(requirement as CFString, [], &requirementRef) == errSecSuccess,
			  let requirementRef else { return false }

		return SecCodeCheckValidity(codeRef, [], requirementRef) == errSecSuccess
	}

	private static func auditToken(of connection: NSXPCConnection) -> audit_token_t? {
		let selector = NSSelectorFromString("auditToken")
		guard connection.responds(to: selector),
			  let value = connection.value(forKey: "auditToken") as? NSValue else { return nil }

		var token = audit_token_t()
		withUnsafeMutableBytes(of: &token) { buffer in
			guard let base = buffer.baseAddress else { return }
			value.getValue(base, size: buffer.count)
		}
		return token
	}
	
}

extension ProxyConfigHelper: ProxyConfigRemoteProcessProtocol {
	func sendRequest(_ request: Data, reply: @escaping (Data?, NSString?) -> Void) {
		Task {
			do {
				let response = try await handleRequest(request)
				reply(response, nil)
			} catch {
				let message = error.localizedDescription
				os_log("ProxyConfigHelper request failed: %{public}@", type: .error, message)
				reply(nil, message as NSString)
			}
		}
	}
}

private extension ProxyConfigHelper {
	private func makeRequestHandlers() -> [String: RequestHandler] {
		var store = MessageHandlerStore()

		store.register(ProxyConfigHelperMessages.GetVersion.self) { [unowned self] _ in
            await helperVersion()
		}

		store.register(ProxyConfigHelperMessages.GetUsedPorts.self) { [unowned self] _ in
			await getUsedPorts()
		}

		store.register(ProxyConfigHelperMessages.StartMeta.self) { [unowned self] message in
			await startMeta(message)
		}

		store.register(ProxyConfigHelperMessages.StopMeta.self) { [unowned self] _ in
			await stopMeta()
			return ProxyConfigHelperExplicitSuccess()
		}

		store.register(ProxyConfigHelperMessages.TerminateExistingMeta.self) { [unowned self] _ in
			return await terminateExistingMeta()
		}

		store.register(ProxyConfigHelperMessages.UpdateTun.self) { [unowned self] message in
			await updateTun(message)
			return ProxyConfigHelperExplicitSuccess()
		}

		store.register(ProxyConfigHelperMessages.FlushDnsCache.self) { [unowned self] _ in
			await flushDnsCache()
			return ProxyConfigHelperExplicitSuccess()
		}

		store.register(ProxyConfigHelperMessages.EnableProxy.self) { [unowned self] message in
			await enableProxy(message)
		}

		store.register(ProxyConfigHelperMessages.DisableProxy.self) { [unowned self] message in
			await disableProxy(message)
		}

		store.register(ProxyConfigHelperMessages.RestoreProxy.self) { [unowned self] message in
			try await restoreProxy(message)
		}

		store.register(ProxyConfigHelperMessages.GetCurrentProxySetting.self) { [unowned self] _ in
			try await currentProxySetting()
		}

		return store.handlers
	}

	func handleRequest(_ data: Data) async throws -> Data {
		let envelope = try ProxyConfigHelperXPCCodec.decodeRequestEnvelope(from: data)
		guard let handler = requestHandlers[envelope.kind] else {
			throw ProxyConfigHelperXPCError.unexpectedMessage(envelope.kind)
		}
		return try await handler(envelope)
	}

    @MainActor
	func helperVersion() -> String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
	}

	@MainActor
	func enableProxy(_ message: ProxyConfigHelperMessages.EnableProxy) -> String? {
		let tool = ProxySettingTool()
		tool.enableProxyWithport(Int32(message.port),
		                         socksPort: Int32(message.socksPort),
		                         pacUrl: message.pac ?? "",
		                         filterInterface: message.filterInterface,
		                         ignoreList: message.ignoreList)
		return nil
	}

	@MainActor
	func disableProxy(_ message: ProxyConfigHelperMessages.DisableProxy) -> String? {
		let tool = ProxySettingTool()
		tool.disableProxyWithfilterInterface(message.filterInterface)
		return nil
	}

	@MainActor
	func restoreProxy(_ message: ProxyConfigHelperMessages.RestoreProxy) throws -> String? {
		let info = try message.info.dictionary()
		let tool = ProxySettingTool()
		tool.restoreProxySetting(info,
		                        currentPort: Int32(message.currentPort),
		                        currentSocksPort: Int32(message.socksPort),
		                        filterInterface: message.filterInterface)
		return nil
	}

	@MainActor
	func currentProxySetting() throws -> ProxyConfigHelperPropertyList {
		let info = ProxySettingTool.currentProxySettings() as? [String: Any] ?? [:]
		return try ProxyConfigHelperPropertyList(info)
	}

	@MainActor
    func startMeta(_ message: ProxyConfigHelperMessages.StartMeta) async -> String? {
        if await terminateExistingMeta() {
            try? await Task.sleep(seconds: 1)
        }
        var result: String?
        for await value in metaTask.start(message.path,
                                          confPath: message.confPath,
                                          confFilePath: message.confFilePath,
                                          confJSON: message.confJSON,
                                          coreMD5: message.coreMD5) {
            result = value
        }
        return result
	}

	@MainActor
	func stopMeta() async {
		await metaTask.stop()
	}

	@MainActor
	func terminateExistingMeta() async -> Bool {
		return await metaTask.terminateExistingMeta()
	}

	@MainActor
	func getUsedPorts() async -> String? {
		await metaTask.getUsedPorts()
	}

	@MainActor
	func updateTun(_ message: ProxyConfigHelperMessages.UpdateTun) async {
		metaDNS.setCustomDNS(message.dns)
		if message.state {
			metaDNS.hijackDNS()
		} else {
			metaDNS.revertDNS()
		}
		await metaDNS.flushDnsCache()
	}

	@MainActor
	func flushDnsCache() async {
		await metaDNS.flushDnsCache()
	}
}
