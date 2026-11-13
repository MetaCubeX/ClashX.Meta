#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
test_directory=$(/usr/bin/mktemp -d /private/tmp/clashx-storage-tests.XXXXXXXX)
trap '/bin/rm -rf "$test_directory"' EXIT

# First compile the unchanged sources and exercise only read-only root operations.
/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$test_directory/modules" \
    "$repository_root/ProxyConfigHelper/PrivilegedFileStore.swift" \
    "$repository_root/ProxyConfigHelper/TrustedCoreStore.swift" \
    "$repository_root/ProxyConfigHelper/CoreLogMaintenance.swift" \
    "$repository_root/Tests/PrivilegedStorageIntegrationTests.swift" \
    -o "$test_directory/production-tests"
"$test_directory/production-tests" "$test_directory/production-fixtures"

# Isolate privileged mutations without requiring root. Only the trust root, expected
# UID/GID and private-member visibility change in these disposable source copies.
# The I/O, digest, receipt, ACL, retention and timer implementations remain unchanged.
/usr/bin/python3 - "$repository_root" "$test_directory" <<'PY'
from pathlib import Path
import sys

repository = Path(sys.argv[1])
destination = Path(sys.argv[2])

def replace_once(source, before, after):
    if source.count(before) != 1:
        raise RuntimeError(f"Update the storage test isolation for changed source: {before}")
    return source.replace(before, after)

source = (repository / "ProxyConfigHelper/PrivilegedFileStore.swift").read_text()
source = replace_once(source, 'let components = path.split(separator: "/").map(String.init)',
    'guard path == storageFixtureRoot || path.hasPrefix(storageFixtureRoot + "/") else { '
    'throw PrivilegedFileError.unsafePath(path) }\n'
    '        let components = path.dropFirst(storageFixtureRoot.count).split(separator: "/").map(String.init)')
source = replace_once(source, 'var fd = Darwin.open("/",', 'var fd = Darwin.open(storageFixtureRoot,')
source = replace_once(source, 'info.st_uid == 0,', 'info.st_uid == geteuid(),')
source = replace_once(source, 'fchown(fd, 0, 0)', 'fchown(fd, geteuid(), getegid())')
(destination / "PrivilegedFileStore.swift").write_text(source)

source = (repository / "ProxyConfigHelper/TrustedCoreStore.swift").read_text()
source = replace_once(source, 'static let root = "/Library/Application Support/com.metacubex.ClashX.meta"',
    'static let root = storageFixtureRoot + "/store"')
(destination / "TrustedCoreStore.swift").write_text(source)

source = (repository / "ProxyConfigHelper/CoreLogMaintenance.swift").read_text().replace('private ', '')
source = replace_once(source, 'static let rootDirectory = "/Library/Logs/com.metacubex.ClashX.meta"',
    'static let rootDirectory = storageFixtureRoot + "/logs"')
source = replace_once(source, 'var descriptor = open("/",', 'var descriptor = open(storageFixtureRoot,')
source = replace_once(source, 'for component in rootDirectory.split(separator: "/")',
    'for component in rootDirectory.dropFirst(storageFixtureRoot.count).split(separator: "/")')
source = replace_once(source, 'metadata.st_uid == 0,', 'metadata.st_uid == geteuid(),')
(destination / "CoreLogMaintenance.swift").write_text(source)
PY

/usr/bin/xcrun swiftc -swift-version 5 -D STORAGE_ISOLATED -module-cache-path "$test_directory/modules" \
    "$test_directory/PrivilegedFileStore.swift" \
    "$test_directory/TrustedCoreStore.swift" \
    "$test_directory/CoreLogMaintenance.swift" \
    "$repository_root/Tests/PrivilegedStorageIntegrationTests.swift" \
    -o "$test_directory/isolated-tests"
"$test_directory/isolated-tests" "$test_directory/isolated-fixtures"
