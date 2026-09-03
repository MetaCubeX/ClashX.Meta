//
//  MetaTask.swift
//  com.metacubex.ClashX.ProxyConfigHelper


import Cocoa
import Subprocess
import System
import Darwin

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

    private enum PrivilegedPathError: LocalizedError {
        case unsafeComponent(String)
        case notRegularFile(String)
        case md5Mismatch
        case ioFailed(String)

        var errorDescription: String? {
            switch self {
            case let .unsafeComponent(path):
                return "Refusing to use an unsafe (non root-owned, group/other-writable, or symlinked) path: \(path)"
            case let .notRegularFile(path):
                return "Refusing to use a path that is not a regular file: \(path)"
            case .md5Mismatch:
                return "Core binary integrity check (MD5) failed."
            case let .ioFailed(path):
                return "Failed to create or write a root-owned path: \(path)"
            }
        }
    }

    private static let coreFileName = "com.metacubex.ClashX.ProxyConfigHelper.meta"
    private static let managedRootDir = "/Library/Application Support/com.metacubex.ClashX.meta"
    private static var managedCoreDir: String { "\(managedRootDir)/Core" }
    private static var managedCorePath: String { "\(managedCoreDir)/\(coreFileName)" }
    private static var managedRunDir: String { "\(managedRootDir)/Run" }
    private static var managedRunConfigPath: String { "\(managedRunDir)/run_config.yaml" }
    private static let coreLogRootDir = "/Library/Logs/com.metacubex.ClashX.meta"

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
        let raw = serverResult?.sessionId ?? ""
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        let filtered = String(raw.filter { allowed.contains($0) })
        return filtered.isEmpty ? "session" : filtered
    }

    private func coreLogDir() -> String {
        "\(Self.coreLogRootDir)/\(safeSessionId())"
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
               confFilePath: String,
               confJSON: String,
               coreMD5: String) -> AsyncStream<String> {
        let state = StartState()

        return AsyncStream { continuation in
            continuation.onTermination = { @Sendable _ in }

            Task { [weak self] in
                do {
                    try await self?.startProcess(path,
                                                 confPath: confPath,
                                                 confFilePath: confFilePath,
                                                 confJSON: confJSON,
                                                 coreMD5: coreMD5,
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

        guard let data: Data = try? await run(
            .name("curl"),
            arguments: Arguments(args),
            output: .data(limit: 65536)
        ).standardOutput,
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
                              coreMD5: String,
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

        let corePath = try installManagedCore(source: path, expectedMD5: coreMD5)
        let safeConfFilePath = try installManagedConfig(source: confFilePath)
        try ensureSecureDirectory(Self.managedRunDir)
        try ensureSecureFile(stdoutLogPath())
        try ensureSecureFile(stderrLogPath())

        let logPath = stdoutLogPath()

        try writePlist(corePath: corePath, confPath: confPath, confFilePath: safeConfFilePath)

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

        let fm = FileManager.default
        try? fm.removeItem(atPath: Self.plistPath)
        fm.createFile(atPath: Self.plistPath, contents: data)
    }

    private func assertSafeRootPath(_ path: String, requireRegularFile: Bool) throws {
        guard path.hasPrefix("/") else { throw PrivilegedPathError.unsafeComponent(path) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.contains(".."), !parts.contains(".") else {
            throw PrivilegedPathError.unsafeComponent(path)
        }

        var current = ""
        for (index, part) in parts.enumerated() {
            current += "/" + part
            var st = stat()
            guard lstat(current, &st) == 0 else {
                throw PrivilegedPathError.unsafeComponent(current)
            }
            let mode = st.st_mode
            if (mode & S_IFMT) == S_IFLNK {
                throw PrivilegedPathError.unsafeComponent(current)
            }
            if st.st_uid != 0 {
                throw PrivilegedPathError.unsafeComponent(current)
            }
            if (mode & (S_IWGRP | S_IWOTH)) != 0 {
                throw PrivilegedPathError.unsafeComponent(current)
            }
            if index == parts.count - 1, requireRegularFile, (mode & S_IFMT) != S_IFREG {
                throw PrivilegedPathError.notRegularFile(current)
            }
        }
    }

    private func ensureSecureDirectory(_ path: String) throws {
        guard path.hasPrefix("/") else { throw PrivilegedPathError.unsafeComponent(path) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.contains(".."), !parts.contains(".") else {
            throw PrivilegedPathError.unsafeComponent(path)
        }

        var current = ""
        for part in parts {
            current += "/" + part
            var st = stat()
            if lstat(current, &st) == 0 {
                let mode = st.st_mode
                if (mode & S_IFMT) == S_IFLNK || (mode & S_IFMT) != S_IFDIR {
                    throw PrivilegedPathError.unsafeComponent(current)
                }
            } else {
                guard mkdir(current, mode_t(0o755)) == 0 else {
                    throw PrivilegedPathError.ioFailed(current)
                }
                _ = chown(current, 0, 0)
                _ = chmod(current, mode_t(0o755))
            }
        }
        try assertSafeRootPath(path, requireRegularFile: false)
    }

    private func writeSecureFile(_ data: Data, to path: String, mode: mode_t) throws {
        var st = stat()
        if lstat(path, &st) == 0 {
            unlink(path)
        }
        let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC | O_NOFOLLOW | O_EXCL, mode)
        guard fd >= 0 else { throw PrivilegedPathError.ioFailed(path) }

        var ok = true
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { ok = raw.count == 0; return }
            var total = 0
            while total < raw.count {
                let n = write(fd, base + total, raw.count - total)
                if n <= 0 { ok = false; break }
                total += n
            }
        }
        _ = fchown(fd, 0, 0)
        _ = fchmod(fd, mode)
        close(fd)

        guard ok else {
            unlink(path)
            throw PrivilegedPathError.ioFailed(path)
        }
    }

    private func ensureSecureFile(_ path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try ensureSecureDirectory(dir)

        var st = stat()
        if lstat(path, &st) == 0 {
            let mode = st.st_mode
            let unsafe = (mode & S_IFMT) != S_IFREG || st.st_uid != 0 || (mode & (S_IWGRP | S_IWOTH)) != 0
            if unsafe {
                unlink(path)
            } else {
                try assertSafeRootPath(path, requireRegularFile: true)
                return
            }
        }

        let fd = open(path, O_CREAT | O_WRONLY | O_NOFOLLOW | O_EXCL, mode_t(0o644))
        guard fd >= 0 else { throw PrivilegedPathError.ioFailed(path) }
        _ = fchown(fd, 0, 0)
        _ = fchmod(fd, mode_t(0o644))
        close(fd)

        try assertSafeRootPath(path, requireRegularFile: true)
    }

    private func installManagedCore(source: String, expectedMD5: String) throws -> String {
        let expected = expectedMD5.lowercased()
        try ensureSecureDirectory(Self.managedCoreDir)
        let dest = Self.managedCorePath

        if (try? assertSafeRootPath(dest, requireRegularFile: true)) != nil {
            if expected.isEmpty || Self.fileMD5(dest) == expected {
                return dest
            }
        }

        guard let data = FileManager.default.contents(atPath: source) else {
            throw PrivilegedPathError.ioFailed(source)
        }

        let tmp = "\(Self.managedCoreDir)/.\(UUID().uuidString).tmp"
        try writeSecureFile(data, to: tmp, mode: mode_t(0o755))

        if !expected.isEmpty {
            guard Self.fileMD5(tmp) == expected else {
                unlink(tmp)
                throw PrivilegedPathError.md5Mismatch
            }
        }

        guard rename(tmp, dest) == 0 else {
            unlink(tmp)
            throw PrivilegedPathError.ioFailed(dest)
        }

        try assertSafeRootPath(dest, requireRegularFile: true)
        return dest
    }

    private func installManagedConfig(source: String) throws -> String {
        guard !source.isEmpty else { return "" }
        guard let data = FileManager.default.contents(atPath: source) else {
            throw PrivilegedPathError.ioFailed(source)
        }
        try ensureSecureDirectory(Self.managedRunDir)
        let dest = Self.managedRunConfigPath
        try writeSecureFile(data, to: dest, mode: mode_t(0o644))
        try assertSafeRootPath(dest, requireRegularFile: true)
        return dest
    }

    private static func fileMD5(_ path: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/md5")
        proc.arguments = ["-q", path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
        } catch {
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
