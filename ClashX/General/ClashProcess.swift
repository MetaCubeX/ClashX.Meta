//
//  ClashProcess.swift
//  ClashX
//
//  Copyright © 2024 west2online. All rights reserved.
//

import Cocoa
import CryptoKit
import Subprocess

@MainActor
protocol ClashProcessDelegate: AnyObject {
	func clashProcess(_ process: ClashProcess, didFailToResolveLaunchPath message: String) async
	func clashProcess(_ process: ClashProcess, didStartWith server: MetaServer) async
	func clashProcessDidUpdateConfig(_ process: ClashProcess) async
	func clashProcess(_ process: ClashProcess, didFailToStartWith error: Error) async
}

enum StartMetaError: Error {
	case configMissing
	case remoteConfigMissing
	case startMetaFailed(String)
	case helperNotFound
	case pushConfigFailed(String)
	case launchPathMissing
}


actor ClashProcess {
	
	enum CoreState {
		case stopped, checkingLaunchPath, checkingHelper, preparingConfig, starting, running
	}

	static let metaCoreSHA256 = BundledCoreTrust.sha256
	private static let metaProcessLabel = "com.metacubex.ClashX.ProxyConfigHelper.meta"

	struct MetaLaunchdStatus {
		var pid: Int?
		var lastExitCode: String?
		var lastTerminatingSignal: String?

		var isRunning: Bool {
			(pid ?? 0) > 0
		}
	}

	static func metaLaunchdStatus() async -> MetaLaunchdStatus? {
		for attempt in 1...2 {
			let result = try? await run(
				.name("launchctl"),
				arguments: ["print", "system/\(metaProcessLabel)"],
				output: .string(limit: 65536),
				error: .string(limit: 65536)
			)

			guard let result else {
				Logger.log("metaLaunchdStatus: launchctl print attempt \(attempt) failed", level: .info)
				if attempt == 1 {
					try? await Task.sleep(seconds: 0.3)
				}
				continue
			}

			if let output = result.standardOutput, !output.isEmpty {
				return Self.parseMetaLaunchdStatus(from: output)
			}

			let errorOutput = result.standardError ?? ""
			let stderr = errorOutput.isEmpty ? "(empty)" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
			Logger.log("metaLaunchdStatus: launchctl print attempt \(attempt) returned empty output, stderr: \(stderr)", level: .info)

			if attempt == 1 {
				try? await Task.sleep(seconds: 0.3)
			}
		}
		return nil
	}

	private static func parseMetaLaunchdStatus(from output: String) -> MetaLaunchdStatus {
		func value(for key: String) -> String? {
			output.split(separator: "\n")
				.first { $0.contains(key) }
				.flatMap { $0.split(separator: "=").last }
				.map { $0.trimmingCharacters(in: .whitespaces) }
		}

		return MetaLaunchdStatus(
			pid: value(for: "pid =").flatMap(Int.init),
			lastExitCode: value(for: "last exit code ="),
			lastTerminatingSignal: value(for: "last terminating signal =")
		)
	}
	
	
	private var coreState: CoreState = .stopped
	private weak var delegate: (any ClashProcessDelegate)?
	private var cachedLaunchPath: (path: String?, err: String?)?
	private var startTask: Task<Void, Never>?

	private func loadLaunchPath() -> (path: String?, err: String?) {
		if let cachedLaunchPath {
			return cachedLaunchPath
		}

		let launchPath = Self.resolveLaunchPath(sha256: Self.metaCoreSHA256)
		cachedLaunchPath = launchPath
		return launchPath
	}

	private static func resolveLaunchPath(sha256: String) -> (path: String?, err: String?) {
		Logger.log("Get launchPath")
		
		guard let alphaCorePath = Paths.alphaCorePath(),
			  let corePath = Paths.defaultCorePath() else {
			return (nil, "Paths error")
		}
		
		if ConfigManager.useAlphaCore {
			if (try? TrustedCoreStore.alpha()) != nil {
				return (alphaCorePath.path, nil)
			}
            Logger.log("No verified Alpha core is installed. Using the bundled core; download Alpha again in Settings to migrate the previous installation.", level: .warning)
		}
		
		let fm = FileManager.default
		
		// unzip internal core
		if !fm.fileExists(atPath: corePath.path) {
			if let msg = unzipMetaCore() {
				return (nil, msg)
			}
		} else if !validateDefaultCore(sha256) {
			try? fm.removeItem(at: corePath)
			if let msg = unzipMetaCore() {
				return (nil, msg)
			}
		}
		
		// Validate the bundled executable against the digest compiled at build time.
		if validateDefaultCore(sha256) {
			return (corePath.path, nil)
		} else {
			Logger.log("Failure to verify the internal Meta Core.")
			Logger.log(corePath.path)
			return (nil, "Failure to verify the internal Meta Core.\nDo NOT replace core file in the resources folder.")
		}
	}
	
	
// MARK: start core
	
	func startIfNeeded(delegate: any ClashProcessDelegate) async {
		self.delegate = delegate
		guard coreState != .running else { return }

		if let startTask {
			await startTask.value
			return
		}

		let task = Task {
			await MainActor.run {
				ConfigManager.shared.kernelState = .starting
			}
			await self.runStartSequence()
		}
		startTask = task
		await task.value
	}

	private func runStartSequence() async {
		defer {
			startTask = nil
		}

		coreState = .checkingLaunchPath
		await MainActor.run {
			ConfigManager.shared.kernelState = .checkingLaunchPath
		}
		let paths = loadLaunchPath()
		guard let launchPath = paths.path else {
			coreState = .stopped
			await MainActor.run {
				ConfigManager.shared.kernelState = .failedToStart
			}
			let msg = paths.err ?? "Load internal Meta Core failed."
			await delegate?.clashProcess(self, didFailToResolveLaunchPath: msg)
			return
		}

		var didStartCore = false

		do {
			try await checkHelperVersion()
			coreState = .preparingConfig
            if try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.TerminateExistingMeta()) {
                try? await Task.sleep(seconds: 1)
            }
            
			await MainActor.run {
				ConfigManager.shared.kernelState = .preparingConfig
			}
			try await prepareConfigFile()
			let config = try await generateInitConfig()
			coreState = .starting
			await MainActor.run {
				ConfigManager.shared.kernelState = .starting
			}
			let res = try await startMeta(config, launchPath: launchPath)
			didStartCore = true
			coreState = .running
			await MainActor.run {
				ConfigManager.shared.kernelState = .running
			}

			if res.log != "" {
				Logger.log("""
\n########  Clash Meta Start Log  #########
\(res.log)
########  END  #########
""", level: .info)
			}

			await delegate?.clashProcess(self, didStartWith: res)
			try await pushInitConfig()
			Logger.log("Init config file success.")
		} catch {
			await handleStartError(error, didStartCore: didStartCore)
		}
	}

	private func handleStartError(_ error: Error, didStartCore: Bool) async {
		Logger.log("\(error)", level: .error)
		coreState = didStartCore ? .running : .stopped
		await MainActor.run {
			ConfigManager.shared.kernelState = didStartCore ? .running : .failedToStart
		}
		await delegate?.clashProcess(self, didFailToStartWith: error)
	}

	private func checkHelperVersion() async throws {
		coreState = .checkingHelper
		await MainActor.run {
			ConfigManager.shared.kernelState = .checkingHelper
		}

		let version: String
		do {
			version = try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.GetVersion())
		} catch {
			Logger.log("Helper, check status failed, will try again")
			throw StartMetaError.helperNotFound
		}

		Logger.log("Helper, check status success \(version)")
	}
	
	private func prepareConfigFile() async throws {
		let configName = ConfigManager.selectConfigName
		guard let path = await ApiRequest.findConfigPath(configName: configName) else {
			throw StartMetaError.configMissing
		}

		if FileManager.default.fileExists(atPath: path) {
			return
		}

		Logger.log("\(configName) not exists")
		if let config = RemoteConfigManager.shared.configs.first(where: { $0.name == configName }) {
			Logger.log("Try to download remote config \(configName)")
			if let error = await RemoteConfigManager.updateConfig(config: config) {
				Logger.log("Download remote config failed, \(error)")
				throw StartMetaError.remoteConfigMissing
			}

			Logger.log("Download remote config success")
			return
		}

		if configName != "config" {
			ConfigManager.selectConfigName = "config"
		}

		Logger.log("Try to copy default config")
		ICloudManager.shared.setup()
		await ConfigFileManager.copySampleConfigIfNeed()
	}

	private func generateInitConfig() async throws -> ClashMetaConfig.Config {
		let paths = try await safePaths()
		var config = await ClashMetaConfig.generateInitConfig()
		config.safePaths = paths.joined(separator: ":")
		config.updatePorts(await usedPorts() ?? "")
		return config
	}
    
	private func safePaths() async throws -> [String] {
		guard let resourcePath = Bundle.main.resourcePath else {
			throw StartMetaError.startMetaFailed("resourcePath")
		}

		var paths = [resourcePath + "/dashboard", Paths.cacheConfigs()]
		guard ICloudManager.shared.useICloudRelay.value else {
			return paths
		}

		if let path = await iCloudURL()?.path {
			paths.append(path)
		}

		return paths
    }

	private func startMeta(_ config: ClashMetaConfig.Config, launchPath: String) async throws -> MetaServer {
		Logger.log("Trying start meta core")

		let confJSON = MetaServer(
			externalController: config.externalController,
			secret: config.secret ?? "",
			safePaths: config.safePaths ?? "",
			sessionId: Logger.shared.sessionId
		).jsonString()

		guard let configData = config.encodedData else {
            throw StartMetaError.startMetaFailed("Unable to encode the initial configuration.")
        }
        let core: ProxyConfigHelperCore = launchPath.hasPrefix(TrustedCoreStore.alphaDirectory + "/") ? .alpha : .bundled

		let response: String?
		do {
			response = try await PrivilegedHelperManager.shared.request(
				ProxyConfigHelperMessages.StartMeta(path: launchPath,
                                                   core: core,
				                                   confPath: kConfigFolderPath,
				                                   configData: configData,
				                                   confJSON: confJSON)
			)
		} catch {
			Logger.log("helperNotFound, startMeta failed", level: .error)
			throw StartMetaError.helperNotFound
		}

		guard let response else {
			throw StartMetaError.startMetaFailed("unknown error")
		}

		guard let jsonData = response.data(using: .utf8),
			  let res = try? JSONDecoder().decode(MetaServer.self, from: jsonData) else {
			throw StartMetaError.startMetaFailed(response)
		}

		return res
	}

	private func pushInitConfig() async throws {
		ClashProxy.cleanCache()
		let configName = ConfigManager.selectConfigName
		Logger.log("Push init config file: \(configName)")

		guard let composedPath = await ConfigOverride.shared.composeConfig(configName: configName) else {
			throw StartMetaError.pushConfigFailed("compose config failed")
		}

		if let error = await ApiRequest.requestConfigUpdate(configPath: composedPath) {
			throw StartMetaError.pushConfigFailed(error)
		}

		await delegate?.clashProcessDidUpdateConfig(self)
	}

	private func usedPorts() async -> String? {
		do {
			return try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.GetUsedPorts())
		} catch {
			Logger.log("helperNotFound, getUsedPorts failed", level: .error)
			return nil
		}
	}

	private func iCloudURL() async -> URL? {
		await ICloudManager.shared.getUrl()
	}
	
// MARK: launch path
	
	private static func unzipMetaCore() -> String? {
		guard let corePath = Paths.defaultCorePath(),
			  let gzPath = Paths.defaultCoreGzPath() else { return "Paths error" }
		let fm = FileManager.default
		do {
			let data = try Data(contentsOf: .init(fileURLWithPath: gzPath)).gunzipped()

			if !fm.fileExists(atPath: corePath.deletingLastPathComponent().path) {
				try fm.createDirectory(at: corePath.deletingLastPathComponent(), withIntermediateDirectories: true)
			}

			try data.write(to: corePath)
			return nil
		} catch let error {
			let msg = "Unzip Meta failed: \(error)"
			Logger.log(msg, level: .error)
			return msg
		}
	}

    private static func validateDefaultCore(_ expectedSHA256: String) -> Bool {
        guard PrivilegedDirectory.isSHA256(expectedSHA256),
              let path = Paths.defaultCorePath()?.path,
              let data = try? PrivilegedDirectory.readSource(path, limit: TrustedCoreStore.maximumCoreSize),
              PrivilegedDirectory.sha256(data) == expectedSHA256 else { return false }
        return chmodX(path)
    }

	private static func chmodX(_ path: String) -> Bool {
		let proc = Process()
		proc.executableURL = .init(fileURLWithPath: "/bin/chmod")
		proc.arguments = ["+x", path]
		do {
			try proc.run()
		} catch let error {
			Logger.log("chmod +x failed. \(error.localizedDescription)")
			return false
		}
		proc.waitUntilExit()
		return proc.terminationStatus == 0
	}
	
// MARK: verify config file
	
	static func verify(_ confPath: String, confFilePath: String, sha256: String = ClashProcess.metaCoreSHA256) -> String? {
		do {
			guard let path = resolveLaunchPath(sha256: sha256).path else { return nil }
			
			let proc = Process()
			proc.executableURL = .init(fileURLWithPath: path)
			var args = [
				"-t",
				"-d",
				confPath
			]
			if confFilePath != "" {
				args.append(contentsOf: [
					"-f",
					confFilePath
				])
			}
			let pipe = Pipe()
			proc.standardOutput = pipe
			
			proc.arguments = args
			try proc.run()
			proc.waitUntilExit()
			
			guard proc.terminationStatus == 0 else {
				return "Test failed, status \(proc.terminationStatus)"
			}
			
			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			guard let string = String(data: data, encoding: String.Encoding.utf8) else {
				return "Test failed, no found output."
			}
			
			let task = MetaTask()
			
			let results = string.split(separator: "\n").map(String.init).map(task.formatMsg(_:))
			
			guard let re = results.last else {
				return "Test failed, no found output."
			}
			
			if re.hasPrefix("configuration file"),
			   re.hasSuffix("test is successful") {
				return nil
			} else if re.hasPrefix("configuration file"),
					  re.hasSuffix("test failed") {
				return results.count > 1
				? results[results.count - 2]
				: "Test failed, unknown result."
			} else {
				return re
			}
		} catch let error {
			return "\(error)"
		}
	}

// MARK: age decrypt

	static func ageDecrypt(key: String, inputPath: String, outputPath: String) -> String? {
		do {
			let proc = Process()
			proc.executableURL = Paths.defaultCorePath()
			proc.arguments = [
				"age",
                "decrypt",
				key,
				inputPath,
				outputPath
			]

			let pipe = Pipe()
			proc.standardOutput = pipe
			proc.standardError = pipe

			try proc.run()
			proc.waitUntilExit()

			guard proc.terminationStatus == 0 else {
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				let output = String(data: data, encoding: .utf8) ?? ""
				return "Decrypt failed, status \(proc.terminationStatus): \(output)"
			}

			return nil
		} catch {
			return "\(error)"
		}
	}
}
