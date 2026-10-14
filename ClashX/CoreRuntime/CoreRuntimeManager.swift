import Foundation

final class CoreRuntimeManager {
    static let shared = CoreRuntimeManager()

    private(set) var kind: CoreRuntimeKind

    private init() {
        let selected = CoreRuntimeSelector.current()
        if selected == .mihomo, MihomoCoreRuntime.isPackaged {
            kind = .mihomo
        } else {
            kind = .legacy
        }
    }

    func initialize() {
        if kind == .legacy {
            LegacyCoreRuntime.initialize()
        }
    }

    func start(checkConfig: Bool, allowLan: Bool) -> String {
        switch kind {
        case .legacy:
            return run(checkConfig.goObject(), allowLan.goObject())?.toString() ?? ""
        case .mihomo:
            let result = MihomoCoreRuntime.start(configPath: kDefaultConfigFilePath) ?? ""
            if let data = result.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
                return result
            }
            Logger.log("Mihomo failed to start; falling back to legacy core: \(result)", level: .error)
            MihomoCoreRuntime.stop()
            kind = .legacy
            LegacyCoreRuntime.initialize()
            return run(checkConfig.goObject(), allowLan.goObject())?.toString() ?? result
        }
    }

    func stop() {
        if kind == .mihomo { MihomoCoreRuntime.stop() }
    }

    var displayName: String {
        switch kind {
        case .mihomo: return "Mihomo v\(MihomoCoreRuntime.version)"
        case .legacy: return "Legacy Clash"
        }
    }
}
