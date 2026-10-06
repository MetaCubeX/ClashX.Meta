//
//  ProxyGroupCollapseStore.swift
//  ClashX Dashboard
//
//  Persists per-group collapse state as [groupName: isCollapsed] in UserDefaults,
//  scoped per config name so local and remote configs never share collapse states.
//

import Foundation

class ProxyGroupCollapseStore {
	static let shared = ProxyGroupCollapseStore()

	private static let keyPrefix = "DashboardProxyGroupCollapse"

	private static func userDefaultsKey(for config: String) -> String {
		"\(keyPrefix).\(config)"
	}

	private var cache: [String: [String: Bool]] = [:]

	private init() {}

	func isCollapsed(_ name: String) -> Bool {
		dict(for: ConfigManager.selectConfigName)[name] ?? false
	}

	func setCollapsed(_ value: Bool, for name: String) {
		let config = ConfigManager.selectConfigName
		var dict = self.dict(for: config)
		guard dict[name] != value else { return }
		dict[name] = value
		cache[config] = dict
		UserDefaults.standard.set(dict, forKey: Self.userDefaultsKey(for: config))
	}

	private func dict(for config: String) -> [String: Bool] {
		if let cached = cache[config] {
			return cached
		}
		let loaded = UserDefaults.standard.dictionary(forKey: Self.userDefaultsKey(for: config)) as? [String: Bool] ?? [:]
		cache[config] = loaded
		return loaded
	}
}
