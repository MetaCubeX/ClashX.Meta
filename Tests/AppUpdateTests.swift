import Foundation

// The test runner compiles the actual menu action with this in-memory alert.
// It never starts the application, displays UI, or changes persistent preferences.
final class NSAlert {
    enum Style { case informational, warning }
    var messageText = ""
    var informativeText = ""
    var alertStyle: Style = .warning
    var buttons = [String]()
    static var presented = [NSAlert]()

    func addButton(withTitle title: String) { buttons.append(title) }
    func runModal() { Self.presented.append(self) }
}

enum AppVersionUtil {
    static var currentVersion = ""
    static var currentBuild = ""
}

@main
struct AppUpdateTests {
    static func main() {
        let subject = AppUpdateSubject()
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        var checks = 0
        for autoCheck in [false, true] {
            for autoInstall in [false, true] {
                defaults.setVolatileDomain([
                    "SUEnableAutomaticChecks": autoCheck,
                    "SUAutomaticallyUpdate": autoInstall,
                    "SUFeedURL": "https://upstream.invalid/newer-appcast.xml",
                    "SULastCheckTime": Date.distantPast,
                    "SUSkippedVersion": "9999.0"
                ], forName: UserDefaults.argumentDomain)
                for version in ["", "0", "1.4.0-fork.1", "999999999999999999999", "版本🔥", "\"\n/path"] {
                    AppVersionUtil.currentVersion = version
                    AppVersionUtil.currentBuild = version.isEmpty ? "" : "42"
                    for sender: Any? in [nil, NSObject()] {
                        let before = NSAlert.presented.count
                        subject.checkForUpdates(sender)
                        precondition(NSAlert.presented.count == before + 1, "Exactly one local response")
                        let alert = NSAlert.presented.last!
                        precondition(alert.messageText == "You're up to date!", "Always the latest status")
                        precondition(alert.informativeText == "ClashX Meta \(version) (\(AppVersionUtil.currentBuild))", "Display the local version without parsing")
                        precondition(alert.alertStyle == .informational && alert.buttons == ["OK"], "No download/install action")
                        checks += 1
                    }
                }
            }
        }
        for _ in 0..<100 { subject.checkForUpdates(nil) }
        precondition(NSAlert.presented.count == checks + 100, "Repeated requests stay local")
        print("Passed \(checks + 100) local app-update scenarios with volatile preferences and an in-memory alert.")
    }
}
