import AppKit

/// Anthropic's own menu bar mark, copied from the installed Claude.app. It is their
/// trademark: fine for identifying whose usage this is on your own machine, not something
/// to redistribute.
enum ClaudeMark {
    static let shared: NSImage? = {
        guard
            let url = Bundle.main.url(forResource: "ClaudeMarkTemplate", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }()

    static func draw(in rect: CGRect, tint: NSColor?) {
        guard let shared else { return }
        shared.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        if let tint {
            tint.set()
            rect.fill(using: .sourceAtop)
        }
    }
}

/// The always-visible part: the mark says whose usage this is, the number says how much.
/// Drawn with Core Graphics rather than rendered from SwiftUI so it lands on exact pixels
/// at both 1x and 2x, the way a system menu bar item does.
enum MenuBarIcon {
    static let canvasHeight: CGFloat = 18
    static let markSize: CGFloat = 14
    static let gap: CGFloat = 4
    static let ringDiameter: CGFloat = 13
    static let lineWidth: CGFloat = 1.7

    static func image(percent: Double?, showsNumber: Bool) -> NSImage {
        let level = Level(percent: percent ?? 0)
        let colored = percent != nil && level.wantsColorInMenuBar
        let ink: NSColor = colored ? level.nsColor : .black

        let label: NSAttributedString? = showsNumber ? text(percent, color: ink) : nil
        let trailing = label?.size().width ?? ringDiameter
        let width = markSize + gap + trailing

        let image = NSImage(size: NSSize(width: ceil(width), height: canvasHeight), flipped: false) { _ in
            ClaudeMark.draw(
                in: CGRect(
                    x: 0, y: (canvasHeight - markSize) / 2, width: markSize, height: markSize
                ),
                tint: colored ? ink : nil
            )

            if let label {
                label.draw(
                    at: NSPoint(
                        x: markSize + gap, y: (canvasHeight - label.size().height) / 2
                    )
                )
            } else {
                drawRing(
                    percent: percent,
                    centre: CGPoint(x: markSize + gap + ringDiameter / 2, y: canvasHeight / 2),
                    ink: ink
                )
            }
            return true
        }

        image.isTemplate = !colored
        return image
    }

    /// Only drawn when the number is hidden — otherwise it would say the same thing twice.
    private static func drawRing(percent: Double?, centre: CGPoint, ink: NSColor) {
        let radius = (ringDiameter - lineWidth) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        ink.withAlphaComponent(0.25).setStroke()
        track.stroke()

        guard let percent, percent > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: centre,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * min(1, percent / 100),
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        ink.setStroke()
        arc.stroke()
    }

    private static func text(_ percent: Double?, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: percent.map { "\(Int($0.rounded()))%" } ?? "–",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: color,
            ]
        )
    }
}
