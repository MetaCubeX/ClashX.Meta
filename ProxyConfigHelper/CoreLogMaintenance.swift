import Darwin
import Foundation
import os.log

final class CoreLogMaintenance: @unchecked Sendable {
    static let rootDirectory = "/Library/Logs/com.metacubex.ClashX.meta"
    private static let maximumLogSize: off_t = 5 * 1024 * 1024
    private static let clearInterval: UInt64 = 300 * 1_000_000_000
    private static let maximumSessions = 20
    private static let logNames = [kCoreLogName, kCoreCrashLogName]

    private enum MaintenanceError: LocalizedError {
        case unsafePath
        case io(Int32)

        var errorDescription: String? {
            switch self {
            case .unsafePath:
                return "Refusing to maintain an unsafe core log path."
            case let .io(code):
                return "Core log maintenance failed: \(String(cString: strerror(code)))."
            }
        }
    }

    private struct LogFile {
        let descriptor: Int32
        var clearedAt: UInt64
    }

    // All mutable state and descriptor lifetimes are confined to this queue.
    private let queue = DispatchQueue(label: "com.metacubex.ClashX.core-log-maintenance")
    private var timer: DispatchSourceTimer?
    private var rootDescriptor: Int32 = -1
    private var sessionID = ""
    private var logFiles: [LogFile] = []

    deinit {
        stopLocked()
    }

    static func sessionDirectory(sessionID: String) throws -> String {
        guard isValidSessionID(sessionID) else { throw MaintenanceError.unsafePath }
        return "\(rootDirectory)/\(sessionID)"
    }

    private static func isValidSessionID(_ value: String) -> Bool {
        let bytes = value.utf8
        return (1...64).contains(bytes.count) && bytes.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) ||
                (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    // The caller creates the protected directory and files before starting launchd.
    func start(sessionID: String) throws {
        _ = try Self.sessionDirectory(sessionID: sessionID)
        try queue.sync {
            stopLocked()
            do {
                rootDescriptor = try Self.openRootDirectory()
                let session = try Self.openDirectory(at: rootDescriptor, name: sessionID)
                defer { close(session) }

                let now = DispatchTime.now().uptimeNanoseconds
                for name in Self.logNames {
                    let file = try Self.openLog(at: session, name: name)
                    logFiles.append(LogFile(descriptor: file, clearedAt: now))
                }
                self.sessionID = sessionID
                try maintainLocked()

                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5), leeway: .milliseconds(250))
                timer.setEventHandler { [weak self] in
                    do {
                        try self?.maintainLocked()
                    } catch {
                        os_log("Core log maintenance failed: %{public}@", type: .error, error.localizedDescription)
                    }
                }
                self.timer = timer
                timer.resume()
            } catch {
                stopLocked()
                throw error
            }
        }
    }

    func stop() {
        queue.sync { stopLocked() }
    }

    private func stopLocked() {
        timer?.cancel()
        timer = nil
        for file in logFiles { close(file.descriptor) }
        logFiles.removeAll()
        if rootDescriptor >= 0 { close(rootDescriptor) }
        rootDescriptor = -1
        sessionID = ""
    }

    private func maintainLocked() throws {
        guard rootDescriptor >= 0 else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        for index in logFiles.indices {
            let file = logFiles[index]
            let metadata = try Self.validate(file.descriptor, directory: false)
            if metadata.st_size > Self.maximumLogSize || now - file.clearedAt >= Self.clearInterval {
                // Keep the inode opened by launchd; renaming would leave its output unbounded.
                guard ftruncate(file.descriptor, 0) == 0 else { throw MaintenanceError.io(errno) }
                logFiles[index].clearedAt = now
            }
        }
        try pruneSessionsLocked()
    }

    private func pruneSessionsLocked() throws {
        var sessions: [(name: String, modified: timespec)] = []
        for name in try Self.entries(at: rootDescriptor) where Self.isValidSessionID(name) {
            guard name != sessionID,
                  let descriptor = try? Self.openDirectory(at: rootDescriptor, name: name) else { continue }
            var metadata = stat()
            if fstat(descriptor, &metadata) == 0 {
                sessions.append((name, metadata.st_mtimespec))
            }
            close(descriptor)
        }
        sessions.sort {
            if $0.modified.tv_sec != $1.modified.tv_sec { return $0.modified.tv_sec > $1.modified.tv_sec }
            if $0.modified.tv_nsec != $1.modified.tv_nsec { return $0.modified.tv_nsec > $1.modified.tv_nsec }
            return $0.name > $1.name
        }
        for session in sessions.dropFirst(Self.maximumSessions - 1) {
            try removeSessionLocked(session.name)
        }
    }

    private func removeSessionLocked(_ name: String) throws {
        guard name != sessionID, Self.isValidSessionID(name) else { throw MaintenanceError.unsafePath }
        let descriptor = try Self.openDirectory(at: rootDescriptor, name: name)
        defer { close(descriptor) }
        let names = try Self.entries(at: descriptor)
        // Never recursively delete an unexpected file, subdirectory or symlink.
        guard names.allSatisfy({ Self.logNames.contains($0) }) else { return }
        for fileName in names {
            guard let file = try? Self.openLog(at: descriptor, name: fileName) else { return }
            close(file)
        }
        for fileName in names {
            guard unlinkat(descriptor, fileName, 0) == 0 else { throw MaintenanceError.io(errno) }
        }
        guard unlinkat(rootDescriptor, name, AT_REMOVEDIR) == 0 else { throw MaintenanceError.io(errno) }
    }

    private static func openRootDirectory() throws -> Int32 {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MaintenanceError.io(errno) }
        do {
            _ = try validate(descriptor, directory: true)
            for component in rootDirectory.split(separator: "/") {
                let next = try openDirectory(at: descriptor, name: String(component))
                close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func openDirectory(at parent: Int32, name: String) throws -> Int32 {
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MaintenanceError.io(errno) }
        do {
            _ = try validate(descriptor, directory: true)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func openLog(at parent: Int32, name: String) throws -> Int32 {
        let descriptor = openat(parent, name, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MaintenanceError.io(errno) }
        do {
            _ = try validate(descriptor, directory: false)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func validate(_ descriptor: Int32, directory: Bool) throws -> stat {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw MaintenanceError.io(errno) }
        let expectedType = directory ? S_IFDIR : S_IFREG
        guard metadata.st_uid == 0,
              metadata.st_mode & S_IFMT == expectedType,
              metadata.st_mode & (S_IWGRP | S_IWOTH) == 0,
              directory || metadata.st_nlink == 1 else { throw MaintenanceError.unsafePath }

        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            // Darwin reports ENOENT when an open file has no extended ACL.
            if errno == ENOENT { return metadata }
            throw MaintenanceError.io(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var selector = ACL_FIRST_ENTRY
        let writePermissions: [acl_perm_t] = [ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD,
                                             ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES,
                                             ACL_WRITE_SECURITY, ACL_CHANGE_OWNER]
        while acl_get_entry(acl, selector.rawValue, &entry) == 0 {
            selector = ACL_NEXT_ENTRY
            guard let entry else { throw MaintenanceError.unsafePath }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else { throw MaintenanceError.io(errno) }
            if tag == ACL_EXTENDED_ALLOW {
                var permissions: acl_permset_t?
                guard acl_get_permset(entry, &permissions) == 0, let permissions else {
                    throw MaintenanceError.io(errno)
                }
                for permission in writePermissions {
                    guard acl_get_perm_np(permissions, permission) == 0 else { throw MaintenanceError.unsafePath }
                }
            }
        }
        return metadata
    }

    private static func entries(at descriptor: Int32) throws -> [String] {
        let duplicate = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard duplicate >= 0 else { throw MaintenanceError.io(errno) }
        guard let directory = fdopendir(duplicate) else {
            let code = errno
            close(duplicate)
            throw MaintenanceError.io(code)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw MaintenanceError.io(errno) }
                return names
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
    }
}
