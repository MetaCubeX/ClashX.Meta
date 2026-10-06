//
//  DBProxyStorage.swift
//  ClashX Dashboard
//
//

import Cocoa
import CryptoKit
import SwiftUI

class DBProxyStorage: ObservableObject {
	@Published var groups = [DBProxyGroup]()
	
	init() {
		
	}
	
	init(_ resp: ClashProxyResp) {
		groups = resp.proxyGroups.map {
			DBProxyGroup($0, resp: resp)
		}
	}

	func updateGroups(_ newGroups: [DBProxyGroup]) {
		var map = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0) })
		for newGroup in newGroups {
			if let existing = map[newGroup.name] {
				existing.update(from: newGroup)
			} else {
				groups.append(newGroup)
				map[newGroup.name] = newGroup
			}
		}
		let newNames = Set(newGroups.map(\.name))
		groups.removeAll { !newNames.contains($0.name) }
	}
}

class DBProxyGroup: ObservableObject, Identifiable {
	let id = UUID().uuidString
	@Published var name: ClashProxyName
	@Published var type: ClashProxyType
	@Published var now: ClashProxyName? {
		didSet {
			currentProxy = proxies.first {
				$0.name == now
			}
		}
	}
	
	@Published var proxies: [DBProxy]
	@Published var currentProxy: DBProxy?
	
	@Published var isOpen: Bool = true {
		didSet {
			ProxyGroupCollapseStore.shared.setCollapsed(!isOpen, for: name)
		}
	}
	@Published var hidden: Bool
    
    init(_ group: ClashProxy, resp: ClashProxyResp) {
        name = group.name
        type = group.type
        now = group.now
        hidden = group.hidden ?? false
        isOpen = !ProxyGroupCollapseStore.shared.isCollapsed(group.name)

        proxies = group.all?.compactMap { name in
            resp.proxiesMap[name]
        }.map(DBProxy.init) ?? []
        
        currentProxy = proxies.first {
            $0.name == now
        }
    }

    func update(from other: DBProxyGroup) {
        name = other.name
        type = other.type
        hidden = other.hidden
        now = other.now
        proxies = other.proxies
        currentProxy = proxies.first { $0.name == now }
    }
}

class DBProxy: ObservableObject {
	let id: String
	@Published var name: ClashProxyName
	@Published var type: ClashProxyType
	@Published var udpString: String
	@Published var tfo: Bool
	
	var delay: Int {
		didSet {
			delayString = DBProxy.delayString(delay)
			delayColor = DBProxy.delayColor(delay)
		}
	}
	
	@Published var delayString: String
	@Published var delayColor: Color
	
	init(_ proxy: ClashProxy) {
		id = proxy.id ?? UUID().uuidString
		name = proxy.name
		type = proxy.type
		tfo = proxy.tfo
		delay = proxy.history.last?.delayInt ?? 0
				
		udpString = {
			if proxy.udp {
				return "UDP"
			} else if proxy.xudp {
				return "XUDP"
			} else {
				return ""
			}
		}()
		delayString = DBProxy.delayString(delay)
		delayColor = DBProxy.delayColor(delay)
	}
	
	static func delayString(_ delay: Int) -> String {
		switch delay {
		case 0:
			return "--"
		default:
			return "\(delay) ms"
		}
	}
	
	static func delayColor(_ delay: Int) -> Color {
		let httpsTest = ConfigManager.shared.benchMarkUrl.hasPrefix("https://")
		let good = httpsTest ? 800 : 200
		let normal = httpsTest ? 1500 : 500
		
		switch delay {
		case 0:
			return .secondary
		case ..<good:
			return DashboardTheme.latencyGood
		case ..<normal:
			return DashboardTheme.latencyNormal
		default:
			return DashboardTheme.latencySlow
		}
	}
}

extension ClashProxyType {
	var displayString: String {
		switch self {
		case .proxy("Shadowsocks"):
			return "SS"
		default:
			return rawString
		}
	}
}


/// Privacy alias for proxy/provider names shown in the UI: the name is
/// hashed to a stable 64-char digest, and a per-launch seed picks the
/// window offset — tokens stay fixed for the whole session (immune to
/// data refreshes) but change on every app restart.
@MainActor
enum HiddenNameToken {
	private static let length = 8
	// Per-launch slicing seed; not persisted so aliases reshuffle each run.
	private static let seed = UInt64.random(in: 0..<UInt64.max)
	// Session cache: displayName walks all groups per frame when hiding.
	private static var cache: [String: String] = [:]

	static func token(for name: String) -> String {
		if let hit = cache[name] { return hit }
		let digest = SHA256.hash(data: Data(name.utf8))
			.map { String(format: "%02x", $0) }.joined()
		let offset = Int(seed % UInt64(digest.count - length))
		let token = String(digest.dropFirst(offset).prefix(length))
		cache[name] = token
		return token
	}
}
