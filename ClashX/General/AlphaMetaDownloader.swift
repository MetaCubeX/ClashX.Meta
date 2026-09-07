import Foundation

final class AlphaMetaDownloader {
    static func update() async throws -> ProxyConfigHelperAlphaInfo {
        try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.UpdateAlphaCore())
    }

    static func installed() async throws -> ProxyConfigHelperAlphaInfo? {
        try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.GetAlphaInfo())
    }
}
