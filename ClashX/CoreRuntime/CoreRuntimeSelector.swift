import Foundation

enum CoreRuntimeKind: String, Equatable {
    case legacy
    case mihomo
}

struct CoreRuntimeSelector {
    static let overrideKey = "CoreRuntimeOverride"

    static func select(majorVersion: Int,
                       override: String? = nil) -> CoreRuntimeKind {
        if let value = override?.lowercased(), let kind = CoreRuntimeKind(rawValue: value) {
            return kind
        }
        return majorVersion >= 13 ? .mihomo : .legacy
    }

    static func current(defaults: UserDefaults = .standard,
                        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> CoreRuntimeKind {
        select(majorVersion: operatingSystemVersion.majorVersion,
               override: defaults.string(forKey: overrideKey))
    }
}
