import Darwin
import Foundation

final class SystemPathDiagnosticsProber: PathDiagnosticsProbing {
    private let queue = DispatchQueue(label: "com.clashx.path-diagnostics", qos: .utility)
    private let lock = NSLock()
    private var controllerConfig: [String: Any] = [:]

    func probe(_ stage: PathDiagnosticStage, completion: @escaping (PathProbeEvidence) -> Void) {
        switch stage {
        case .core: probeCore(completion)
        case .tun: probeTun(completion)
        case .dns: probeDNS(completion)
        case .node: probeNode(completion)
        case .internet: probeInternet(completion)
        }
    }

    private func probeCore(_ completion: @escaping (PathProbeEvidence) -> Void) {
        guard ConfigManager.shared.isRunning else {
            completion(evidence(.failed, "Core not running", "Clash core reports stopped."))
            return
        }
        guard let url = URL(string: ConfigManager.apiUrl + "/configs") else {
            completion(evidence(.failed, "Invalid controller URL", ConfigManager.apiUrl))
            return
        }

        let started = Date()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        let secret = ConfigManager.shared.overrideSecret ?? ConfigManager.shared.apiSecret
        if !secret.isEmpty { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let duration = Date().timeIntervalSince(started)
            if let error = error {
                completion(self?.evidence(.failed, "Controller unreachable", error.localizedDescription, duration) ??
                    PathProbeEvidence(status: .failed, summary: "Controller unreachable", detail: error.localizedDescription, duration: duration))
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(self?.evidence(.failed, "Controller rejected request", "HTTP \(code)", duration) ??
                    PathProbeEvidence(status: .failed, summary: "Controller rejected request", detail: "HTTP \(code)", duration: duration))
                return
            }
            self?.lock.lock()
            self?.controllerConfig = json
            self?.lock.unlock()
            completion(self?.evidence(.healthy, "Controller responding", "GET /configs returned HTTP \(http.statusCode).", duration) ??
                PathProbeEvidence(status: .healthy, summary: "Controller responding", detail: "HTTP \(http.statusCode)", duration: duration))
        }.resume()
    }

    private func probeTun(_ completion: @escaping (PathProbeEvidence) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let started = Date()
            self.lock.lock()
            let config = self.controllerConfig
            self.lock.unlock()
            let tun = config["tun"] as? [String: Any]
            let configured = tun?["enable"] as? Bool
            let interfaces = self.tunInterfaces()
            let routes = self.command("/usr/sbin/netstat", arguments: ["-rn", "-f", "inet"])
            let routedInterface = interfaces.first { routes.contains($0) }
            let duration = Date().timeIntervalSince(started)

            if configured == false {
                completion(self.evidence(.inactive, "TUN disabled", "Controller reports tun.enable=false.", duration))
            } else if let routedInterface = routedInterface {
                let source = configured == true ? "Controller enabled" : "Detected from routing table"
                completion(self.evidence(.healthy, routedInterface, "\(source); active route uses \(routedInterface).", duration))
            } else if configured == true {
                completion(self.evidence(.failed, "Route missing", "TUN is enabled, but no IPv4 route uses a utun interface. Interfaces: \(interfaces.joined(separator: ", ")).", duration))
            } else {
                completion(self.evidence(.inactive, "No TUN route", "Controller exposes no TUN state and no IPv4 route uses utun.", duration))
            }
        }
    }

    private func probeDNS(_ completion: @escaping (PathProbeEvidence) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let started = Date()
            guard let url = URL(string: ConfigManager.shared.benchMarkUrl), let host = url.host else {
                completion(self.evidence(.failed, "Invalid probe host", ConfigManager.shared.benchMarkUrl))
                return
            }
            var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                                 ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            let code = getaddrinfo(host, nil, &hints, &result)
            defer { if result != nil { freeaddrinfo(result) } }
            let duration = Date().timeIntervalSince(started)
            if code == 0 {
                completion(self.evidence(.healthy, host, "System resolver returned an address for \(host).", duration))
            } else {
                completion(self.evidence(.failed, "Resolution failed", String(cString: gai_strerror(code)), duration))
            }
        }
    }

    private func probeNode(_ completion: @escaping (PathProbeEvidence) -> Void) {
        ApiRequest.getMergedProxyData { proxyInfo in
            let groups = Set(proxyInfo?.proxyGroups.map { $0.name } ?? [])
            ApiRequest.getConnections { connections in
                let chains = connections.first(where: { !$0.chains.isEmpty })?.chains ?? []
                guard let node = PathDiagnosticsLogic.exitNode(from: chains, groupNames: groups) else {
                    completion(self.evidence(.inactive, "No active chain", "Generate traffic, then run diagnostics again."))
                    return
                }
                let started = Date()
                ApiRequest.getProxyDelay(proxyName: node) { delay in
                    let duration = Date().timeIntervalSince(started)
                    if delay > 0 {
                        completion(self.evidence(.healthy, node, "Observed chain: \(chains.joined(separator: " -> ")); delay \(delay) ms.", duration))
                    } else {
                        completion(self.evidence(.failed, node, "Observed chain: \(chains.joined(separator: " -> ")); delay probe failed.", duration))
                    }
                }
            }
        }
    }

    private func probeInternet(_ completion: @escaping (PathProbeEvidence) -> Void) {
        guard let url = URL(string: ConfigManager.shared.benchMarkUrl) else {
            completion(evidence(.failed, "Invalid probe URL", ConfigManager.shared.benchMarkUrl))
            return
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        let started = Date()
        session.dataTask(with: url) { [weak self] _, response, error in
            let duration = Date().timeIntervalSince(started)
            defer { session.finishTasksAndInvalidate() }
            if let error = error {
                completion(self?.evidence(.failed, "Request failed", error.localizedDescription, duration) ??
                    PathProbeEvidence(status: .failed, summary: "Request failed", detail: error.localizedDescription, duration: duration))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(self?.evidence(.failed, "No HTTP response", url.host ?? url.absoluteString, duration) ??
                    PathProbeEvidence(status: .failed, summary: "No HTTP response", detail: url.absoluteString, duration: duration))
                return
            }
            completion(self?.evidence(.healthy, "HTTP \(http.statusCode)", url.absoluteString, duration) ??
                PathProbeEvidence(status: .healthy, summary: "HTTP \(http.statusCode)", detail: url.absoluteString, duration: duration))
        }.resume()
    }

    private func evidence(_ status: PathDiagnosticStatus,
                          _ summary: String,
                          _ detail: String,
                          _ duration: TimeInterval? = nil) -> PathProbeEvidence {
        return PathProbeEvidence(status: status, summary: summary, detail: detail, duration: duration)
    }

    private func tunInterfaces() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var names = Set<String>()
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            let name = String(cString: item.pointee.ifa_name)
            if name.hasPrefix("utun") { names.insert(name) }
            current = item.pointee.ifa_next
        }
        return names.sorted()
    }

    private func command(_ launchPath: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.launchPath = launchPath
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return error.localizedDescription
        }
    }
}
