#!/bin/sh
set -eu

source_file="${1:-ProxyConfigHelper/ProxyConfigHelper.m}"

if ! sed -n '/invalidationHandler = \^{/,/};/p' "$source_file" | grep -q 'stopMihomoIfOrphaned'; then
    echo "FAIL: last XPC disconnect must stop orphaned Mihomo" >&2
    exit 1
fi

if ! sed -n '/connectionCheckOnLaunch/,/^}/p' "$source_file" | grep -q 'stopMihomoIfOrphaned'; then
    echo "FAIL: helper startup without app must clean stale Mihomo" >&2
    exit 1
fi

echo "PrivilegedHelperLifecycleTests: PASS"
