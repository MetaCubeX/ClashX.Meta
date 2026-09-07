//
//  ClashMetaConfig.swift
//  ClashX Meta

import Foundation
import Cocoa
import Yams

class ClashMetaConfig: NSObject {
	static let initRulePayload = "ClashXMetaInitConfigQWERTYUIOP".lowercased()

    struct Config: Codable {
        var externalUI: String? = {
			var subpath = "dashboard/"
            
            switch ConfigManager.webDashboard {
            case .yacd:
                subpath += "yacd"
            case .metacubexd:
                subpath += "xd"
            case .zashboard:
                subpath += "zashboard"
            }
            
            guard let htmlPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: subpath) else {
                return nil
            }
            return URL(fileURLWithPath: htmlPath).deletingLastPathComponent().path
        }()

        var externalController = "127.0.0.1:9090"
        var externalControllerUnix: String?
        var secret: String?

        var port: Int?
        var socksPort: Int?
        var mixedPort: Int?

        var geodataMode: Bool?
		var geoxUrl: [String: String]?

        var logLevel = ConfigOverride.shared.logLevel.rawValue
		
		var rules = ["DOMAIN-KEYWORD,\(initRulePayload),REJECT"]
        
        var safePaths: String?

        var encodedData: Data? {
            guard let yaml = try? YAMLEncoder().encode(self) else { return nil }
            return yaml.data(using: .utf8)
        }

        var path: String {
            get {
                guard let s = try? YAMLEncoder().encode(self),
                      let path = RemoteConfigManager.createCacheConfig(string: s) else {
                    assertionFailure("Create init config file failed.")
                    return ""
                }
                return path
            }
        }

        enum CodingKeys: String, CodingKey {
            case externalController = "external-controller",
                 externalControllerUnix = "external-controller-unix",
                 externalUI = "external-ui",
                 mixedPort = "mixed-port",
                 port,
                 socksPort = "socks-port",
                 logLevel = "log-level",
                 geodataMode = "geodata-mode",
				 geoxUrl = "geox-url",
                 secret,
				 rules
        }

        mutating func loadDefaultConfigFile(_ path: String) {
            let fm = FileManager.default
            guard let data = fm.contents(atPath: path),
                  let string = String(data: data, encoding: .utf8),
                  let yaml = try? Yams.load(yaml: string) as? [String: Any] else {
                return
            }

            let keys = Config.CodingKeys.self
            if let ec = yaml[keys.externalController.rawValue] as? String {
                externalController = ec
            }

            if let ecUnix = yaml[keys.externalControllerUnix.rawValue] as? String {
                externalControllerUnix = ecUnix
            } else {
                let randomStr = {
                    let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
                    return String((0..<5).map { _ in chars.randomElement()! })
                }()
                externalControllerUnix = "/tmp/clashx_meta_\(randomStr).sock"
            }

            if let s = yaml[keys.secret.rawValue] as? String {
                secret = s
            }

            if let port = yaml[keys.mixedPort.rawValue] as? Int {
                mixedPort = port
            } else {
                if let p = yaml[keys.port.rawValue] as? Int {
                    port = p
                }
                if let sp = yaml[keys.socksPort.rawValue] as? Int {
                    socksPort = sp
                }
            }

            if port == nil && mixedPort == nil {
                mixedPort = 7890
            }
			
			if let urls = yaml[keys.geoxUrl.rawValue] as? [String: String] {
				geoxUrl = urls
			}
			
			if let mode = yaml[keys.geodataMode.rawValue] as? Bool {
				geodataMode = mode
			}
				
        }

        mutating func updatePorts(_ usedPorts: String) {
            let usedPorts = usedPorts.split(separator: ",").compactMap {
                Int($0)
            }

            var availablePorts = Set(1..<65534)
            availablePorts.subtract(usedPorts)

            func update(_ port: Int?) -> Int? {
                guard let p = port, p != 0 else {
                    return port
                }

                if availablePorts.contains(p) {
                    availablePorts.remove(p)
                    return p
                } else if let p = Set(p..<65534).intersection(availablePorts).min() {
                    availablePorts.remove(p)
                    return p
                } else {
                    return nil
                }
            }

            port = update(port)
            socksPort = update(socksPort)
            mixedPort = update(mixedPort)

            let ecPort: Int = {
                if let port = externalController.components(separatedBy: ":").last,
                   let p = Int(port) {
                    return p
                } else {
                    return 9090
                }
            }()

            externalController = "127.0.0.1:\(update(ecPort) ?? 9090)"
        }
    }

    static func generateInitConfig() async -> Config {
        var config = Config()
        let path = await ApiRequest.findConfigPath(configName: ConfigManager.selectConfigName)
		config.loadDefaultConfigFile(path ?? "")
		ApiRequestTransport.unixSocketPath = config.externalControllerUnix
		return config
    }

    static func updateConfigTun(_ config: Data, enable: Bool) -> String? {
        guard let s = String(data: config, encoding: .utf8),
              var yaml = try? Yams.compose(yaml: s) else {
            return nil
        }

        if yaml["tun"] != nil {
            yaml["tun"]!["enable"] = .init("\(enable)")
        } else {
            yaml["tun"] = [
                "enable": .init("\(enable)"),
                "stack": "system",
                "auto-route": "true",
                "auto-detect-interface": "true",
                "dns-hijack": [
                    "any:53"
                ]
            ]
        }

        guard let ss = try? Yams.serialize(node: yaml),
              let path = RemoteConfigManager.createCacheConfig(string: ss) else {
            return nil
        }
        return path
    }
}
