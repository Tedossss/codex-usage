import SwiftUI

/// Grey until it matters. A meter that is always coloured is a meter you stop reading,
/// so nothing earns colour below 60%.
enum Level: Int, Comparable {
    case calm, warm, high, critical

    init(percent: Double) {
        switch percent {
        case ..<60: self = .calm
        case ..<80: self = .warm
        case ..<93: self = .high
        default: self = .critical
        }
    }

    static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .calm: return .primary
        case .warm: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .calm: return .labelColor
        case .warm: return .systemYellow
        case .high: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// The menu bar stays a template image while calm, so macOS can invert it with the
    /// menu bar's own appearance. Colour opts out of that, so only spend it on a warning.
    var wantsColorInMenuBar: Bool { self != .calm }
}
