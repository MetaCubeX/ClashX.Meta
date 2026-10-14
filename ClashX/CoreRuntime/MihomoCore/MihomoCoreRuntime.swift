import Foundation

/// Mihomo stays isolated from the legacy Go bridge. Activation is allowed only
/// after its packaged binary and privileged lifecycle have passed validation.
enum MihomoCoreRuntime {
    static let minimumSystemMajorVersion = 13
    static let version = "1.19.32"

    static var bundledExecutableURL: URL? {
        Bundle.main.url(forResource: "mihomo", withExtension: nil, subdirectory: "MihomoCore")
            ?? Bundle.main.url(forResource: "mihomo", withExtension: nil)
    }

    static var isPackaged: Bool {
        guard let url = bundledExecutableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    static func start(configPath: String, timeout: TimeInterval = 15) -> String? {
        guard let executable = bundledExecutableURL else { return "Mihomo executable is missing" }
        let effectivePath: String
        do {
            effectivePath = try MihomoConfigComposer.effectiveConfigPath(for: configPath)
        } catch {
            return error.localizedDescription
        }

        let port = Int.random(in: 49152...62000)
        let controller = "127.0.0.1:\(port)"
        let secret = UUID().uuidString
        let uiPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "dashboard")
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path } ?? ""
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: String?
        PrivilegedHelperManager.shared.helper(failture: {
            launchError = "Unable to connect to privileged helper"
            semaphore.signal()
        })?.startMihomo(atPath: executable.path,
                        configPath: effectivePath,
                        controller: controller,
                        secret: secret,
                        uiPath: uiPath) { error in
            launchError = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return "Timed out while starting Mihomo"
        }
        if let launchError = launchError, !launchError.isEmpty { return launchError }

        let deadline = Date().addingTimeInterval(timeout)
        let url = URL(string: "http://\(controller)/")!
        while Date() < deadline {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 1)
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            let probe = DispatchSemaphore(value: 0)
            var ready = false
            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let status = (response as? HTTPURLResponse)?.statusCode,
                   (200..<300).contains(status), let data = data,
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    ready = object["hello"] != nil
                }
                probe.signal()
            }.resume()
            _ = probe.wait(timeout: .now() + 1.2)
            if ready {
                let response = ["externalController": controller, "secret": secret]
                let responseData = try? JSONSerialization.data(withJSONObject: response)
                return responseData.flatMap { String(data: $0, encoding: .utf8) }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return "Mihomo controller did not become ready"
    }

    static func stop(timeout: TimeInterval = 5) {
        let semaphore = DispatchSemaphore(value: 0)
        guard let helper = PrivilegedHelperManager.shared.helper(failture: {
            semaphore.signal()
        }) else { return }
        helper.stopMihomo { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + timeout)
    }
}
