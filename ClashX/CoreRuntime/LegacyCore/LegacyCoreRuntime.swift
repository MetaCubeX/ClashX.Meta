import Foundation

/// Ownership boundary for the existing embedded Go core. The C bridge remains
/// untouched so macOS 10.13 through 12 keep their established runtime path.
enum LegacyCoreRuntime {
    static func initialize() {
        initClashCore()
    }
}
