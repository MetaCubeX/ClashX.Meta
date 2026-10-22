#!/bin/zsh
set -eu

readonly repo_root=$(cd "$(dirname "$0")/../.." && pwd)
readonly security_source="$repo_root/ProxyConfigHelper/HelperXPCSecurity.swift"
readonly test_source="$repo_root/Tests/HelperXPCSecurity/HelperXPCSecurityTest.swift"
readonly build_dir=$(mktemp -d)
readonly test_binary="$build_dir/helper-xpc-security-test"

cleanup() {
	rm -rf "$build_dir"
}
trap cleanup EXIT

swiftc ${=CLASHX_SWIFTC_FLAGS:-} "$test_source" "$security_source" -framework Security -o "$test_binary"

codesign --force --sign - --identifier com.metacubex.ClashX.meta "$test_binary"
"$test_binary" accepted

codesign --force --sign - --identifier com.example.unauthorized "$test_binary"
"$test_binary" rejected
