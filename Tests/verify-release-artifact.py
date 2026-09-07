#!/usr/bin/env python3
"""Read-only checks of a built universal fork; does not launch or install it."""
import json
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


require(not any(key.startswith(("SU", "SPU")) for key in info), "Built app has no upstream updater settings")
require(not any("sparkle" in path.name.lower() for path in contents.rglob("*")), "Built app embeds no Sparkle updater")
for executable in [binary, helper]:
    dependencies = subprocess.check_output(["/usr/bin/otool", "-L", str(executable)], text=True)
    require("Sparkle" not in dependencies, f"No Sparkle load command: {executable.name}")
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(executable)], text=True).split()
    require(set(architectures) == {"arm64", "x86_64"}, f"Both Mac architectures: {executable.name}")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(executable)], check=True)
    checks += 1
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
checks += 1
for language in ["zh-Hans", "zh-Hant"]:
    strings = contents / "Resources" / (language + ".lproj") / "Localizable.strings"
    translated = json.loads(subprocess.check_output(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(strings)]))
    require(translated["You're up to date!"] == "已是最新版本", f"Built translation: {language}")
menu = contents / "Resources/Base.lproj/Main.storyboardc/MainMenu.nib"
require(menu.is_file(), "Compiled update menu is included")
compiled_menu = menu.read_bytes()
require(b"checkForUpdates:" in compiled_menu, "Compiled menu retains the local update action")
require(b"SPUStandardUpdaterController" not in compiled_menu, "Compiled nib has no implicit updater")
print(f"Passed {checks} universal app-artifact checks; no application or helper was launched.")
