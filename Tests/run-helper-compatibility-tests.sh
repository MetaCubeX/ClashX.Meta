#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
test_directory=$(/usr/bin/mktemp -d /private/tmp/clashx-helper-tests.XXXXXXXX)
trap '/bin/rm -rf "$test_directory"' EXIT

# Keep production compatibility and lifecycle methods unchanged. Replace only
# external frameworks, filesystem queries, and the unavailable privileged installer.
/usr/bin/python3 - "$repository_root" "$test_directory" <<'PY'
import pathlib
import sys

repository = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
source = (repository / "ClashX/General/Managers/PrivilegedHelperManager.swift").read_text()
for dependency in ["AppKit", "RxCocoa", "RxSwift", "ServiceManagement"]:
    statement = "import " + dependency + "\n"
    assert source.count(statement) == 1, statement
    source = source.replace(statement, "")

start = source.index("    private func installHelperDaemon() -> DaemonInstallResult {")
end = source.index("\n    private func configuredConnection()", start)
source = source[:start] + """    private func installHelperDaemon() -> DaemonInstallResult {
        preconditionFailure("The real privileged installer is unavailable in offline tests")
    }
""" + source[end:]
source = source[:source.index("\nprivate enum DaemonInstallResult {")]

for original, replacement, count in [
    ("CFBundleCopyInfoDictionaryForURL(", "OfflineEnvironment.bundleInfo(", 2),
    ("FileManager.default.fileExists(atPath:", "OfflineEnvironment.fileExists(atPath:", 1),
]:
    assert source.count(original) == count, original
    source = source.replace(original, replacement)

tests = (repository / "Tests/HelperCompatibilityTests.swift").read_text()
(destination / "HelperCompatibilityTests.swift").write_text(source + "\n" + tests)
PY

/usr/bin/xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$test_directory/modules" \
    "$repository_root/ProxyConfigHelper/ProxyConfigHelperXPCTransport.swift" \
    "$test_directory/HelperCompatibilityTests.swift" \
    -o "$test_directory/helper-compatibility-tests"
"$test_directory/helper-compatibility-tests"
