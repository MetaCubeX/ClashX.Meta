//
//  ClashConfig.swift
//  ClashX
//
//  Created by CYC on 2018/7/30.
//  Copyright © 2018年 yichengchen. All rights reserved.
//
import CocoaLumberjack
import Foundation

enum ClashProxyMode: String, Codable {
    case rule
    case global
    case direct
    #if PRO_VERSION
        case script
    #endif
}

extension ClashProxyMode {
    var name: String {
        switch self {
        case .rule: return NSLocalizedString("Rule", comment: "")
        case .global: return NSLocalizedString("Global", comment: "")
        case .direct: return NSLocalizedString("Direct", comment: "")
        #if PRO_VERSION
            case .script: return NSLocalizedString("Script", comment: "")
        #endif
        }
    }
}

enum ClashLogLevel: String, Codable {
    case info
    #if PRO_VERSION
        case warning = "warn"
    #else
        case warning
    #endif
    case error
    case debug
    case silent
    case unknow = "unknown"

    func toDDLogLevel() -> DDLogLevel {
        switch self {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        case .debug:
            return .debug
        case .silent:
            return .off
        case .unknow:
            return .error
        }
    }
}

class ClashConfig: Codable {
    private var port: Int
    private var socksPort: Int
    var allowLan: Bool
    var mixedPort: Int
    var mode: ClashProxyMode
    var logLevel: ClashLogLevel

    var usedHttpPort: Int {
        if mixedPort > 0 {
            return mixedPort
        }
        return port
    }

    var usedSocksPort: Int {
        if mixedPort > 0 {
            return mixedPort
        }
        return socksPort
    }

    private enum CodingKeys: String, CodingKey {
        case port, socksPort = "socks-port", mixedPort = "mixed-port", allowLan = "allow-lan", mode, logLevel = "log-level"
    }

    static func fromData(_ data: Data) -> ClashConfig? {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ClashConfig.self, from: data)
        } catch let err {
            Logger.log((err as NSError).description, level: .error)
            return nil
        }
    }

    func copy() -> ClashConfig? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let copy = try? JSONDecoder().decode(ClashConfig.self, from: data)
        return copy
    }
}
