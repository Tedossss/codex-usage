import AppKit

/// The always-visible part. Drawn with Core Graphics rather than rendered from SwiftUI so
/// the ring lands on exact pixels at both 1x and 2x, the way a system menu bar item does.
enum MenuBarIcon {
    static let diameter: CGFloat = 15
    static let lineWidth: CGFloat = 1.8
    static let canvasHeight: CGFloat = 18

    static func image(percent: Double?, showsNumber: Bool, working: Int) -> NSImage {
        let level = Level(percent: percent ?? 0)
        let colored = percent != nil && level.wantsColorInMenuBar
        let ink: NSColor = colored ? level.nsColor : .black

        let label: NSAttributedString? = showsNumber ? text(percent, color: ink) : nil
        let gap: CGFloat = label == nil ? 0 : 4
        let width = diameter + gap + (label?.size().width ?? 0)

        let image = NSImage(size: NSSize(width: ceil(width), height: canvasHeight), flipped: false) { _ in
            let centre = CGPoint(x: diameter / 2, y: canvasHeight / 2)
            let radius = (diameter - lineWidth) / 2

            let track = NSBezierPath()
            track.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            ink.withAlphaComponent(0.22).setStroke()
            track.stroke()

            if let percent, percent > 0 {
                let sweep = 360 * min(1, percent / 100)
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: centre,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - sweep,
                    clockwise: true
                )
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                ink.setStroke()
                arc.stroke()
            } else if percent == nil {
                // No reading yet: a hollow ring with a dot, not a zero we cannot vouch for.
                let dot = NSBezierPath(ovalIn: CGRect(x: centre.x - 1.4, y: centre.y - 1.4, width: 2.8, height: 2.8))
                ink.withAlphaComponent(0.45).setFill()
                dot.fill()
            }

            if working > 0 {
                let badge = NSBezierPath(
                    ovalIn: CGRect(x: diameter - 3.4, y: canvasHeight - 6.6, width: 3.4, height: 3.4)
                )
                (colored ? ink : NSColor.black).setFill()
                badge.fill()
            }

            label?.draw(
                at: NSPoint(
                    x: diameter + gap,
                    y: (canvasHeight - (label?.size().height ?? 0)) / 2
                )
            )
            return true
        }

        image.isTemplate = !colored
        return image
    }

    private static func text(_ percent: Double?, color: NSColor) -> NSAttributedString {
        let value = percent.map { "\(Int($0.rounded()))%" } ?? "–"
        return NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: color,
            ]
        )
    }
}
