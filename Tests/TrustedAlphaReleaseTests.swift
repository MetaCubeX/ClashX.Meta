@main struct AlphaFixtureTests {
    static var checks = 0
    static func require(_ condition: Bool, _ label: String) { checks += 1; if !condition { fatalError(label) } }
    static func rejected(_ label: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected rejection: " + label) } catch { checks += 1 }
    }
    static func rejectedAsync(_ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); fatalError("Expected rejection: " + label) } catch { checks += 1 }
    }
    fileprivate static func simulated(_ downloader: TrustedAlphaRelease.BoundedDownload,
                          events: (TrustedAlphaRelease.BoundedDownload, URLSession, URLSessionDataTask) -> Void) async throws -> Data {
        let session = URLSession(configuration: .ephemeral)
        // Delegate events are injected directly; this task is never resumed.
        let task = session.dataTask(with: downloader.url)
        defer { session.invalidateAndCancel() }
        return try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            downloader.session = session
            events(downloader, session, task)
        }
    }
    static func injected(limit: Int, declaredSize: Int?, chunks: [Data], status: Int = 200) async throws -> Data {
        let url = URL(string: "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/checksums.txt")!
        let downloader = TrustedAlphaRelease.BoundedDownload(url: url, limit: limit, timeout: 1)
        return try await simulated(downloader) { downloader, session, task in
            let headers = declaredSize.map { ["Content-Length": String($0)] } ?? [:]
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            downloader.urlSession(session, dataTask: task, didReceive: response) { decision in
                guard decision == .allow else { return }
                for chunk in chunks { downloader.urlSession(session, dataTask: task, didReceive: chunk) }
                downloader.urlSession(session, task: task, didCompleteWithError: nil)
            }
        }
    }
    static func metadataEdges(archive: Data, name: String, digest: String) throws {
        let source = "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/"
        let core: [String: Any] = ["id": 101, "name": name, "state": "uploaded", "size": archive.count,
                                   "browser_download_url": source + name, "digest": "sha256:" + digest]
        let checksumAsset: [String: Any] = ["id": 102, "name": "checksums.txt", "state": "uploaded", "size": 80,
                                            "browser_download_url": source + "checksums.txt"]
        let metadata: [String: Any] = ["id": 100, "tag_name": "Prerelease-Alpha", "draft": false,
                                       "assets": [core, checksumAsset]]
        func decode(_ value: [String: Any]) throws -> TrustedAlphaRelease.Release {
            try JSONDecoder().decode(TrustedAlphaRelease.Release.self, from: JSONSerialization.data(withJSONObject: value))
        }
        func selected(_ value: [String: Any], architecture: String = "arm64") throws -> TrustedAlphaRelease.Asset {
            try TrustedAlphaRelease.selectAssets(decode(value), architecture: architecture).0
        }
        require(try selected(metadata).id == 101, "Decode official JSON field names")
        for field in ["id", "tag_name", "draft", "assets"] {
            var missing = metadata; missing.removeValue(forKey: field)
            rejected("missing release field " + field) { _ = try selected(missing) }
        }
        for field in ["id", "name", "state", "size", "browser_download_url"] {
            var missingCore = core; missingCore.removeValue(forKey: field)
            var missing = metadata; missing["assets"] = [missingCore, checksumAsset]
            rejected("missing core field " + field) { _ = try selected(missing) }
        }
        for (field, value) in [("id", "100" as Any), ("draft", "false" as Any), ("assets", NSNull())] {
            var malformed = metadata; malformed[field] = value
            rejected("incorrect JSON type " + field) { _ = try selected(malformed) }
        }
        for value in [0, -1] {
            var malformed = metadata; malformed["id"] = value
            rejected("nonpositive release ID") { _ = try selected(malformed) }
        }
        var draft = metadata; draft["draft"] = true
        rejected("draft release") { _ = try selected(draft) }
        rejected("unsupported release architecture") { _ = try selected(metadata, architecture: "riscv64") }
        for assets in [[], [core], [checksumAsset], [core, checksumAsset, checksumAsset]] {
            var malformed = metadata; malformed["assets"] = assets
            rejected("missing or duplicate required assets") { _ = try selected(malformed) }
        }
        var duplicateID = checksumAsset; duplicateID["id"] = 101
        var malformed = metadata; malformed["assets"] = [core, duplicateID]
        rejected("archive and checksum share asset ID") { _ = try selected(malformed) }
        for suffix in ["", "../core", "%2fcore", "-abc", "éabc", String(repeating: "a", count: 97)] {
            var badCore = core; badCore["name"] = "mihomo-darwin-arm64-alpha-" + suffix + ".gz"
            var badRelease = metadata; badRelease["assets"] = [badCore, checksumAsset]
            rejected("invalid Alpha version suffix " + suffix) { _ = try selected(badRelease) }
        }
        var x86 = core
        x86["id"] = 103
        x86["name"] = "mihomo-darwin-amd64-alpha-abc1234.gz"
        x86["browser_download_url"] = source + (x86["name"] as! String)
        var multiarch = metadata; multiarch["assets"] = [x86, core, checksumAsset]
        require(try selected(multiarch).id == 101, "Select arm64 from a multi-architecture release")
        require(try selected(multiarch, architecture: "amd64").id == 103, "Select amd64 from a multi-architecture release")
        for (field, value) in [("id", 0 as Any), ("size", 0 as Any), ("size", -1 as Any),
                               ("size", TrustedAlphaRelease.archiveLimit + 1 as Any), ("state", "new" as Any)] {
            var badCore = core; badCore[field] = value
            var badRelease = metadata; badRelease["assets"] = [badCore, checksumAsset]
            rejected("invalid selected asset " + field) {
                _ = try TrustedAlphaRelease.assetURL(selected(badRelease), limit: TrustedAlphaRelease.archiveLimit)
            }
        }
        for badURL in [source.replacingOccurrences(of: "https:", with: "http:") + name,
                       source + name + "?download=1", source + name + "#fragment",
                       source.replacingOccurrences(of: "Prerelease-Alpha", with: "v1.0") + name,
                       source.replacingOccurrences(of: "github.com", with: "github.com.evil.example") + name,
                       source.replacingOccurrences(of: "github.com", with: "user@github.com") + name] {
            var badCore = core; badCore["browser_download_url"] = badURL
            var badRelease = metadata; badRelease["assets"] = [badCore, checksumAsset]
            rejected("unexpected asset download URL") {
                _ = try TrustedAlphaRelease.assetURL(selected(badRelease), limit: TrustedAlphaRelease.archiveLimit)
            }
        }
        for value in ["", "sha512:" + digest, "sha256:" + String(digest.dropLast()),
                      "sha256:" + digest + "0", "sha256:" + String(repeating: "g", count: 64)] {
            var badCore = core; badCore["digest"] = value
            var badRelease = metadata; badRelease["assets"] = [badCore, checksumAsset]
            rejected("malformed metadata digest") { try TrustedAlphaRelease.validateAssetData(archive, asset: selected(badRelease)) }
        }
        for missingDigest in [false, true] {
            var optionalCore = core
            if missingDigest { optionalCore.removeValue(forKey: "digest") } else { optionalCore["digest"] = NSNull() }
            var optionalRelease = metadata; optionalRelease["assets"] = [optionalCore, checksumAsset]
            try TrustedAlphaRelease.validateAssetData(archive, asset: selected(optionalRelease)); checks += 1
        }
        var uppercaseCore = core; uppercaseCore["digest"] = "sha256:" + digest.uppercased()
        var uppercase = metadata; uppercase["assets"] = [uppercaseCore, checksumAsset]
        try TrustedAlphaRelease.validateAssetData(archive, asset: selected(uppercase)); checks += 1
    }
    static func downloadEdges(source: String) async throws {
        let initial = URL(string: source)!
        let cdn = URL(string: "https://release-assets.githubusercontent.com/release/file?token=fixture")!
        func downloader(metadata: Bool = false) -> TrustedAlphaRelease.BoundedDownload {
            TrustedAlphaRelease.BoundedDownload(url: metadata ? TrustedAlphaRelease.metadataURL : initial,
                                                limit: 8, timeout: 1, metadata: metadata)
        }
        func redirected(_ download: TrustedAlphaRelease.BoundedDownload, requests: [URLRequest]) async throws -> Data {
            try await simulated(download) { download, session, task in
                let response = HTTPURLResponse(url: download.url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
                for request in requests {
                    var accepted = false
                    download.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) {
                        accepted = $0 != nil
                    }
                    if !accepted { return }
                }
                download.finish(.success(Data([1])))
            }
        }
        let request = URLRequest(url: cdn)
        require(try await redirected(downloader(), requests: Array(repeating: request, count: 5)) == Data([1]), "Exactly five redirects are allowed")
        await rejectedAsync("sixth redirect") { _ = try await redirected(downloader(), requests: Array(repeating: request, count: 6)) }
        for destination in ["http://release-assets.githubusercontent.com/file", "https://evil.example/file"] {
            await rejectedAsync("redirect to unsafe destination") {
                _ = try await redirected(downloader(), requests: [URLRequest(url: URL(string: destination)!)])
            }
        }
        var post = request; post.httpMethod = "POST"
        await rejectedAsync("redirect changes GET to POST") { _ = try await redirected(downloader(), requests: [post]) }
        await rejectedAsync("metadata cannot redirect to CDN") { _ = try await redirected(downloader(metadata: true), requests: [request]) }
        let metadataQuery = URLRequest(url: URL(string: TrustedAlphaRelease.metadataURL.absoluteString + "?page=2")!)
        await rejectedAsync("metadata endpoint query changes") { _ = try await redirected(downloader(metadata: true), requests: [metadataQuery]) }
        for status in [206, 301, 304, 403, 429, 500] {
            await rejectedAsync("non-success response \(status)") { _ = try await injected(limit: 8, declaredSize: 0, chunks: [], status: status) }
        }
        require(try await injected(limit: 8, declaredSize: nil, chunks: [Data(repeating: 1, count: 8)]).count == 8,
                "Unknown content length is bounded by received bytes")
        await rejectedAsync("chunked response exceeds limit") {
            _ = try await injected(limit: 8, declaredSize: nil, chunks: [Data(repeating: 1, count: 9)])
        }
        await rejectedAsync("completion without an HTTP response") {
            _ = try await simulated(downloader()) { download, session, task in
                download.urlSession(session, task: task, didCompleteWithError: nil)
            }
        }
        for errorCode in [URLError.cancelled, URLError.timedOut, URLError.networkConnectionLost] {
            do {
                _ = try await simulated(downloader()) { download, session, task in
                    download.receivedResponse = true
                    download.urlSession(session, dataTask: task, didReceive: Data([1]))
                    download.urlSession(session, task: task, didCompleteWithError: URLError(errorCode))
                }
                fatalError("Partial response accepted after transport error")
            } catch let error as URLError {
                require(error.code == errorCode, "Transport cancellation/error is preserved")
            }
        }
        let completed = downloader()
        let result = try await simulated(completed) { download, session, task in
            download.receivedResponse = true
            download.urlSession(session, dataTask: task, didReceive: Data([1]))
            download.urlSession(session, task: task, didCompleteWithError: nil)
            download.urlSession(session, dataTask: task, didReceive: Data([2]))
            download.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
            download.finish(.failure(CancellationError()))
        }
        require(result == Data([1]) && completed.data == Data([1]), "Late data and completion cannot change a completed download")
        require(completed.continuation == nil && completed.session == nil, "Completed download releases continuation and session")
        let cancelled = downloader()
        let cancellation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cancelled.download()
        }
        do { _ = try await cancellation.value; fatalError("Cancelled task started a download") }
        catch is CancellationError { checks += 1 }
        require(cancelled.session == nil, "Pre-cancelled task creates no URLSession")
    }
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let archive = try Data(contentsOf: directory.appendingPathComponent("arm.gz"))
        let executable = try Data(contentsOf: directory.appendingPathComponent("arm.bin"))
        let x86 = try Data(contentsOf: directory.appendingPathComponent("x86.bin"))
        require(try TrustedAlphaRelease.decompress(archive) == executable, "Valid gzip round-trip")
        rejected("truncated gzip") { _ = try TrustedAlphaRelease.decompress(archive.dropLast(4)) }
        var corrupted = archive; corrupted[corrupted.count - 8] ^= 1
        rejected("bad gzip CRC") { _ = try TrustedAlphaRelease.decompress(corrupted) }
        rejected("gzip trailing payload") { _ = try TrustedAlphaRelease.decompress(archive + Data([0])) }
        rejected("concatenated gzip") { _ = try TrustedAlphaRelease.decompress(archive + archive) }
        rejected("decompression cap") { _ = try TrustedAlphaRelease.decompress(archive, limit: executable.count - 1) }
        try TrustedAlphaRelease.validateExecutable(executable, architecture: "arm64"); checks += 1
        try TrustedAlphaRelease.validateExecutable(x86, architecture: "amd64"); checks += 1
        rejected("wrong architecture") { try TrustedAlphaRelease.validateExecutable(executable, architecture: "amd64") }
        var library = executable; library[12] = 6
        rejected("dylib is not executable") { try TrustedAlphaRelease.validateExecutable(library, architecture: "arm64") }
        let name = "mihomo-darwin-arm64-alpha-abc1234.gz"
        let digest = TrustedAlphaRelease.sha256(archive)
        let checksums = Data((String(repeating: "0", count: 64) + "  " + name + ".bak\n" + digest.uppercased() + " *" + name + "\n").utf8)
        require(try TrustedAlphaRelease.checksum(checksums, fileName: name) == digest, "Exact checksum match")
        let officialChecksums = Data((digest + "  ./" + name + "\n").utf8)
        require(try TrustedAlphaRelease.checksum(officialChecksums, fileName: name) == digest, "Official find/sha256sum format")
        rejected("duplicate normalized checksum") { _ = try TrustedAlphaRelease.checksum(checksums + officialChecksums, fileName: name) }
        for prefix in ["../", "subdir/", "././"] {
            rejected("noncanonical checksum path: " + prefix) { _ = try TrustedAlphaRelease.checksum(Data((digest + "  " + prefix + name + "\n").utf8), fileName: name) }
        }
        rejected("duplicate checksum") { _ = try TrustedAlphaRelease.checksum(checksums + checksums, fileName: name) }
        rejected("missing exact checksum") { _ = try TrustedAlphaRelease.checksum(Data((digest + "  " + name + ".bak\n").utf8), fileName: name) }
        rejected("malformed SHA256") { _ = try TrustedAlphaRelease.checksum(Data(("xyz  " + name + "\n").utf8), fileName: name) }
        let source = "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/" + name
        try metadataEdges(archive: archive, name: name, digest: digest)
        let asset = TrustedAlphaRelease.Asset(id: 101, name: name, state: "uploaded", size: archive.count, browserDownloadURL: source, digest: "sha256:" + digest)
        let sumAsset = TrustedAlphaRelease.Asset(id: 102, name: "checksums.txt", state: "uploaded", size: checksums.count, browserDownloadURL: "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/checksums.txt", digest: nil)
        let release = TrustedAlphaRelease.Release(id: 100, tagName: "Prerelease-Alpha", draft: false, assets: [asset, sumAsset])
        let selected = try TrustedAlphaRelease.selectAssets(release, architecture: "arm64")
        require(selected.0.id == 101 && selected.1.id == 102 && selected.2 == "alpha-abc1234", "Correct platform/version selection")
        rejected("duplicate matching assets") { _ = try TrustedAlphaRelease.selectAssets(TrustedAlphaRelease.Release(id: 100, tagName: "Prerelease-Alpha", draft: false, assets: [asset, asset, sumAsset]), architecture: "arm64") }
        rejected("wrong release tag") { _ = try TrustedAlphaRelease.selectAssets(TrustedAlphaRelease.Release(id: 100, tagName: "stable", draft: false, assets: [asset, sumAsset]), architecture: "arm64") }
        try TrustedAlphaRelease.validateAssetData(archive, asset: asset); checks += 1
        rejected("metadata size mismatch") { try TrustedAlphaRelease.validateAssetData(archive + Data([0]), asset: asset) }
        rejected("metadata digest mismatch") { try TrustedAlphaRelease.validateAssetData(corrupted, asset: asset) }
        require(try TrustedAlphaRelease.assetURL(asset, limit: 1024).absoluteString == source, "Fixed official asset URL")
        let foreign = TrustedAlphaRelease.Asset(id: 101, name: name, state: "uploaded", size: archive.count, browserDownloadURL: "https://github.com/attacker/mihomo/releases/download/Prerelease-Alpha/" + name, digest: nil)
        rejected("other GitHub repository") { _ = try TrustedAlphaRelease.assetURL(foreign, limit: 1024) }
        let downloader = TrustedAlphaRelease.BoundedDownload(url: URL(string: source)!, limit: 1024, timeout: 1)
        require(downloader.permitted(URL(string: "https://release-assets.githubusercontent.com/release/file?token=fixture")!), "Known GitHub CDN")
        for bad in ["http://release-assets.githubusercontent.com/file", "https://evil.example/file", "https://github.com.evil.example/file", "https://user@release-assets.githubusercontent.com/file", "https://release-assets.githubusercontent.com:444/file", "https://release-assets.githubusercontent.com/file#fragment", "https://github.com/attacker/file"] {
            require(!downloader.permitted(URL(string: bad)!), "Reject unsafe redirect: " + bad)
        }
        require(try await injected(limit: 8, declaredSize: 8, chunks: [Data(repeating: 1, count: 4), Data(repeating: 2, count: 4)]).count == 8, "Bounded stream accepts exact limit")
        do { _ = try await injected(limit: 8, declaredSize: 9, chunks: []); fatalError("oversized header accepted") } catch { checks += 1 }
        do { _ = try await injected(limit: 8, declaredSize: 8, chunks: [Data(repeating: 1, count: 5), Data(repeating: 1, count: 5)]); fatalError("oversized stream accepted") } catch { checks += 1 }
        do { _ = try await injected(limit: 8, declaredSize: 0, chunks: [], status: 404); fatalError("HTTP error accepted") } catch { checks += 1 }
        let cancelled = TrustedAlphaRelease.BoundedDownload(url: URL(string: source)!, limit: 8, timeout: 1)
        cancelled.cancelled = true
        do { _ = try await cancelled.download(); fatalError("cancelled download started") } catch is CancellationError { checks += 1 }
        try await downloadEdges(source: source)
        for invalid in [Data(), Data([0x1f, 0x8b]), executable] {
            rejected("not a complete gzip archive") { _ = try TrustedAlphaRelease.decompress(invalid) }
        }
        require(try TrustedAlphaRelease.decompress(archive, limit: executable.count) == executable, "Exact decompression limit is accepted")
        for limit in [0, -1, TrustedAlphaRelease.executableLimit + 1] {
            rejected("invalid decompression limit") { _ = try TrustedAlphaRelease.decompress(archive, limit: limit) }
        }
        rejected("truncated Mach-O header") { try TrustedAlphaRelease.validateExecutable(executable.prefix(31), architecture: "arm64") }
        rejected("unsupported executable architecture") { try TrustedAlphaRelease.validateExecutable(executable, architecture: "riscv64") }
        var badMagic = executable; badMagic[0] = 0
        rejected("invalid Mach-O magic") { try TrustedAlphaRelease.validateExecutable(badMagic, architecture: "arm64") }
        let cancelledInflate = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TrustedAlphaRelease.decompress(archive)
        }
        do { _ = try await cancelledInflate.value; fatalError("Cancelled task decompressed an archive") }
        catch is CancellationError { checks += 1 }
        rejected("non-UTF8 checksums") { _ = try TrustedAlphaRelease.checksum(Data([0xff]), fileName: name) }
        rejected("oversized checksum file") {
            _ = try TrustedAlphaRelease.checksum(Data(repeating: 0, count: TrustedAlphaRelease.smallDownloadLimit + 1), fileName: name)
        }
        let tabbed = Data((digest + "\t*./" + name + "\r\n").utf8)
        require(try TrustedAlphaRelease.checksum(tabbed, fileName: name) == digest, "Binary checksum marker, canonical prefix and CRLF are accepted")
        print("PASS: \(checks) offline Alpha validation scenarios; no network or executable invocation")
    }
}
