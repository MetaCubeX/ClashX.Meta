//
//  MetaTask.swift
//  com.metacubex.ClashX.ProxyConfigHelper


import Cocoa
import Subprocess
import System

private actor StartState {
    var finished = false
    var logs = [String]()

    func markFinished() -> Bool {
        guard !finished else { return false }
        finished = true
        return true
    }

    var isFinished: Bool { finished }

    func appendLogs(_ items: [String]) {
        logs.append(contentsOf: items)
    }

    func logsString() -> String {
        logs.joined(separator: "\n")
    }
}

class MetaTask: NSObject {
    private enum StartError: LocalizedError {
        case invalidConfig

        var errorDescription: String? {
            switch self {
            case .invalidConfig:
                return "Can't decode config file."
            }
        }
    }

    struct MetaCurl: Decodable {
        let hello: String
    }

    // MARK: - Properties

    private static let label = "com.metacubex.ClashX.ProxyConfigHelper.meta"
    private static let plistFileName = "com.metacubex.ClashX.ProxyConfigHelper.meta.plist"
    private static let plistDir = "/Library/LaunchDaemons"
    private static var plistPath: String { "\(plistDir)/\(plistFileName)" }

    private var serverResult: MetaServer?

    private func stdoutLogPath(_ confPath: String) -> String {
        "\(confPath)/logs/\(serverResult?.sessionId ?? "")/\(kCoreLogName)"
    }

    private func stderrLogPath(_ confPath: String) -> String {
        "\(confPath)/logs/\(serverResult?.sessionId ?? "")/\(kCoreCrashLogName)"
    }

    // MARK: - Public API

    func start(_ path: String,
               confPath: String,
               confFilePath: String,
               confJSON: String) -> AsyncStream<String> {
        let state = StartState()

        return AsyncStream { continuation in
            continuation.onTermination = { @Sendable _ in }

            Task { [weak self] in
                do {
                    try await self?.startProcess(path,
                                                 confPath: confPath,
                                                 confFilePath: confFilePath,
                                                 confJSON: confJSON,
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
        try? FileManager.default.removeItem(atPath: Self.plistPath)
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
            try? FileManager.default.removeItem(atPath: Self.plistPath)
        }
        _ = try? await run(.name("killall"), arguments: ["com.metacubex.ClashX.ProxyConfigHelper.meta"], output: .discarded)
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
        var args = [server.externalController]
        if server.secret != "" {
            args.append(contentsOf: [
                "--header",
                "Authorization: Bearer \(server.secret)"
            ])
        }

        // SubprocessFoundation DataOutput is not linked in this target; use string output.
        guard let output: String = try? await run(
            .name("curl"),
            arguments: Arguments(args),
            output: .string(limit: 65536)
        ).standardOutput,
              let data = output.data(using: .utf8),
              let str = try? JSONDecoder().decode(MetaCurl.self, from: data),
              (str.hello == "clash.meta" || str.hello == "mihomo") else {
            return false
        }
        return true
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
                              confFilePath: String,
                              confJSON: String,
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

        let logPath = stdoutLogPath(confPath)

        try writePlist(path: path, confPath: confPath, confFilePath: confFilePath)

        _ = try? await run(.name("launchctl"), arguments: ["unload", Self.plistPath], output: .discarded)
        do {
            _ = try await run(.name("launchctl"), arguments: ["load", Self.plistPath], output: .discarded)
            _ = try await run(.name("launchctl"), arguments: ["start", Self.label], output: .discarded)
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
            continuation.yield(encodeServerResult(with: logs))
            continuation.finish()
        }

        _ = await logReaderTask.value
        _ = await pollingTask.value
        _ = await timeoutTask.value
    }

    private func writePlist(path: String, confPath: String, confFilePath: String) throws {
        guard let serverResult else { return }
        var programArguments = [path, "-d", confPath]
        if !confFilePath.isEmpty {
            programArguments.append(contentsOf: ["-f", confFilePath])
        }

        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": programArguments,
            "WorkingDirectory": confPath,
            "EnvironmentVariables": ["SAFE_PATHS": serverResult.safePaths],
            "StandardOutPath": stdoutLogPath(confPath),
            "StandardErrorPath": stderrLogPath(confPath),
            "KeepAlive": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let fm = FileManager.default
        try? fm.removeItem(atPath: Self.plistPath)
        fm.createFile(atPath: Self.plistPath, contents: data)
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
