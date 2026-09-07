#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
test_directory=$(/usr/bin/mktemp -d /private/tmp/clashx-security-tests.XXXXXXXX)
trap '/bin/rm -rf "$test_directory"' EXIT

/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$test_directory/modules" \
    "$repository_root/ProxyConfigHelper/PrivilegedFileStore.swift" \
    "$repository_root/ProxyConfigHelper/ProxyConfigHelperXPCTransport.swift" \
    "$repository_root/Tests/PrivilegedFileStoreTests.swift" \
    -o "$test_directory/file-tests"
"$test_directory/file-tests" "$test_directory/fixtures"
/bin/bash "$repository_root/Tests/run-alpha-security-tests.sh"
/usr/bin/python3 "$repository_root/Tests/run-app-update-tests.py"
/bin/bash "$repository_root/Tests/run-storage-security-tests.sh"
/bin/bash "$repository_root/Tests/run-helper-compatibility-tests.sh"
/usr/bin/python3 "$repository_root/Tests/run-core-trust-tests.py"
