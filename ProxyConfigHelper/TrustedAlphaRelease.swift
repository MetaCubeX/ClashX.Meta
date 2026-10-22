import Foundation
import CryptoKit
import zlib

struct TrustedAlphaPayload: Sendable {
    let data: Data
    let version: String
    let assetID: Int
    let releaseID: Int
    let archiveSHA256: String
    let executableSHA256: String
}

enum TrustedAlphaRelease {
    fileprivate static let metadataURL = URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha")!
    fileprivate static let smallDownloadLimit = 2 * 1024 * 1024
    fileprivate static let archiveLimit = 128 * 1024 * 1024
    fileprivate static let executableLimit = 256 * 1024 * 1024

    fileprivate struct Release: Decodable {
        let id: Int
        let tagName: String
        let draft: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case id, draft, assets
            case tagName = "tag_name"
        }
    }

    fileprivate struct Asset: Decodable {
        let id: Int
        let name: String
        let state: String
        let size: Int
        let browserDownloadURL: String
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case id, name, state, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    static func fetch() async throws -> TrustedAlphaPayload {
        let metadata = try await BoundedDownload(url: metadataURL, limit: smallDownloadLimit,
                                                 timeout: 30, metadata: true).download()
        let release = try JSONDecoder().decode(Release.self, from: metadata)
        let architecture = try nativeArchitecture()
        let (archiveAsset, checksumAsset, version) = try selectAssets(release, architecture: architecture)
        let checksumURL = try assetURL(checksumAsset, limit: smallDownloadLimit)
        let archiveURL = try assetURL(archiveAsset, limit: archiveLimit)

        let checksums = try await BoundedDownload(url: checksumURL, limit: smallDownloadLimit,
                                                  timeout: 30).download()
        try validateAssetData(checksums, asset: checksumAsset)
        let expectedSHA256 = try checksum(checksums, fileName: archiveAsset.name)
        let archive = try await BoundedDownload(url: archiveURL, limit: archiveLimit,
                                                timeout: 120).download()
        try validateAssetData(archive, asset: archiveAsset)
        guard sha256(archive) == expectedSHA256 else {
            throw AlphaError.invalid("The official Alpha archive does not match its SHA256 checksum.")
        }

        let executable = try decompress(archive)
        try validateExecutable(executable, architecture: architecture)
        return TrustedAlphaPayload(data: executable, version: version,
                                   assetID: archiveAsset.id, releaseID: release.id,
                                   archiveSHA256: expectedSHA256,
                                   executableSHA256: sha256(executable))
    }

    fileprivate static func nativeArchitecture() throws -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "amd64"
        #else
        throw AlphaError.invalid("This Mac architecture is not supported by the Alpha updater.")
        #endif
    }

    fileprivate static func selectAssets(_ release: Release, architecture: String) throws -> (Asset, Asset, String) {
        guard release.id > 0, release.tagName == "Prerelease-Alpha", !release.draft,
              architecture == "arm64" || architecture == "amd64" else {
            throw AlphaError.invalid("The official Alpha release metadata is invalid.")
        }
        let prefix = "mihomo-darwin-\(architecture)-alpha-"
        let archives = release.assets.filter { $0.name.hasPrefix(prefix) && $0.name.hasSuffix(".gz") }
        let checksumAssets = release.assets.filter { $0.name == "checksums.txt" }
        guard archives.count == 1, checksumAssets.count == 1,
              let archive = archives.first, let checksums = checksumAssets.first,
              archive.id != checksums.id else {
            throw AlphaError.invalid("The official Alpha release must contain exactly one matching core and checksums.txt.")
        }
        let suffix = String(archive.name.dropFirst(prefix.count).dropLast(3))
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.".utf8)
        guard !suffix.isEmpty, suffix.utf8.count <= 96,
              suffix.utf8.allSatisfy({ allowed.contains($0) }),
              suffix.first?.isLetter == true || suffix.first?.isNumber == true else {
            throw AlphaError.invalid("The official Alpha asset has an invalid version name.")
        }
        return (archive, checksums, "alpha-\(suffix)")
    }

    fileprivate static func assetURL(_ asset: Asset, limit: Int) throws -> URL {
        let expected = "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/\(asset.name)"
        guard asset.id > 0, asset.state == "uploaded", asset.size > 0, asset.size <= limit,
              asset.browserDownloadURL == expected, let url = URL(string: expected) else {
            throw AlphaError.invalid("The official Alpha asset has an invalid source, size, or upload state.")
        }
        return url
    }

    fileprivate static func validateAssetData(_ data: Data, asset: Asset) throws {
        guard data.count == asset.size else {
            throw AlphaError.invalid("The official Alpha asset changed during download or was truncated.")
        }
        if let digest = asset.digest {
            guard digest.hasPrefix("sha256:"),
                  validSHA256(String(digest.dropFirst(7))),
                  sha256(data) == digest.dropFirst(7).lowercased() else {
                throw AlphaError.invalid("The Alpha asset does not match the official release metadata digest.")
            }
        }
    }

    fileprivate static func checksum(_ data: Data, fileName: String) throws -> String {
        guard data.count <= smallDownloadLimit, let text = String(data: data, encoding: .utf8) else {
            throw AlphaError.invalid("The official checksum file is invalid.")
        }
        var matches = [String]()
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 2 else { continue }
            var name = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasPrefix("*") { name.removeFirst() }
            // The official release workflow feeds `find .` output to sha256sum.
            if name.hasPrefix("./") { name.removeFirst(2) }
            if name == fileName {
                let digest = String(fields[0])
                guard validSHA256(digest) else {
                    throw AlphaError.invalid("The official checksum is not a SHA256 digest.")
                }
                matches.append(digest.lowercased())
            }
        }
        guard matches.count == 1, let digest = matches.first else {
            throw AlphaError.invalid("The official checksum file must contain exactly one checksum for the selected Alpha core.")
        }
        return digest
    }

    fileprivate static func validSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    fileprivate static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func decompress(_ archive: Data, limit: Int = executableLimit) throws -> Data {
        guard !archive.isEmpty, archive.count <= archiveLimit, limit > 0, limit <= executableLimit else {
            throw AlphaError.invalid("The Alpha archive size is invalid.")
        }
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw AlphaError.invalid("The Alpha archive decompressor could not be initialized.")
        }
        defer { inflateEnd(&stream) }

        return try archive.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(input.count)
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try Task.checkCancellation()
                let (status, count) = buffer.withUnsafeMutableBytes { chunk -> (Int32, Int) in
                    stream.next_out = chunk.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = uInt(chunk.count)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    return (status, chunk.count - Int(stream.avail_out))
                }
                guard count <= limit - output.count else {
                    throw AlphaError.tooLarge
                }
                output.append(contentsOf: buffer.prefix(count))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0, !output.isEmpty else {
                        throw AlphaError.invalid("The Alpha gzip archive has trailing data or an empty executable.")
                    }
                    return output
                }
                guard status == Z_OK, count > 0 || stream.avail_in > 0 else {
                    throw AlphaError.invalid("The Alpha gzip archive is corrupt or incomplete.")
                }
            }
        }
    }

    fileprivate static func validateExecutable(_ data: Data, architecture: String) throws {
        guard data.count >= 32 else { throw AlphaError.invalid("The Alpha executable is truncated.") }
        let header = [UInt8](data.prefix(16))
        let expectedCPU: [UInt8] = architecture == "arm64" ? [12, 0, 0, 1] : [7, 0, 0, 1]
        guard architecture == "arm64" || architecture == "amd64",
              Array(header[0..<4]) == [0xcf, 0xfa, 0xed, 0xfe],
              Array(header[4..<8]) == expectedCPU,
              Array(header[12..<16]) == [2, 0, 0, 0] else {
            throw AlphaError.invalid("The Alpha executable is not a Mach-O binary for this Mac.")
        }
    }

    fileprivate enum AlphaError: LocalizedError {
        case invalid(String)
        case tooLarge
        case untrustedURL
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case let .invalid(reason): return reason
            case .tooLarge: return "The official Alpha download or executable exceeds its size limit."
            case .untrustedURL: return "The Alpha updater refused an unexpected download URL or redirect."
            case let .httpStatus(status): return "The official Alpha download returned HTTP \(status)."
            }
        }
    }

    fileprivate final class BoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        fileprivate let url: URL
        fileprivate let limit: Int
        fileprivate let timeout: TimeInterval
        fileprivate let metadata: Bool
        fileprivate let lock = NSLock()
        fileprivate var continuation: CheckedContinuation<Data, Error>?
        fileprivate var session: URLSession?
        fileprivate var cancelled = false
        fileprivate var receivedResponse = false
        fileprivate var redirects = 0
        fileprivate var data = Data()

        init(url: URL, limit: Int, timeout: TimeInterval, metadata: Bool = false) {
            self.url = url
            self.limit = limit
            self.timeout = timeout
            self.metadata = metadata
        }

        func download() async throws -> Data {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { start($0) }
            } onCancel: {
                self.lock.lock()
                self.cancelled = true
                self.lock.unlock()
                self.finish(.failure(CancellationError()))
            }
        }

        fileprivate func start(_ continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            guard !cancelled, permitted(url) else {
                let error: Error = cancelled ? CancellationError() : AlphaError.untrustedURL
                lock.unlock()
                continuation.resume(throwing: error)
                return
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = min(timeout, 30)
            configuration.timeoutIntervalForResource = timeout
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            self.continuation = continuation
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: min(timeout, 30))
            request.setValue("ClashX-Meta-PrivilegedHelper", forHTTPHeaderField: "User-Agent")
            request.setValue(metadata ? "application/vnd.github+json" : "application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if metadata { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
            request.httpShouldHandleCookies = false
            let task = session.dataTask(with: request)
            lock.unlock()
            task.resume()
        }

        fileprivate func permitted(_ candidate: URL) -> Bool {
            guard let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
                  components.scheme?.lowercased() == "https", components.user == nil,
                  components.password == nil, components.fragment == nil,
                  components.port == nil || components.port == 443,
                  let host = components.host?.lowercased() else { return false }
            if metadata { return candidate.absoluteString == TrustedAlphaRelease.metadataURL.absoluteString }
            if host == "github.com" { return candidate.absoluteString == url.absoluteString }
            return ["release-assets.githubusercontent.com", "objects.githubusercontent.com",
                    "github-releases.githubusercontent.com"].contains(host)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            lock.lock()
            redirects += 1
            let active = continuation != nil && redirects <= 5
            lock.unlock()
            guard active, request.httpMethod == "GET", let target = request.url, permitted(target) else {
                completionHandler(nil)
                finish(.failure(AlphaError.untrustedURL))
                return
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let response = response as? HTTPURLResponse, let source = response.url, permitted(source) else {
                completionHandler(.cancel)
                finish(.failure(AlphaError.untrustedURL))
                return
            }
            guard response.statusCode == 200 else {
                completionHandler(.cancel)
                finish(.failure(AlphaError.httpStatus(response.statusCode)))
                return
            }
            guard response.expectedContentLength <= Int64(limit) else {
                completionHandler(.cancel)
                finish(.failure(AlphaError.tooLarge))
                return
            }
            lock.lock()
            receivedResponse = true
            let active = continuation != nil
            lock.unlock()
            completionHandler(active ? .allow : .cancel)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            lock.lock()
            guard continuation != nil else { lock.unlock(); return }
            guard chunk.count <= limit - data.count else {
                lock.unlock()
                finish(.failure(AlphaError.tooLarge))
                return
            }
            data.append(chunk)
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let result: Result<Data, Error> = error.map { .failure($0) }
                ?? (receivedResponse ? .success(data) : .failure(AlphaError.invalid("The Alpha download returned no response.")))
            lock.unlock()
            finish(result)
        }

        fileprivate func finish(_ result: Result<Data, Error>) {
            lock.lock()
            guard let continuation else { lock.unlock(); return }
            self.continuation = nil
            let session = self.session
            self.session = nil
            lock.unlock()
            session?.invalidateAndCancel()
            continuation.resume(with: result)
        }
    }
}
