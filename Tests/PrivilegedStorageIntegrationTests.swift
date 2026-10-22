import Darwin
import Foundation

// The runner supplies a fresh /private/tmp directory. Production builds keep the
// real root policy; STORAGE_ISOLATED uses disposable source copies with only the
// owner and root-path expectations changed to this unprivileged fixture.
let storageFixtureRoot = CommandLine.arguments.dropFirst().first ?? ""
let kCoreLogName = "clashx_mihomo.log"
let kCoreCrashLogName = "clashx_mihomo_error.log"
private let bundledBytes = Data("trusted bundled executable fixture".utf8)
enum BundledCoreTrust { static let sha256 = PrivilegedDirectory.sha256(bundledBytes) }
struct TrustedAlphaPayload {
    let data: Data
    let version: String
    let assetID: Int
    let releaseID: Int
    let archiveSHA256: String
    let executableSHA256: String
}

private enum TestFailure: Error { case assertion(String) }
private func expect(_ value: Bool, _ message: String) throws {
    guard value else { throw TestFailure.assertion(message) }
}
private func expectFailure(_ message: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw TestFailure.assertion(message)
}
private func contents(_ path: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: path)) }
private func writeFixture(_ data: Data, _ path: String) throws { try data.write(to: URL(fileURLWithPath: path)) }
private func metadata(_ fd: Int32) throws -> stat {
    var info = stat()
    try expect(fstat(fd, &info) == 0, "fstat failed")
    return info
}

@main
private enum StorageIntegrationTests {
    static func main() {
        do {
            try expect(geteuid() != 0, "Run these tests as an unprivileged user, never root")
            try expect(storageFixtureRoot.hasPrefix("/private/tmp/") && !storageFixtureRoot.contains(".."),
                       "The fixture must be inside /private/tmp")
            try FileManager.default.createDirectory(atPath: storageFixtureRoot, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(atPath: storageFixtureRoot) }
            #if STORAGE_ISOLATED
            try testStorage()
            try testAlphaPublication()
            try testLogs()
            #else
            try testProductionPolicy()
            #endif
        } catch {
            fputs("Storage test failure: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testProductionPolicy() throws {
        _ = try PrivilegedDirectory.open("/")
        let file = storageFixtureRoot + "/untrusted"
        try writeFixture(Data("unprivileged source".utf8), file)
        let fd = open(file, O_RDONLY | O_NOFOLLOW)
        try expect(fd >= 0, "Cannot open ownership fixture")
        defer { close(fd) }
        try expectFailure("Production policy accepted a non-root file") {
            try PrivilegedDirectory.validate(fd, directory: false, path: file)
        }
        try expectFailure("Production policy accepted a non-root directory") {
            _ = try PrivilegedDirectory.open(storageFixtureRoot)
        }
        try expect(try PrivilegedDirectory.readSource(file, limit: 64) == Data("unprivileged source".utf8),
                   "Reading untrusted input should remain separate from trusting a stored executable")
        print("PASS: unchanged production sources compile; root path validation is read-only; non-root stored paths rejected")
    }

    #if STORAGE_ISOLATED
    private static func setACL(_ fd: Int32, permission: acl_perm_t, inherited: Bool = false) throws {
        var acl: acl_t? = acl_init(1)
        try expect(acl != nil, "Cannot allocate ACL")
        defer { acl_free(UnsafeMutableRawPointer(acl!)) }
        var entry: acl_entry_t?
        try expect(acl_create_entry(&acl, &entry) == 0, "Cannot create ACL entry")
        var qualifier = UUID().uuid
        try expect(acl_set_tag_type(entry!, ACL_EXTENDED_ALLOW) == 0, "Cannot set ACL type")
        try expect(acl_set_qualifier(entry!, &qualifier) == 0, "Cannot set ACL identity")
        var permissions: acl_permset_t?
        try expect(acl_get_permset(entry!, &permissions) == 0, "Cannot read ACL permissions")
        try expect(acl_add_perm(permissions!, permission) == 0, "Cannot add ACL permission")
        if inherited {
            try expect(acl_add_perm(permissions!, ACL_SEARCH) == 0, "Cannot add directory search permission")
            var flags: acl_flagset_t?
            try expect(acl_get_flagset_np(UnsafeMutableRawPointer(entry!), &flags) == 0, "Cannot read ACL flags")
            try expect(acl_add_flag_np(flags!, ACL_ENTRY_FILE_INHERIT) == 0, "Cannot inherit ACL to files")
            try expect(acl_add_flag_np(flags!, ACL_ENTRY_DIRECTORY_INHERIT) == 0, "Cannot inherit ACL to directories")
        }
        try expect(acl_set_fd_np(fd, acl!, ACL_TYPE_EXTENDED) == 0, "Cannot set fixture ACL")
    }

    private static func clearACL(_ fd: Int32) throws {
        let acl = acl_init(0)!
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        try expect(acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED) == 0, "Cannot clear fixture ACL")
    }

    private static func hasACL(_ fd: Int32) throws -> Bool {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            try expect(errno == ENOENT, "Unexpected ACL read failure")
            return false
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        return acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry) == 0
    }

    private static func testStorage() throws {
        let source = storageFixtureRoot + "/source"
        try writeFixture(bundledBytes, source)
        let bundledPath = try TrustedCoreStore.bundled(source: source)
        let core = try PrivilegedDirectory.open(TrustedCoreStore.coreDirectory)
        try expect(try contents(bundledPath) == bundledBytes, "Trusted bundled bytes were not published")
        for digest in [BundledCoreTrust.sha256, "invalid", String(repeating: "A", count: 64)] {
            try expectFailure("Wrong or malformed digest was published") {
                try core.write(Data("wrong bytes".utf8), name: TrustedCoreStore.coreName, mode: 0o755,
                               expectedSHA256: digest)
            }
            try expect(try contents(bundledPath) == bundledBytes, "Failed digest check changed existing cache")
        }
        try expect(!(try FileManager.default.contentsOfDirectory(atPath: core.path)).contains { $0.hasSuffix(".tmp") },
                   "Failed digest check left staging files")
        try writeFixture(Data("corrupted cache".utf8), bundledPath)
        try writeFixture(Data("corrupted input".utf8), source)
        try expectFailure("Tampered bundled cache was reused") { _ = try TrustedCoreStore.bundled(source: source) }
        try writeFixture(bundledBytes, source)
        _ = try TrustedCoreStore.bundled(source: source)
        try expect(try contents(bundledPath) == bundledBytes, "Trusted source did not repair corrupt cache")
        try expectFailure("Oversized source was read") { _ = try PrivilegedDirectory.readSource(source, limit: 1) }
        for name in ["", ".", "..", "a/b", "a\0b"] {
            try expectFailure("Unsafe leaf name accepted: \(name)") { try core.write(Data(), name: name, mode: 0o600) }
        }
        try expectFailure("Directory traversal accepted") { _ = try PrivilegedDirectory.open(core.path + "/../escape", create: true) }
        try core.write(Data("protected target".utf8), name: "probe", mode: 0o600)
        try expect(symlinkat("probe", core.descriptor, "linked") == 0, "Cannot create symlink fixture")
        try expectFailure("Stored symlink was read") { _ = try core.read("linked", limit: 128) }
        try expect(linkat(core.descriptor, "probe", core.descriptor, "hardlink", 0) == 0, "Cannot create hardlink fixture")
        try expectFailure("Stored hardlink was read") { _ = try core.read("hardlink", limit: 128) }
        try core.remove("hardlink")
        let probe = openat(core.descriptor, "probe", O_RDWR | O_NOFOLLOW)
        try expect(probe >= 0, "Cannot open permission fixture")
        defer { close(probe) }
        try expect(fchmod(probe, 0o622) == 0, "Cannot set unsafe mode")
        try expectFailure("Writable mode was accepted") { _ = try core.read("probe", limit: 128) }
        try expect(fchmod(probe, 0o600) == 0, "Cannot restore fixture mode")
        try setACL(probe, permission: ACL_WRITE_DATA)
        try expectFailure("Write ACL was accepted") { _ = try core.read("probe", limit: 128) }
        try clearACL(probe)
        try core.write(Data("new leaf".utf8), name: "linked", mode: 0o600)
        try expect(try core.read("probe", limit: 128) == Data("protected target".utf8), "Publication followed a symlink")

        try expectFailure("Empty configuration was accepted") { _ = try TrustedCoreStore.writeConfig(Data()) }
        let maximumConfig = Data(repeating: 0x61, count: 4 * 1024 * 1024)
        let maximumConfigPath = try TrustedCoreStore.writeConfig(maximumConfig)
        try expect(try contents(maximumConfigPath) == maximumConfig, "Exact 4 MiB configuration was not preserved")
        try expectFailure("Configuration above 4 MiB was accepted") {
            _ = try TrustedCoreStore.writeConfig(Data(repeating: 0x62, count: maximumConfig.count + 1))
        }
        try expect(try contents(maximumConfigPath) == maximumConfig, "Rejected oversized config changed the active file")
        let configPath = try TrustedCoreStore.writeConfig(Data("secret: fixture".utf8))
        let run = try PrivilegedDirectory.open(TrustedCoreStore.runDirectory)
        try setACL(run.descriptor, permission: ACL_READ_DATA, inherited: true)
        _ = try TrustedCoreStore.writeConfig(Data("secret: second-fixture".utf8))
        let config = open(configPath, O_RDONLY | O_NOFOLLOW)
        try expect(config >= 0, "Cannot open private config fixture")
        defer { close(config) }
        try expect(try metadata(config).st_mode & 0o777 == 0o600, "Config mode is not 600")
        try expect(try metadata(run.descriptor).st_mode & 0o777 == 0o700, "Run mode is not 700")
        try expect(try !hasACL(config) && !hasACL(run.descriptor), "Private config or Run retained inherited read/search ACL")
        try setACL(core.descriptor, permission: ACL_READ_DATA, inherited: true)
        try core.write(Data("private fixture".utf8), name: "private-file", mode: 0o600)
        let privateFile = openat(core.descriptor, "private-file", O_RDONLY | O_NOFOLLOW)
        try expect(privateFile >= 0, "Cannot open private file fixture")
        defer { close(privateFile) }
        try expect(try !hasACL(privateFile), "New private file retained a public parent's inherited read ACL")
        try clearACL(core.descriptor)
        print("PASS: digest publication, cache revalidation, size/name boundaries, links, modes, writable ACLs and inherited read ACL removal")
    }

    private static func alphaPayload(_ version: Int) -> TrustedAlphaPayload {
        let bytes = Data("trusted alpha executable fixture \(version)".utf8)
        return TrustedAlphaPayload(data: bytes, version: "alpha-\(version)", assetID: version, releaseID: version,
                                   archiveSHA256: String(repeating: "a", count: 64),
                                   executableSHA256: PrivilegedDirectory.sha256(bytes))
    }

    private static func testAlphaPublication() throws {
        let first = alphaPayload(1)
        let second = alphaPayload(2)
        let third = alphaPayload(3)
        _ = try TrustedCoreStore.installAlpha(first)
        let originalPath = try TrustedCoreStore.alpha().path
        let alpha = try PrivilegedDirectory.open(TrustedCoreStore.alphaDirectory)
        let originalReceipt = try alpha.read("receipt.json", limit: 16 * 1024)
        do {
            try expect(renameat(alpha.descriptor, first.executableSHA256, alpha.descriptor, "version-backup") == 0,
                       "Cannot prepare version directory symlink fixture")
            defer {
                unlinkat(alpha.descriptor, first.executableSHA256, 0)
                renameat(alpha.descriptor, "version-backup", alpha.descriptor, first.executableSHA256)
            }
            try expect(symlinkat("version-backup", alpha.descriptor, first.executableSHA256) == 0,
                       "Cannot create version directory symlink")
            try expectFailure("Symlinked Alpha hash directory was accepted") { _ = try TrustedCoreStore.alpha() }
        }
        do {
            let version = try PrivilegedDirectory.open(TrustedCoreStore.alphaDirectory + "/" + first.executableSHA256)
            try expect(linkat(version.descriptor, TrustedCoreStore.coreName, version.descriptor, "hardlink", 0) == 0,
                       "Cannot create Alpha executable hardlink")
            defer { unlinkat(version.descriptor, "hardlink", 0) }
            try expectFailure("Hardlinked Alpha executable was accepted") { _ = try TrustedCoreStore.alpha() }
        }
        try writeFixture(Data("corrupted alpha bytes".utf8), originalPath)
        try expectFailure("Tampered Alpha cache was reused") { _ = try TrustedCoreStore.alpha() }
        _ = try TrustedCoreStore.installAlpha(first)
        try alpha.write(Data("invalid JSON".utf8), name: "receipt.json", mode: 0o644)
        try expectFailure("Malformed receipt was accepted") { _ = try TrustedCoreStore.alpha() }
        try alpha.write(originalReceipt, name: "receipt.json", mode: 0o644)
        let invalid = TrustedAlphaPayload(data: Data("bad input".utf8), version: "bad", assetID: 9, releaseID: 9,
                                          archiveSHA256: first.archiveSHA256, executableSHA256: first.executableSHA256)
        try expectFailure("Invalid Alpha payload was published") { _ = try TrustedCoreStore.installAlpha(invalid) }
        _ = try TrustedCoreStore.alpha()

        // An immutable receipt makes the actual rename fail after the new binary
        // has been persisted. No simulated success or mocked write is involved.
        let receiptFD = openat(alpha.descriptor, "receipt.json", O_RDONLY | O_NOFOLLOW)
        try expect(receiptFD >= 0, "Cannot open receipt failure fixture")
        defer { close(receiptFD) }
        try expect(fchflags(receiptFD, UInt32(UF_IMMUTABLE)) == 0, "Cannot make receipt publication fail")
        do {
            defer { fchflags(receiptFD, 0) }
            try expectFailure("Immutable receipt unexpectedly published") { _ = try TrustedCoreStore.installAlpha(second) }
            let current = try TrustedCoreStore.alpha()
            try expect(current.receipt.executableSHA256 == first.executableSHA256, "Failed update changed active receipt")
            try expect(try contents(current.path) == first.data, "Failed update damaged the old executable")
            try expect(try alpha.read("receipt.json", limit: 16 * 1024) == originalReceipt, "Failed update changed receipt bytes")
            let staged = try PrivilegedDirectory.open(TrustedCoreStore.alphaDirectory + "/" + second.executableSHA256)
            try expect(try staged.read(TrustedCoreStore.coreName, limit: 4096) == second.data, "Receipt failure occurred before binary publication")
        }
        _ = try TrustedCoreStore.installAlpha(second)
        try expect(try contents(originalPath) == first.data, "Previous Alpha was not retained")
        _ = try TrustedCoreStore.installAlpha(second)
        try expect(try contents(originalPath) == first.data, "Reinstalling current Alpha deleted the previous version")
        _ = try TrustedCoreStore.installAlpha(third)
        let retained = try FileManager.default.contentsOfDirectory(atPath: TrustedCoreStore.alphaDirectory).filter(PrivilegedDirectory.isSHA256)
        try expect(Set(retained) == Set([second.executableSHA256, third.executableSHA256]), "Alpha did not retain current and previous versions")
        try expect(try TrustedCoreStore.alpha().path.contains(third.executableSHA256), "Active Alpha path does not identify its content hash")
        print("PASS: Alpha cache/receipt rejection, failed receipt rollback, idempotent reinstall and two-version retention")
    }

    private static func testLogs() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: CoreLogMaintenance.rootDirectory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        let root = try PrivilegedDirectory.open(CoreLogMaintenance.rootDirectory)
        for value in ["", ".", "..", "a/b", "a\\b", "ä", "a\0b", String(repeating: "a", count: 65)] {
            try expectFailure("Unsafe session identifier accepted") { _ = try CoreLogMaintenance.sessionDirectory(sessionID: value) }
        }
        _ = try CoreLogMaintenance.sessionDirectory(sessionID: String(repeating: "a", count: 64))
        let session = try PrivilegedDirectory.open(CoreLogMaintenance.rootDirectory + "/active", create: true)
        var writers: [Int32] = []
        defer { writers.forEach { close($0) } }
        for name in [kCoreLogName, kCoreCrashLogName] {
            try session.ensureLog(name)
            let writer = openat(session.descriptor, name, O_WRONLY | O_APPEND | O_NOFOLLOW)
            try expect(writer >= 0, "Cannot open persistent log writer")
            writers.append(writer)
            try expect(ftruncate(writer, 6 * 1024 * 1024) == 0, "Cannot grow log fixture")
        }
        for index in 0..<24 {
            let old = try PrivilegedDirectory.open(CoreLogMaintenance.rootDirectory + "/session-\(index)", create: true)
            try old.ensureLog(kCoreLogName)
            try old.ensureLog(kCoreCrashLogName)
        }
        let maintenance = CoreLogMaintenance()
        defer { maintenance.stop() }
        try maintenance.start(sessionID: "active")
        for writer in writers {
            try expect(try metadata(writer).st_size == 0, "Startup maintenance did not truncate the writer's existing inode")
            let line = Array("after-truncate\n".utf8)
            try expect(line.withUnsafeBytes { write(writer, $0.baseAddress!, $0.count) } == line.count, "Held writer could not append")
            try expect(try metadata(writer).st_size == line.count, "Held writer produced a sparse hole after truncation")
        }
        let retained = try fm.contentsOfDirectory(atPath: CoreLogMaintenance.rootDirectory)
        try expect(retained.count == 20 && retained.contains("active"), "Log retention did not keep 20 sessions including current")
        try maintenance.queue.sync {
            for index in maintenance.logFiles.indices {
                maintenance.logFiles[index].clearedAt = DispatchTime.now().uptimeNanoseconds - CoreLogMaintenance.clearInterval
            }
            try maintenance.maintainLocked()
        }
        for writer in writers {
            try expect(try metadata(writer).st_size == 0, "Five-minute maintenance missed a log stream")
            try expect(ftruncate(writer, CoreLogMaintenance.maximumLogSize) == 0, "Cannot test exact size boundary")
        }
        try maintenance.queue.sync { try maintenance.maintainLocked() }
        for writer in writers {
            try expect(try metadata(writer).st_size == CoreLogMaintenance.maximumLogSize, "Log cleared before exceeding size threshold")
            try expect(ftruncate(writer, CoreLogMaintenance.maximumLogSize + 1) == 0, "Cannot cross size threshold")
        }
        // Exercise the actual repeating timer. There is no launchd job or core process.
        let deadline = Date().addingTimeInterval(8)
        while try Date() < deadline && writers.contains(where: { try metadata($0).st_size != 0 }) {
            Thread.sleep(forTimeInterval: 0.025)
        }
        for writer in writers { try expect(try metadata(writer).st_size == 0, "Actual maintenance timer did not limit the log") }

        let target = storageFixtureRoot + "/outside-log-target"
        try writeFixture(Data("unchanged".utf8), target)
        try expect(symlinkat(target, session.descriptor, "linked-log") == 0, "Cannot create log symlink")
        try expectFailure("Log symlink accepted") { _ = try CoreLogMaintenance.openLog(at: session.descriptor, name: "linked-log") }
        try expect(linkat(session.descriptor, kCoreLogName, session.descriptor, "hardlink", 0) == 0, "Cannot create log hardlink")
        try expectFailure("Log hardlink accepted") { _ = try CoreLogMaintenance.openLog(at: session.descriptor, name: kCoreLogName) }
        try session.remove("hardlink")
        try setACL(writers[0], permission: ACL_WRITE_DATA)
        try expectFailure("Log write ACL accepted") { _ = try CoreLogMaintenance.openLog(at: session.descriptor, name: kCoreLogName) }
        try clearACL(writers[0])
        try expect(symlinkat(session.path, root.descriptor, "linked-session") == 0, "Cannot create session symlink")
        try expectFailure("Session symlink accepted") { _ = try CoreLogMaintenance.openDirectory(at: root.descriptor, name: "linked-session") }
        let unknown = try PrivilegedDirectory.open(CoreLogMaintenance.rootDirectory + "/unknown", create: true)
        try unknown.write(Data("retained stdout".utf8), name: kCoreLogName, mode: 0o644)
        try unknown.ensureLog(kCoreCrashLogName)
        try unknown.write(Data("keep".utf8), name: "unrelated-file", mode: 0o600)
        try maintenance.queue.sync { try maintenance.removeSessionLocked("unknown") }
        try expect(try unknown.read("unrelated-file", limit: 16) == Data("keep".utf8), "Cleanup recursively removed unknown contents")
        try expect(try unknown.read(kCoreLogName, limit: 64) == Data("retained stdout".utf8),
                   "Cleanup partially removed a session containing extra files")
        try expect(try contents(target) == Data("unchanged".utf8), "Log maintenance changed a symlink target")
        let descriptors = maintenance.queue.sync { maintenance.logFiles.map(\.descriptor) + [maintenance.rootDescriptor] }
        maintenance.stop()
        for fd in descriptors { try expect(fcntl(fd, F_GETFD) == -1 && errno == EBADF, "Stop leaked a maintenance descriptor") }
        print("PASS: log session boundaries, both streams, held append FDs, time/size thresholds, actual timer, retention, unsafe entries and stop cleanup")
    }
    #endif
}
