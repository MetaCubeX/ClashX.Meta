//
//  MetaTask.swift
//  com.metacubex.ClashX.ProxyConfigHelper


import Cocoa
import Subprocess
import System
import Darwin

private actor StartState {
    var finished = false
    private var logs = ""

    func markFinished() -> Bool {
        guard !finished else { return false }
        finished = true
        return true
    }

    var isFinished: Bool { finished }

    func appendLogs(_ items: [String]) {
        logs += items.joined(separator: "\n") + "\n"
        if logs.count > 65_536 { logs = String(logs.suffix(65_536)) }
    }

    func logsString() -> String {
        logs
    }
}

class MetaTask: NSObject {
    private enum StartError: LocalizedError {
        case invalidConfig
        case launchFailed

        var errorDescription: String? {
            switch self {
            case .invalidConfig:
                return "Can't decode config file."
            case .launchFailed:
                return "launchd could not load or start the verified core."
            }
        }
    }

    private static let managedRunDir = TrustedCoreStore.runDirectory
    private let logMaintenance = CoreLogMaintenance()

    struct MetaCurl: Decodable {
        let hello: String
    }

    // MARK: - Properties

    private static let label = "com.metacubex.ClashX.ProxyConfigHelper.meta"
    private static let plistFileName = "com.metacubex.ClashX.ProxyConfigHelper.meta.plist"
    private static let plistDir = "/Library/LaunchDaemons"
    private static var plistPath: String { "\(plistDir)/\(plistFileName)" }

    private var serverResult: MetaServer?

    private func safeSessionId() -> String {
        serverResult?.sessionId ?? ""
    }

    private func coreLogDir() -> String {
        "\(CoreLogMaintenance.rootDirectory)/\(safeSessionId())"
    }

    private func stdoutLogPath() -> String {
        "\(coreLogDir())/\(kCoreLogName)"
    }

    private func stderrLogPath() -> String {
        "\(coreLogDir())/\(kCoreCrashLogName)"
    }

    // MARK: - Public API

    func start(_ path: String,
               confPath: String,
               configData: Data,
               confJSON: String,
               core: ProxyConfigHelperCore) -> AsyncStream<String> {
        let state = StartState()

        return AsyncStream { continuation in
            continuation.onTermination = { @Sendable _ in }

            Task { [weak self] in
                do {
                    try await self?.startProcess(path,
                                                 confPath: confPath,
                                                 configData: configData,
                                                 confJSON: confJSON,
                                                 core: core,
                                                 state: state,
                                                 continuation: continuation)
                } catch let error as StartError {
                    guard await state.markFinished() else { return }
                    continuation.yield(error.localizedDescription)
                    continuation.finish()
                } catch {
                    guard await state.markFinished() else { return }
                    continuation.yield("Start meta error, \(error.localizedDescription).")
                    continuation.finish()
                }
            }
        }
    }

    func stop() async {
        _ = try? await run(.name("launchctl"), arguments: ["stop", Self.label], output: .discarded)
        _ = try? await run(.name("launchctl"), arguments: ["unload", Self.plistPath], output: .discarded)
        logMaintenance.stop()
        try? PrivilegedDirectory.open(Self.plistDir).remove(Self.plistFileName)
    }

    @discardableResult
    func terminateExistingMeta() async -> Bool {
        let listOutput = (try? await run(
            .name("launchctl"),
            arguments: ["list"],
            output: .string(limit: 65536)
        ).standardOutput) ?? ""

        let isLoaded = listOutput.contains(Self.label)
        if isLoaded {
            _ = try? await run(.name("launchctl"), arguments: ["stop", Self.label], output: .discarded)
            _ = try? await run(.name("launchctl"), arguments: ["unload", Self.plistPath], output: .discarded)
            try? PrivilegedDirectory.open(Self.plistDir).remove(Self.plistFileName)
        }
        _ = try? await run(.name("killall"), arguments: ["com.metacubex.ClashX.ProxyConfigHelper.meta"], output: .discarded)
        logMaintenance.stop()
        return isLoaded
    }

    // MARK: - Utility

    func getUsedPorts() async -> String? {
        guard let output: String = try? await run(
            .name("bash"),
            arguments: ["-c", "lsof -nP -iTCP -sTCP:LISTEN | grep LISTEN"],
            output: .string(limit: 65536)
        ).standardOutput, !output.isEmpty else {
            return ""
        }

        return output.split(separator: "\n").compactMap { str -> Int? in
            let line = str.split(separator: " ").map(String.init)
            guard line.count == 10,
            let port = line[8].components(separatedBy: ":").last else { return nil }
            return Int(port)
        }.map(String.init).joined(separator: ",")
    }

    func testExternalController(_ server: MetaServer) async -> Bool {
        guard let address = URLComponents(string: "http://" + server.externalController),
              address.scheme == "http", address.host == "127.0.0.1",
              let port = address.port, (1...65535).contains(port),
              address.user == nil, address.password == nil,
              address.path.isEmpty, address.query == nil, address.fragment == nil,
              let url = address.url, server.secret.utf8.count <= 4096,
              !server.secret.contains("\r"), !server.secret.contains("\n") else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        if !server.secret.isEmpty { request.setValue("Bearer " + server.secret, forHTTPHeaderField: "Authorization") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4096 else { return false }
                data.append(byte)
            }
            let result = try JSONDecoder().decode(MetaCurl.self, from: data)
            return result.hello == "clash.meta" || result.hello == "mihomo"
        } catch { return false }
    }

    func formatMsg(_ msg: String) -> String {
        let msgs = msg.split(separator: " ", maxSplits: 2).map(String.init)

        guard msgs.count == 3,
              msgs[1].starts(with: "level"),
              msgs[2].starts(with: "msg") else {
            return msg
        }

        let level = msgs[1].replacingOccurrences(of: "level=", with: "")
        var re = msgs[2].replacingOccurrences(of: "msg=\"", with: "")

        while re.last == "\"" || re.last == "\n" {
            re.removeLast()
        }

        if re.contains("time=") {
            print(re)
        }

        return "[\(level)] \(re)"
    }

    // MARK: - Private

    private func startProcess(_ path: String,
                              confPath: String,
                              configData: Data,
                              confJSON: String,
                              core: ProxyConfigHelperCore,
                              state: StartState,
                              continuation: AsyncStream<String>.Continuation) async throws {

        guard let confData = confJSON.data(using: .utf8),
              let result = try? JSONDecoder().decode(MetaServer.self, from: confData) else {
            throw StartError.invalidConfig
        }
        serverResult = result

        func encodeServerResult(with logs: String) -> String {
            var result = serverResult!
            result.log = logs
            return result.jsonString()
        }

        guard confPath.hasPrefix("/"), !confPath.utf8.contains(0), confPath.utf8.count <= 4096 else {
            throw PrivilegedFileError.unsafePath(confPath)
        }
        let sessionDirectory = try CoreLogMaintenance.sessionDirectory(sessionID: result.sessionId)
        let corePath: String
        switch core {
        case .bundled: corePath = try TrustedCoreStore.bundled(source: path)
        case .alpha: corePath = try TrustedCoreStore.alpha().path
        }
        let safeConfFilePath = try TrustedCoreStore.writeConfig(configData)
        let logDirectory = try PrivilegedDirectory.open(sessionDirectory, create: true)
        try logDirectory.ensureLog(kCoreLogName)
        try logDirectory.ensureLog(kCoreCrashLogName)
        try logMaintenance.start(sessionID: result.sessionId)

        let logPath = stdoutLogPath()

        try writePlist(corePath: corePath, confPath: confPath, confFilePath: safeConfFilePath)

        _ = try? await run(.name("launchctl"), arguments: ["unload", Self.plistPath], output: .discarded)
        do {
            let loaded = try await run(.path("/bin/launchctl"), arguments: ["load", Self.plistPath], output: .discarded)
            guard loaded.terminationStatus.isSuccess else { throw StartError.launchFailed }
            let started = try await run(.path("/bin/launchctl"), arguments: ["start", Self.label], output: .discarded)
            guard started.terminationStatus.isSuccess else { throw StartError.launchFailed }
        } catch {
            guard await state.markFinished() else { return }
            continuation.yield("Start meta error: \(error.localizedDescription).")
            continuation.finish()
            return
        }

        let logReaderTask = Task { [weak self] in
            guard let self else { return }
            var offset: UInt64 = 0

            while !Task.isCancelled {
                try? await Task.sleep(seconds: 0.2)
                guard !Task.isCancelled else { return }
                guard await !state.isFinished else { return }

                let (newLines, newOffset) = self.readNewLines(from: logPath, offset: offset)
                offset = newOffset

                guard !newLines.isEmpty else { continue }
                let messages = newLines.map(self.formatMsg)
                await state.appendLogs(messages)

                for message in messages {
                    if message.contains("External controller listen error:") || message.contains("External controller serve error:") {
                        guard await state.markFinished() else { return }
                        continuation.yield(message)
                        continuation.finish()
                        return
                    }

                    if message.contains("RESTful API listening at:") {
                        let controllerReady = await self.testExternalController(self.serverResult!)
                        if controllerReady {
                            let logs = await state.logsString()
                            guard await state.markFinished() else { return }
                            continuation.yield(encodeServerResult(with: logs))
                            continuation.finish()
                            return
                        }
                    }
                }
            }
        }

        let pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(seconds: 0.5)
                guard !Task.isCancelled else { return }
                guard await !state.isFinished else { return }
                guard await self.testExternalController(self.serverResult!) else { continue }

                let logs = await state.logsString()
                guard await state.markFinished() else { return }
                continuation.yield(encodeServerResult(with: logs))
                continuation.finish()
                return
            }
        }

        let timeoutTask = Task {
            try? await Task.sleep(seconds: 30)
            guard await state.markFinished() else { return }
            let logs = await state.logsString()
            continuation.yield("The core did not become ready within 30 seconds.\n" + logs)
            continuation.finish()
        }

        _ = await logReaderTask.value
        _ = await pollingTask.value
        _ = await timeoutTask.value
    }

    private func writePlist(corePath: String, confPath: String, confFilePath: String) throws {
        guard let serverResult else { return }
        var programArguments = [corePath, "-d", confPath]
        if !confFilePath.isEmpty {
            programArguments.append(contentsOf: ["-f", confFilePath])
        }

        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": programArguments,
            "WorkingDirectory": Self.managedRunDir,
            "EnvironmentVariables": ["SAFE_PATHS": serverResult.safePaths],
            "StandardOutPath": stdoutLogPath(),
            "StandardErrorPath": stderrLogPath(),
            "KeepAlive": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let directory = try PrivilegedDirectory.open(Self.plistDir)
        try directory.write(data, name: Self.plistFileName, mode: 0o644)
    }

    private func readNewLines(from path: String, offset: UInt64) -> (lines: [String], newOffset: UInt64) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return ([], offset) }
        defer { handle.closeFile() }

        let fileEnd = handle.seekToEndOfFile()

        if offset > fileEnd {
            handle.seek(toFileOffset: 0)
            let data = handle.availableData
            let content = String(data: data, encoding: .utf8) ?? ""
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return (lines, UInt64(data.count))
        }

        guard offset < fileEnd else { return ([], offset) }

        handle.seek(toFileOffset: offset)
        let data = handle.availableData
        let newOffset = offset + UInt64(data.count)
        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return (lines, newOffset)
    }
}
