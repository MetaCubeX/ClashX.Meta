import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum StatusItemDisplayModeTests {
    static func main() {
        expect(StatusItemDisplayMode.full.showsIcon, "full mode must show icon")
        expect(StatusItemDisplayMode.full.showsSpeed, "full mode must show speed")
        expect(StatusItemDisplayMode.speedOnly.showsIcon == false, "speed-only mode must hide icon")
        expect(StatusItemDisplayMode.speedOnly.showsSpeed, "speed-only mode must show speed")
        expect(StatusItemDisplayMode.iconOnly.showsIcon, "icon-only mode must show icon")
        expect(StatusItemDisplayMode.iconOnly.showsSpeed == false, "icon-only mode must hide speed")
        expect(StatusItemDisplayMode.speedOnly.statusItemLength < StatusItemDisplayMode.full.statusItemLength,
               "speed-only mode must save menu bar space")
        expect(StatusItemDisplayMode.speedOnly.contentOffsetX == 3,
               "speed-only mode must keep only standard edge padding")
        expect(StatusItemDisplayMode.resolve(showSpeed: true, speedOnly: true) == .speedOnly,
               "enabled speed-only setting must select speed-only mode")
        expect(StatusItemDisplayMode.resolve(showSpeed: false, speedOnly: true) == .iconOnly,
               "hidden speed must keep icon available for opening menu")
        print("StatusItemDisplayModeTests: PASS")
    }
}
