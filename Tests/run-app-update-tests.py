#!/usr/bin/env python3
"""Check update wiring and execute the real menu action without launching the app."""
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "ClashX/AppDelegate.swift").read_text()
storyboard = ET.parse(root / "ClashX/Base.lproj/Main.storyboard").getroot()
project = (root / "ClashX.xcodeproj/project.pbxproj").read_text()
info = plistlib.loads((root / "ClashX/Info.plist").read_bytes())
resolved = json.loads((root / "ClashX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
checks = 0


def require(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1


require("Sparkle" not in project, "No Sparkle build/link/package dependency")
require(all(pin["identity"] != "sparkle" for pin in resolved["pins"]), "No Sparkle package pin")
require(not any(key.startswith(("SU", "SPU")) for key in info), "No upstream feed or updater configuration")
for path in (root / "ClashX").rglob("*.swift"):
    require(not re.search(r"\b(Sparkle|SPUStandardUpdaterController|SPUUpdater|SUUpdater)\b", path.read_text()),
            f"No implicit or programmatic updater in {path.relative_to(root)}")
require(not any("Updater" in node.attrib.get("customClass", "") for node in storyboard.iter()), "No nib-created updater")
require(not any(node.attrib.get("property") == "updaterController" for node in storyboard.iter("outlet")), "No dangling updater outlet")
actions = [node for node in storyboard.iter("action") if node.attrib.get("selector") == "checkForUpdates:"]
require(len(actions) == 1, "Exactly one manual app-update entry")
targets = [node for node in storyboard.iter() if node.attrib.get("id") == actions[0].attrib["target"]]
require(len(targets) == 1 and targets[0].attrib.get("customClass") == "AppDelegate", "Update menu targets the local action")
require("try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.UpdateAlphaCore())" in
        (root / "ClashX/General/AlphaMetaDownloader.swift").read_text(), "Alpha update remains routed through helper")
require("https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha" in
        (root / "ProxyConfigHelper/TrustedAlphaRelease.swift").read_text(), "Alpha keeps its independently verified source")
require("RemoteConfigManager.shared.updateCheck" in source and "func updateGEO" in source,
        "Subscription and GEO update entries remain available")
translations = json.loads((root / "ClashX/Support Files/Localizable.xcstrings").read_text())["strings"]["You're up to date!"]["localizations"]
for language in ["zh-Hans", "zh-Hant"]:
    require(translations[language]["stringUnit"]["value"] == "已是最新版本", f"Local latest-status translation for {language}")

match = re.search(r"    @IBAction func checkForUpdates\(_ sender: Any\?\) \{", source)
require(match is not None, "Local update action exists")
start = source.index("{", match.start())
depth = 1
end = start + 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
action = source[match.start():end]
require(not any(token in action for token in ["URLSession", "URLRequest", "Process(", "Task {", "DispatchQueue"]),
        "The update action has no network, process, or deferred work")
with tempfile.TemporaryDirectory(prefix="clashx-app-update-tests.", dir="/private/tmp") as tmp:
    temporary = pathlib.Path(tmp)
    sdk = subprocess.check_output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    compiled = temporary / "AppUpdate.swift"
    compiled.write_text((root / "Tests/AppUpdateTests.swift").read_text() +
                        "\nfinal class AppUpdateSubject: NSObject {\n" + action + "\n}\n")
    subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                    "-sdk", sdk,
                    "-module-cache-path", str(temporary / "modules"), str(compiled),
                    "-o", str(temporary / "app-update-tests")], check=True)
    subprocess.run([str(temporary / "app-update-tests")], check=True)
print(f"Passed {checks} source, storyboard, localization, and dependency checks.")
