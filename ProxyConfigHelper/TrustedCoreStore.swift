import Foundation

enum TrustedCoreStore {
    static let root = "/Library/Application Support/com.metacubex.ClashX.meta"
    static let coreName = "com.metacubex.ClashX.ProxyConfigHelper.meta"
    static let coreDirectory = root + "/Core"
    static let alphaDirectory = coreDirectory + "/Alpha"
    static let alphaPath = alphaDirectory + "/" + coreName
    static let runDirectory = root + "/Run"
    static let configName = "run_config.yaml"
    static let maximumCoreSize = 256 * 1024 * 1024

    struct AlphaReceipt: Codable {
        let version: String
        let assetID: Int
        let releaseID: Int
        let archiveSHA256: String
        let executableSHA256: String
    }

    static func bundled(source: String) throws -> String {
        let expected = BundledCoreTrust.sha256
        guard PrivilegedDirectory.isSHA256(expected) else { throw PrivilegedFileError.invalidCore }
        let directory = try PrivilegedDirectory.open(coreDirectory, create: true)
        if let installed = try? directory.read(coreName, limit: maximumCoreSize),
           PrivilegedDirectory.sha256(installed) == expected {
            return coreDirectory + "/" + coreName
        }
        let data = try PrivilegedDirectory.readSource(source, limit: maximumCoreSize)
        try directory.write(data, name: coreName, mode: 0o755, expectedSHA256: expected)
        return coreDirectory + "/" + coreName
    }

    static func alphaInfo() throws -> (path: String, receipt: AlphaReceipt) {
        let directory = try PrivilegedDirectory.open(alphaDirectory)
        let receipt = try JSONDecoder().decode(AlphaReceipt.self, from: directory.read("receipt.json", limit: 16 * 1024))
        guard PrivilegedDirectory.isSHA256(receipt.executableSHA256),
              PrivilegedDirectory.isSHA256(receipt.archiveSHA256) else {
            throw PrivilegedFileError.invalidCore
        }
        return (alphaDirectory + "/" + receipt.executableSHA256 + "/" + coreName, receipt)
    }

    static func alpha() throws -> (path: String, receipt: AlphaReceipt) {
        let info = try alphaInfo()
        let directory = try PrivilegedDirectory.open(alphaDirectory + "/" + info.receipt.executableSHA256)
        guard PrivilegedDirectory.sha256(try directory.read(coreName, limit: maximumCoreSize)) == info.receipt.executableSHA256 else {
            throw PrivilegedFileError.invalidCore
        }
        return info
    }

    static func installAlpha(_ payload: TrustedAlphaPayload) throws -> AlphaReceipt {
        guard payload.data.count <= maximumCoreSize,
              PrivilegedDirectory.isSHA256(payload.archiveSHA256),
              PrivilegedDirectory.isSHA256(payload.executableSHA256),
              PrivilegedDirectory.sha256(payload.data) == payload.executableSHA256 else {
            throw PrivilegedFileError.invalidCore
        }
        let directory = try PrivilegedDirectory.open(alphaDirectory, create: true)
        let previous = try? alphaInfo().receipt.executableSHA256
        let receipt = AlphaReceipt(version: payload.version, assetID: payload.assetID, releaseID: payload.releaseID,
                                   archiveSHA256: payload.archiveSHA256, executableSHA256: payload.executableSHA256)
        let versionDirectory = try PrivilegedDirectory.open(alphaDirectory + "/" + payload.executableSHA256, create: true)
        try versionDirectory.write(payload.data, name: coreName, mode: 0o755, expectedSHA256: payload.executableSHA256)
        // Publishing this receipt is the commit point; an interrupted install leaves the previous version usable.
        // This public receipt contains only release identifiers and digests, never credentials or configuration.
        try directory.write(JSONEncoder().encode(receipt), name: "receipt.json", mode: 0o644)
        // Reinstalling the same executable must retain the previous distinct version.
        if previous == payload.executableSHA256 { return receipt }
        let retained = Set([payload.executableSHA256, previous].compactMap { $0 })
        for name in (try? FileManager.default.contentsOfDirectory(atPath: alphaDirectory)) ?? [] {
            guard PrivilegedDirectory.isSHA256(name), !retained.contains(name),
                  let obsolete = try? PrivilegedDirectory.open(alphaDirectory + "/" + name) else { continue }
            do {
                try obsolete.remove(coreName)
                try directory.removeDirectory(name)
            } catch { /* A nonempty or unsafe directory is left intact. */ }
        }
        return receipt
    }

    static func writeConfig(_ data: Data) throws -> String {
        guard !data.isEmpty, data.count <= 4 * 1024 * 1024 else { throw PrivilegedFileError.oversizedFile }
        let directory = try PrivilegedDirectory.open(runDirectory, create: true, mode: 0o700)
        try directory.write(data, name: configName, mode: 0o600)
        return runDirectory + "/" + configName
    }
}
