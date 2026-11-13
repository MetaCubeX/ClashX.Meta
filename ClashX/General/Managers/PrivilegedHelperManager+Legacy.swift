//
//  PrivilegedHelperManager+Legacy.swift
//  ClashX
//
//  Created by yicheng 2020/4/22.
//  Copyright © 2020 west2online. All rights reserved.
//

import Cocoa
import CryptoKit
import Darwin

extension PrivilegedHelperManager {
    enum HelperInstallationError: LocalizedError {
        case cancelled
        case invalidHelper(String)
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return NSLocalizedString("Helper installation was cancelled.", comment: "")
            case let .invalidHelper(message), let .scriptFailed(message):
                return message
            }
        }
    }

    func getInstallScript() throws -> String {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices")
            .appendingPathComponent(Self.machServiceName)
        let digest = try Self.bundledHelperSHA256(at: helperURL)
        return Self.makeInstallScript(helperSourcePath: helperURL.path, expectedSHA256: digest)
    }

    static func makeInstallScript(helperSourcePath: String, expectedSHA256: String) -> String {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>Label</key>
        <string>\(machServiceName)</string>
        <key>MachServices</key>
        <dict>
        <key>\(machServiceName)</key>
        <true/>
        </dict>
        <key>Program</key>
        <string>/Library/PrivilegedHelperTools/\(machServiceName)</string>
        <key>ProgramArguments</key>
        <array>
        <string>/Library/PrivilegedHelperTools/\(machServiceName)</string>
        </array>
        </dict>
        </plist>
        """

        return """
        \(secureDirectoryScript)
        require_secure_directory /
        require_secure_directory /Library
        for directory in /Library/PrivilegedHelperTools /Library/LaunchDaemons; do
            if [ ! -e "$directory" ] && [ ! -L "$directory" ]; then
                /bin/mkdir -m 0755 "$directory"
            fi
            require_secure_directory "$directory"
        done
        helperPath=\(shellQuote("/Library/PrivilegedHelperTools/" + machServiceName))
        plistPath=\(shellQuote("/Library/LaunchDaemons/" + machServiceName + ".plist"))
        serviceTarget=\(shellQuote("system/" + machServiceName))
        require_regular_destination "$helperPath"
        require_regular_destination "$plistPath"

        stagedHelper=''
        stagedPlist=''
        cleanup() {
            if [ -n "$stagedHelper" ]; then /bin/rm -f "$stagedHelper"; fi
            if [ -n "$stagedPlist" ]; then /bin/rm -f "$stagedPlist"; fi
        }
        trap cleanup EXIT
        trap 'exit 1' HUP INT TERM
        stagedHelper=$(/usr/bin/mktemp /Library/PrivilegedHelperTools/.clashx-helper.XXXXXXXX)
        stagedPlist=$(/usr/bin/mktemp /Library/LaunchDaemons/.clashx-helper.XXXXXXXX)
        /bin/cp -X \(shellQuote(helperSourcePath)) "$stagedHelper"
        actualDigest=$(/usr/bin/env -i /usr/bin/shasum -a 256 "$stagedHelper")
        actualDigest=${actualDigest%% *}
        if [ "$actualDigest" != \(shellQuote(expectedSHA256)) ]; then
            fail 'The bundled helper changed while installation was being authorized. Please retry.'
        fi
        /usr/sbin/chown root:wheel "$stagedHelper"
        /bin/chmod 0755 "$stagedHelper"
        /usr/bin/printf '%s\\n' \(shellQuote(plist)) > "$stagedPlist"
        /usr/bin/plutil -lint "$stagedPlist" > /dev/null
        /usr/sbin/chown root:wheel "$stagedPlist"
        /bin/chmod 0644 "$stagedPlist"

        if /bin/launchctl print "$serviceTarget" > /dev/null 2>&1; then
            /bin/launchctl bootout "$serviceTarget"
        fi
        /bin/mv -f "$stagedHelper" "$helperPath"
        stagedHelper=''
        /bin/mv -f "$stagedPlist" "$plistPath"
        stagedPlist=''
        /bin/launchctl enable "$serviceTarget"
        /bin/launchctl bootstrap system "$plistPath"
        /bin/launchctl print "$serviceTarget" > /dev/null
        """
    }

    @MainActor
    func runScriptWithRootPermission(script: String) throws {
        let source = "do shell script \(Self.appleScriptQuote(script)) with administrator privileges"
        guard let appleScript = NSAppleScript(source: source) else {
            throw HelperInstallationError.scriptFailed("Could not prepare the helper installation script.")
        }
        var errorInfo: NSDictionary?
        _ = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -128 {
                throw HelperInstallationError.cancelled
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "The helper installation script failed."
            throw HelperInstallationError.scriptFailed(message)
        }
    }

    @MainActor
    func legacyInstallHelper() async throws {
        let script = try getInstallScript()
        try runScriptWithRootPermission(script: script)
        resetHelper(invalidate: true)
        try? await Task.sleep(seconds: 1)
    }

    @MainActor
    func removeInstallHelper() async throws {
        let script = """
        \(Self.secureDirectoryScript)
        require_secure_directory /
        require_secure_directory /Library
        for directory in /Library/PrivilegedHelperTools /Library/LaunchDaemons; do
            if [ -e "$directory" ] || [ -L "$directory" ]; then
                require_secure_directory "$directory"
            fi
        done
        helperPath=\(Self.shellQuote("/Library/PrivilegedHelperTools/" + Self.machServiceName))
        plistPath=\(Self.shellQuote("/Library/LaunchDaemons/" + Self.machServiceName + ".plist"))
        serviceTarget=\(Self.shellQuote("system/" + Self.machServiceName))
        require_regular_destination "$helperPath"
        require_regular_destination "$plistPath"
        if /bin/launchctl print "$serviceTarget" > /dev/null 2>&1; then
            /bin/launchctl bootout "$serviceTarget"
        fi
        /bin/rm -f "$plistPath" "$helperPath"
        """

        try runScriptWithRootPermission(script: script)
        resetHelper(invalidate: true)
    }

    private static func bundledHelperSHA256(at url: URL) throws -> String {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw HelperInstallationError.invalidHelper("Could not open the bundled helper for verification.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw HelperInstallationError.invalidHelper("The bundled helper must be a regular file.")
        }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static var secureDirectoryScript: String {
        """
        set -eu
        umask 077
        fail() {
            /usr/bin/printf '%s\\n' "$1" >&2
            exit 1
        }
        require_secure_directory() {
            if [ -L "$1" ] || [ ! -d "$1" ]; then
                fail "Unsafe helper installation directory: $1"
            fi
            if [ "$(/usr/bin/stat -f '%u' "$1")" != 0 ]; then
                fail "The helper installation directory is not owned by root: $1"
            fi
            directoryMode=$(/usr/bin/stat -f '%Lp' "$1")
            if [ "$((0$directoryMode & 0022))" -ne 0 ]; then
                fail "The helper installation directory is writable by another user: $1"
            fi
            directoryListing=$(/bin/ls -lde "$1")
            directoryACL=$(/usr/bin/printf '%s\\n' "$directoryListing" | /usr/bin/tail -n +2)
            if [ -n "$directoryACL" ]; then
                fail "The helper installation directory has an unsupported access control list: $1"
            fi
        }
        require_regular_destination() {
            if [ -L "$1" ] || { [ -e "$1" ] && [ ! -f "$1" ]; }; then
                fail "Unsafe helper installation destination: $1"
            fi
        }
        """
    }
}
