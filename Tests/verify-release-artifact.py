#!/usr/bin/env python3
"""Read-only architecture and signature checks; does not launch or install the app."""
import pathlib
import plistlib
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 Tests/verify-release-artifact.py '/path/to/ClashX Meta.app'")
app = pathlib.Path(sys.argv[1]).resolve()
contents = app / "Contents"
info = plistlib.loads((contents / "Info.plist").read_bytes())
binary = contents / "MacOS" / info["CFBundleExecutable"]
helper = contents / "Library/LaunchServices/com.metacubex.ClashX.ProxyConfigHelper"
checks = 0


def require(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1


for executable in [binary, helper]:
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(executable)], text=True).split()
    require(set(architectures) == {"arm64", "x86_64"}, f"Both Mac architectures: {executable.name}")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(executable)], check=True)
    checks += 1
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
checks += 1
print(f"Passed {checks} universal app-artifact checks; no application or helper was launched.")
