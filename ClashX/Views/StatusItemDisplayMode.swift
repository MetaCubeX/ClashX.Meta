import Foundation

enum StatusItemDisplayMode {
    case full
    case speedOnly
    case iconOnly

    static func resolve(showSpeed: Bool, speedOnly: Bool) -> StatusItemDisplayMode {
        guard showSpeed else { return .iconOnly }
        return speedOnly ? .speedOnly : .full
    }

    var showsIcon: Bool {
        self != .speedOnly
    }

    var showsSpeed: Bool {
        self != .iconOnly
    }

    var statusItemLength: CGFloat {
        switch self {
        case .full: return 72
        case .speedOnly: return 34
        case .iconOnly: return 25
        }
    }

    var contentOffsetX: CGFloat {
        switch self {
        case .full: return 38
        case .speedOnly: return 3
        case .iconOnly: return 3
        }
    }
}
