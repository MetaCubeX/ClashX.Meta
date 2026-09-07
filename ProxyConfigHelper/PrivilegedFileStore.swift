import CryptoKit
import Darwin
import Foundation

enum PrivilegedFileError: LocalizedError {
    case unsafePath(String)
    case io(String)
    case invalidCore
    case oversizedFile

    var errorDescription: String? {
        switch self {
        case let .unsafePath(path): return "Refusing an unsafe privileged path: \(path)"
        case let .io(path): return "Unable to access privileged file: \(path)"
        case .invalidCore: return "The core does not match a trusted SHA256 digest."
        case .oversizedFile: return "The supplied file exceeds the size limit."
        }
    }
}

/// Operations stay relative to an opened, validated directory descriptor.
final class PrivilegedDirectory {
    let descriptor: Int32
    let path: String

    private init(descriptor: Int32, path: String) {
        self.descriptor = descriptor
        self.path = path
    }

    deinit { close(descriptor) }

    static func open(_ path: String, create: Bool = false, mode: mode_t = 0o755) throws -> PrivilegedDirectory {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw PrivilegedFileError.unsafePath(path) }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains("."), !components.contains("..") else { throw PrivilegedFileError.unsafePath(path) }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw PrivilegedFileError.io("/") }
        do {
            try validate(fd, directory: true, path: "/")
            var current = ""
            for (index, component) in components.enumerated() {
                current += "/" + component
                var child = openat(fd, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                if child < 0, errno == ENOENT, create {
                    let childMode: mode_t = index == components.count - 1 ? mode : 0o755
                    guard mkdirat(fd, component, childMode) == 0 || errno == EEXIST else {
                        throw PrivilegedFileError.io(current)
                    }
                    child = openat(fd, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                guard child >= 0 else { throw PrivilegedFileError.unsafePath(current) }
                do { try validate(child, directory: true, path: current) }
                catch { close(child); throw error }
                close(fd)
                fd = child
            }
            // Only the requested application directory is tightened; shared ancestors are never chmod'ed.
            if create, mode == 0o700 {
                try clearACL(fd, path: path)
                guard fchmod(fd, mode) == 0 else { throw PrivilegedFileError.io(path) }
            }
            return PrivilegedDirectory(descriptor: fd, path: path)
        } catch {
            close(fd)
            throw error
        }
    }

    static func validate(_ fd: Int32, directory: Bool, path: String) throws {
        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_uid == 0,
              info.st_mode & 0o022 == 0,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1 else { throw PrivilegedFileError.unsafePath(path) }
        try rejectWritableACL(fd, path: path)
    }

    private static func rejectWritableACL(_ fd: Int32, path: String) throws {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return }
            throw PrivilegedFileError.io(path)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var selector = ACL_FIRST_ENTRY
        let writes: [acl_perm_t] = [ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD,
                                   ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER]
        while acl_get_entry(acl, selector.rawValue, &entry) == 0 {
            selector = ACL_NEXT_ENTRY
            guard let entry else { throw PrivilegedFileError.unsafePath(path) }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else { throw PrivilegedFileError.io(path) }
            if tag == ACL_EXTENDED_ALLOW {
                var permissions: acl_permset_t?
                guard acl_get_permset(entry, &permissions) == 0, let permissions else { throw PrivilegedFileError.io(path) }
                for permission in writes {
                    guard acl_get_perm_np(permissions, permission) == 0 else { throw PrivilegedFileError.unsafePath(path) }
                }
            }
        }
    }

    private static func clearACL(_ fd: Int32, path: String) throws {
        guard let acl = acl_init(0) else { throw PrivilegedFileError.io(path) }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED) == 0 else { throw PrivilegedFileError.io(path) }
    }

    private func checkName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else {
            throw PrivilegedFileError.unsafePath(name)
        }
    }

    func read(_ name: String, limit: Int) throws -> Data {
        try checkName(name)
        let fd = openat(descriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PrivilegedFileError.io(path + "/" + name) }
        defer { close(fd) }
        try Self.validate(fd, directory: false, path: path + "/" + name)
        return try Self.readDescriptor(fd, limit: limit)
    }

    static func readSource(_ path: String, limit: Int) throws -> Data {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw PrivilegedFileError.unsafePath(path) }
        let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PrivilegedFileError.io(path) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw PrivilegedFileError.unsafePath(path) }
        return try readDescriptor(fd, limit: limit)
    }

    private static func readDescriptor(_ fd: Int32, limit: Int) throws -> Data {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0, info.st_size <= limit else { throw PrivilegedFileError.oversizedFile }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw PrivilegedFileError.io("read") }
            if count == 0 { return data }
            guard data.count <= limit - count else { throw PrivilegedFileError.oversizedFile }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    func write(_ data: Data, name: String, mode: mode_t, expectedSHA256: String? = nil) throws {
        try checkName(name)
        let temporary = "." + UUID().uuidString + ".tmp"
        let fd = openat(descriptor, temporary, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw PrivilegedFileError.io(path) }
        defer { close(fd); unlinkat(descriptor, temporary, 0) }
        // Restrictive POSIX modes alone do not remove inherited read ACLs.
        try Self.clearACL(fd, path: path + "/" + temporary)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw PrivilegedFileError.io(path) }
                offset += count
            }
        }
        if let expectedSHA256 {
            guard Self.isSHA256(expectedSHA256), lseek(fd, 0, SEEK_SET) == 0,
                  Self.sha256(try Self.readDescriptor(fd, limit: data.count)) == expectedSHA256 else {
                throw PrivilegedFileError.invalidCore
            }
        }
        guard fchown(fd, 0, 0) == 0, fchmod(fd, mode) == 0, fsync(fd) == 0 else { throw PrivilegedFileError.io(path) }
        try Self.validate(fd, directory: false, path: path + "/" + temporary)
        guard renameat(descriptor, temporary, descriptor, name) == 0 else { throw PrivilegedFileError.io(path + "/" + name) }
        guard fsync(descriptor) == 0 else { throw PrivilegedFileError.io(path) }
    }

    func ensureLog(_ name: String) throws {
        try checkName(name)
        let fd = openat(descriptor, name, O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o644)
        guard fd >= 0 else { throw PrivilegedFileError.io(path + "/" + name) }
        defer { close(fd) }
        try Self.validate(fd, directory: false, path: path + "/" + name)
    }

    func remove(_ name: String) throws {
        try checkName(name)
        guard unlinkat(descriptor, name, 0) == 0 || errno == ENOENT else { throw PrivilegedFileError.io(path + "/" + name) }
    }

    func removeDirectory(_ name: String) throws {
        try checkName(name)
        guard unlinkat(descriptor, name, AT_REMOVEDIR) == 0 || errno == ENOENT else {
            throw PrivilegedFileError.io(path + "/" + name)
        }
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func isSHA256(_ string: String) -> Bool {
        string.utf8.count == 64 && string.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
