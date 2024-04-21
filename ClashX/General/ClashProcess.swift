//
//  ClashProcess.swift
//  ClashX
//
//  Copyright © 2024 west2online. All rights reserved.
//

import Cocoa
import PromiseKit

protocol ClashProcessDelegate {
	func clashLaunchPathNotFound(_ msg: String)
	func clashApiUpdated(_ server: MetaServer)
	func clashConfigUpdated()
	func clashStartError(_ error: Error)
}

enum StartMetaError: Error {
	case configMissing
	case remoteConfigMissing
	case startMetaFailed(String)
	case helperNotFound
	case pushConfigFailed(String)
	case launchPathMissing
}

class ClashProcess: NSObject {
	
	enum CoreState: Int {
		case stopped, startFailed, checkingHelper, helperReady, starting, running
	}
	
	
	private let md5: String
	private var retryTimes = 0
	
	private var _coreState: CoreState = .stopped
	
	var coreState: CoreState {
		return _coreState
	}
	
	var delegate: ClashProcessDelegate?
	
	init(_ md5: String) {
		self.md5 = md5
	}
	
	lazy var launchPath: (path: String?, err: String?) = {
		Logger.log("Get launchPath")
		
		guard let alphaCorePath = Paths.alphaCorePath(),
			  let corePath = Paths.defaultCorePath() else {
			return (nil, "Paths error")
		}
		
		// alpha core
		if let _ = verifyCoreFile(alphaCorePath.path) {
			if ConfigManager.useAlphaCore {
				return (alphaCorePath.path, nil)
			}
		}
		
		let fm = FileManager.default
		
		// unzip internal core
		if !fm.fileExists(atPath: corePath.path) {
			if let msg = unzipMetaCore() {
				return (nil, msg)
			}
		} else if !validateDefaultCore(md5) {
			try? fm.removeItem(at: corePath)
			if let msg = unzipMetaCore() {
				return (nil, msg)
			}
		}
		
		if let msg = verifyCoreFile(corePath.path) {
			Logger.log("version: \(msg.version)")
		}
		
		// validate md5
		if validateDefaultCore(md5) {
			return (corePath.path, nil)
		} else {
			Logger.log("Failure to verify the internal Meta Core.")
			Logger.log(corePath.path)
			return (nil, "Failure to verify the internal Meta Core.\nDo NOT replace core file in the resources folder.")
		}
	}()
	
	
// MARK: start core
	
	func start() {
		let paths = launchPath
		
		guard let _ = paths.path else {
			let msg = paths.err ?? "Load internal Meta Core failed."
			delegate?.clashLaunchPathNotFound(msg)
			return
		}
		
		checkHelperVersion().then { _ in
			self.startProxy()
		}.done {
			self.retryTimes = 0
			Logger.log("Init config file success.")
			
			self.showUpdateNotification("ClashX_Meta_1.3.0_UpdateTips", info: "Config Floder migrated from\n~/.config/clash to\n~/.config/clash.meta")
		}.catch { error in
			Logger.log("\(error)", level: .error)

			switch error {
			case StartMetaError.helperNotFound:
				self._coreState = .checkingHelper
				let delay: DispatchTimeInterval = {
					switch self.retryTimes {
					case 0..<10:
						return .milliseconds(500)
					case 10..<20:
						return .seconds(2)
					case 20..<30:
						return .seconds(8)
					case 30..<40:
						return .seconds(15)
					default:
						return .seconds(60)
					}
				}()
				self.retryTimes += 1
				after(delay).done {
					self.start()
				}
			default:
				self._coreState = .startFailed
				self.delegate?.clashStartError(error)
			}
		}
	}
	
	func checkHelperVersion() -> Promise<String?> {
		guard coreState.rawValue < CoreState.helperReady.rawValue else {
			return .value(nil)
		}
		_coreState = .checkingHelper
		return Promise { resolver in
			PrivilegedHelperManager.shared.helper {
				Logger.log("Helper, check status failed, will try again")
				resolver.reject(StartMetaError.helperNotFound)
			}?.getVersion {
				Logger.log("Helper, check status success \($0)")
				self._coreState = .helperReady
				resolver.fulfill($0)
			}
		}
	}
	
	private func startProxy() -> Promise<()> {
		guard coreState.rawValue < CoreState.starting.rawValue else {
			return .value(())
		}
		_coreState = .starting
		
		Logger.log("Trying start meta core")
		
		return prepareConfigFile().then {
			self.generateInitConfig()
		}.then {
			self.startMeta($0)
		}.get { res in
			if res.log != "" {
				Logger.log("""
\n########  Clash Meta Start Log  #########
\(res.log)
########  END  #########
""", level: .info)
			}
			self._coreState = .running
			self.delegate?.clashApiUpdated(res)
		}.then { _ in
			self.pushInitConfig()
		}
	}
	

	func prepareConfigFile() -> Promise<()> {
		.init { resolver in
			let configName = ConfigManager.selectConfigName
			ApiRequest.findConfigPath(configName: configName) { path in
				guard let path = path else {
					resolver.reject(StartMetaError.configMissing)
					return
				}
				if FileManager.default.fileExists(atPath: path) {
					resolver.fulfill_()
					return
				}
				
				Logger.log("\(configName) not exists")
				if let config = RemoteConfigManager.shared.configs.first(where: { $0.name == configName }) {
					Logger.log("Try to download remote config \(configName)")
					RemoteConfigManager.updateConfig(config: config) {
						if let error = $0 {
							Logger.log("Download remote config failed, \(error)")
							resolver.reject(StartMetaError.remoteConfigMissing)
						} else {
							Logger.log("Download remote config success")
							resolver.fulfill_()
						}
					}
				} else {
					if configName != "config" {
						ConfigManager.selectConfigName = "config"
					}

					Logger.log("Try to copy default config")
					ICloudManager.shared.setup()
					ConfigFileManager.copySampleConfigIfNeed()
					resolver.fulfill_()
				}
			}
		}
	}

	func generateInitConfig() -> Promise<ClashMetaConfig.Config> {
		Promise { resolver in
			ClashMetaConfig.generateInitConfig {
                var config = $0
                PrivilegedHelperManager.shared.helper {
//                    resolver.reject(StartMetaError.helperNotFound)
					Logger.log("helperNotFound, getUsedPorts failed", level: .error)
					resolver.fulfill(config)
                }?.getUsedPorts {
                    config.updatePorts($0 ?? "")
                    resolver.fulfill(config)
                }
			}
		}
	}

	func startMeta(_ config: ClashMetaConfig.Config) -> Promise<MetaServer> {
		.init { resolver in
			let confJSON = MetaServer(externalController: config.externalController, secret: config.secret ?? "").jsonString()
			
			guard let path = launchPath.path else {
				resolver.reject(StartMetaError.launchPathMissing)
				return
			}
			
			PrivilegedHelperManager.shared.helper {
				Logger.log("helperNotFound, startMeta failed", level: .error)
				resolver.reject(StartMetaError.helperNotFound)
			}?.startMeta(path: path,
						 confPath: kConfigFolderPath,
						 confFilePath: config.path,
						 confJSON: confJSON) {
				if let string = $0 {
					guard let jsonData = string.data(using: .utf8),
						  let res = try? JSONDecoder().decode(MetaServer.self, from: jsonData) else {
						resolver.reject(StartMetaError.startMetaFailed(string))
						return
					}

					resolver.fulfill(res)
				} else {
					resolver.reject(StartMetaError.startMetaFailed($0 ?? "unknown error"))
				}
			}
		}
	}

	func pushInitConfig() -> Promise<()> {
		.init { resolver in
			ClashProxy.cleanCache()
			let configName = ConfigManager.selectConfigName
			Logger.log("Push init config file: \(configName)")
			ApiRequest.requestConfigUpdate(configName: configName) { err in
				if let error = err {
					resolver.reject(StartMetaError.pushConfigFailed(error))
				} else {
					self.delegate?.clashConfigUpdated()
					resolver.fulfill_()
				}
			}
		}
	}
	
	func showUpdateNotification(_ udString: String, info: String) {
		guard !UserDefaults.standard.bool(forKey: udString) else { return }
		
		UserDefaults.standard.set(true, forKey: udString)
		
		NSUserNotificationCenter.default
			.postNotificationAlert(title: "Update Tips", info: info)
	}
	
// MARK: launch path
	
	private func unzipMetaCore() -> String? {
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

	func verifyCoreFile(_ path: String) -> (version: String, date: Date?)? {
		guard chmodX(path) else { return nil }

		let proc = Process()
		proc.executableURL = .init(fileURLWithPath: path)
		proc.arguments = ["-v"]
		let pipe = Pipe()
		proc.standardOutput = pipe
		do {
			try proc.run()
		} catch let error {
			Logger.log(error.localizedDescription)
			return nil
		}
		proc.waitUntilExit()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()

		guard proc.terminationStatus == 0,
			  let out = String(data: data, encoding: .utf8) else {
			return nil
		}

		Logger.log("verify core path: \(path)")
		Logger.log("-v out: \(out)")
		
		let outs = out
			.split(separator: "\n")
			.first {
				$0.starts(with: "Clash Meta") || $0.starts(with: "Mihomo Meta")
			}?.split(separator: " ")
			.map(String.init)

		guard let outs,
			  outs.count == 13,
			  (outs[0] == "Clash" || outs[0] == "Mihomo"),
			  outs[1] == "Meta",
			  outs[3] == "darwin" else {
			return nil
		}

		let version = outs[2]

		let dateString = [outs[7], outs[8], outs[9], outs[10], outs[12]].joined(separator: "-")
		let f = DateFormatter()
		f.dateFormat = "E-MMM-d-HH:mm:ss-yyyy"
		f.timeZone = .init(abbreviation: outs[11])
		let date = f.date(from: dateString)

		return (version: version, date: date)
	}

	private func validateDefaultCore(_ md5: String) -> Bool {
		guard let path = Paths.defaultCorePath()?.path,
			  chmodX(path) else { return false }

		#if DEBUG
			return true
		#endif
		let proc = Process()
		proc.executableURL = .init(fileURLWithPath: "/sbin/md5")
		proc.arguments = ["-q", path]
		let pipe = Pipe()
		proc.standardOutput = pipe

		try? proc.run()
		proc.waitUntilExit()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		guard proc.terminationStatus == 0,
			  let out = String(data: data, encoding: .utf8) else {
			return false
		}

		return md5 == out.replacingOccurrences(of: "\n", with: "")
	}

	private func chmodX(_ path: String) -> Bool {
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
	
	@objc func verify(_ confPath: String, confFilePath: String) -> String? {
		do {
			guard let path = launchPath.path else { return nil }
			
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
			   re.hasSuffix("verify is successful") {
				return nil
			} else if re.hasPrefix("configuration file"),
					  re.hasSuffix("verify failed") {
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
}
