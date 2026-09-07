#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
test_directory=$(/usr/bin/mktemp -d /private/tmp/clashx-alpha-tests.XXXXXXXX)
trap '/bin/rm -rf "$test_directory"' EXIT

/usr/bin/python3 - "$test_directory" <<'PY'
import gzip
import pathlib
import struct
import sys

directory = pathlib.Path(sys.argv[1])
for name, cpu in [("arm", 0x0100000c), ("x86", 0x01000007)]:
    data = struct.pack("<IIIIIIII", 0xfeedfacf, cpu, 0, 2, 0, 0, 0, 0) + b"fixture-only"
    (directory / (name + ".bin")).write_bytes(data)
    if name == "arm":
        (directory / "arm.gz").write_bytes(gzip.compress(data, mtime=0))
PY

# Compile fixtures in the same file to exercise file-private parsing and download boundaries.
/bin/cat "$repository_root/ProxyConfigHelper/TrustedAlphaRelease.swift" \
    "$repository_root/Tests/TrustedAlphaReleaseTests.swift" > "$test_directory/AlphaTests.swift"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$test_directory/modules" "$test_directory/AlphaTests.swift" \
    -o "$test_directory/alpha-tests"
"$test_directory/alpha-tests" "$test_directory"
