import AppKit
import ZielzeitCore

/// The menu bar icon: a small progress ring drawn to reflect actual progress.
///
/// Drawn rather than an SF Symbol so the icon carries information — it fills as
/// the portfolio approaches the goal. Produced as a *template* image, which is
/// what makes it native: macOS tints it for light and dark menu bars, for the
/// highlighted state when the popover is open, and for reduced-contrast modes.
/// A coloured icon would fight all three.
enum StatusItemIcon {

    /// How the ring is drawn in the menu bar.
    enum Style {
        /// Monochrome template image; macOS tints it for the bar.
        case template
        /// The brand mark: the app icon's gradient ring, in colour.
        case brand
        /// The full app icon, plate and all.
        case plate
    }

    /// Menu bar icons are sized in points against the ~22pt bar. Large enough to
    /// hold two digits legibly, small enough not to crowd the bar.
    private static let side: CGFloat = 20
    private static let lineWidth: CGFloat = 1.8

    /// Brand colours come from `Theme.Brand` so the icon, the menu bar and the
    /// popover cannot drift apart.
    private static let brandLight = Theme.Brand.mint
    private static let brandDeep = Theme.Brand.deep

    /// Shortest arc still legible at this size — below this a round-capped
    /// stroke degenerates into a dot.
    private static let minimumArc: Double = 0.06

    /// Metrics for the direction caret drawn beside the ring.
    private static let arrowWidth: CGFloat = 5
    private static let arrowHeight: CGFloat = 4.5
    private static let arrowGap: CGFloat = 2.5

    /// A ring filled to `progress`, with the percentage inside it, and optionally a
    /// direction caret beside it.
    ///
    /// The caret goes in the *image* rather than into the button's title, which was
    /// the obvious place and the wrong one: setting an `attributedTitle` to colour
    /// one glyph takes the whole string out of AppKit's automatic handling, so the
    /// year stops inverting when the popover highlights the status item. Drawing it
    /// here costs a wider canvas and leaves `button.title` a plain string.
    ///
    /// `isDarkBar` only matters for the coloured styles: a template image is
    /// tinted by AppKit, but a colour image has to pick its own contrast.
    static func ring(
        progress: Double,
        direction: MoveDirection? = nil,
        style: Style = .brand,
        isDarkBar: Bool = true
    ) -> NSImage {
        let clamped = min(max(progress, 0), 1)
        let percent = Int((clamped * 100).rounded())
        // `flat` draws nothing: a caret beside a figure that rounds to zero claims
        // a move the number does not show.
        let caret: MoveDirection? = (direction == .flat) ? nil : direction
        let width = caret == nil ? side : side + arrowGap + arrowWidth

        let image = NSImage(size: NSSize(width: width, height: side), flipped: false) { _ in
            // The plate steals the room the digits need, so it gets a tighter
            // ring; the other styles use the full canvas.
            let plate: NSRect?
            let field: NSRect
            switch style {
            case .plate:
                let inset = side * 0.02
                let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
                plate = rect
                field = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16)
            case .template, .brand:
                plate = nil
                field = NSRect(origin: .zero, size: NSSize(width: side, height: side))
            }

            if let plate {
                drawPlate(plate)
            }

            let stroke = style == .plate ? lineWidth * 0.85 : lineWidth
            let ringRect = field.insetBy(dx: stroke / 2, dy: stroke / 2)
            let centre = NSPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = ringRect.width / 2

            // Track.
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = stroke
            trackColor(style: style, isDarkBar: isDarkBar).setStroke()
            track.stroke()

            // Progress arc, clockwise from twelve o'clock.
            if clamped > 0 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: centre,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - max(clamped, minimumArc) * 360,
                    clockwise: true
                )
                switch style {
                case .template:
                    arc.lineWidth = stroke
                    arc.lineCapStyle = .round
                    NSColor.black.setStroke()
                    arc.stroke()
                case .brand, .plate:
                    fillGradient(alongStrokeOf: arc, width: stroke, in: ringRect)
                }
            }

            // The number inside. At 100% a checkmark reads better than three
            // digits crammed into the opening.
            let text = clamped >= 1 ? "✓" : String(percent)
            let font = innerFont(digits: text.count, scaledTo: field.width / side)
            let label = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: digitColor(style: style, isDarkBar: isDarkBar),
            ])
            let size = label.size()
            label.draw(at: NSPoint(
                x: centre.x - size.width / 2,
                // Optical rather than metric centring: the cap-height box sits
                // high, so nudge down by the descender.
                y: centre.y - size.height / 2 + 0.5
            ))

            if let caret {
                drawCaret(
                    caret,
                    at: NSRect(
                        x: side + arrowGap,
                        y: (side - arrowHeight) / 2,
                        width: arrowWidth,
                        height: arrowHeight
                    ),
                    style: style,
                    isDarkBar: isDarkBar
                )
            }

            return true
        }

        // Only the monochrome style may be a template; tinting a colour image
        // would flatten it to a silhouette.
        image.isTemplate = style == .template
        image.accessibilityDescription = Self.describe(percent: percent, direction: caret)
        return image
    }

    private static func describe(percent: Int, direction: MoveDirection?) -> String {
        let progress = "\(percent)% of goal"
        switch direction {
        case .up: return progress + ", up"
        case .down: return progress + ", down"
        case .flat, nil: return progress
        }
    }

    /// A solid triangle, pointing up for a gain and down for a loss.
    ///
    /// Deliberately not an SF Symbol: those come as template images that AppKit
    /// would tint to match the bar, which is the one thing this glyph must not do —
    /// its colour *is* the information.
    private static func drawCaret(
        _ direction: MoveDirection,
        at rect: NSRect,
        style: Style,
        isDarkBar: Bool
    ) {
        let path = NSBezierPath()
        if direction == .up {
            path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.move(to: NSPoint(x: rect.midX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        }
        path.close()
        caretColor(direction, style: style, isDarkBar: isDarkBar).setFill()
        path.fill()
    }

    /// Contrast picked the same way the digits pick theirs: the bright brand tone
    /// on a dark bar would vanish on a light one, and vice versa.
    ///
    /// The template style is the exception — it must stay monochrome, so the caret
    /// carries direction by its shape alone and lets AppKit tint it.
    private static func caretColor(_ direction: MoveDirection, style: Style, isDarkBar: Bool) -> NSColor {
        guard style != .template else { return .black }
        switch direction {
        case .up:
            return isDarkBar ? Theme.Brand.mint : Theme.Brand.deep
        case .down:
            return isDarkBar
                ? NSColor(srgbRed: 1.00, green: 0.45, blue: 0.42, alpha: 1)
                : NSColor(srgbRed: 0.76, green: 0.14, blue: 0.11, alpha: 1)
        case .flat:
            return .clear
        }
    }

    // MARK: - Style pieces

    private static func drawPlate(_ rect: NSRect) {
        let shape = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.width * 0.2237,
            yRadius: rect.width * 0.2237
        )
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(
            starting: NSColor(srgbRed: 0.10, green: 0.27, blue: 0.25, alpha: 1),
            ending: NSColor(srgbRed: 0.01, green: 0.05, blue: 0.05, alpha: 1)
        )?.draw(in: rect, angle: -68)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// AppKit cannot stroke with a gradient, so take the stroke's own outline and
    /// fill a gradient through it.
    private static func fillGradient(alongStrokeOf path: NSBezierPath, width: CGFloat, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let outline = path.cgPath.copy(
            strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 0
        )
        NSGraphicsContext.saveGraphicsState()
        context.addPath(outline)
        context.clip()
        NSGradient(starting: brandLight, ending: brandDeep)?.draw(in: rect, angle: -55)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func trackColor(style: Style, isDarkBar: Bool) -> NSColor {
        switch style {
        case .template:
            return NSColor.black.withAlphaComponent(0.28)
        case .plate:
            return NSColor.white.withAlphaComponent(0.16)
        case .brand:
            return (isDarkBar ? NSColor.white : NSColor.black).withAlphaComponent(0.22)
        }
    }

    private static func digitColor(style: Style, isDarkBar: Bool) -> NSColor {
        switch style {
        case .template:
            return .black
        case .plate:
            return .white
        case .brand:
            // On a light bar white digits would vanish; use the darkest brand tone.
            return isDarkBar ? .white : NSColor(srgbRed: 0.04, green: 0.30, blue: 0.22, alpha: 1)
        }
    }

    /// Diagnostic used by `--icons`: how wide the inner text is versus the space
    /// inside the ring.
    ///
    /// Exists because a 20pt glyph cannot be judged by eye from a magnified
    /// screenshot — magnification blur reads as collisions that are not there.
    /// The bound reported is the square inscribed in the ring's opening, which is
    /// conservative: centred text is widest at mid-height, where the full inner
    /// diameter is available.
    static func innerFill(percent: Int) -> (text: String, width: CGFloat, available: CGFloat) {
        let text = percent >= 100 ? "✓" : String(percent)
        let width = NSAttributedString(
            string: text,
            attributes: [.font: innerFont(digits: text.count)]
        ).size().width
        // The usable box is the square inscribed in the ring's opening, whose
        // side is the inner diameter divided by √2.
        let innerDiameter = side - 2 * lineWidth
        return (text, width, innerDiameter / 2.0.squareRoot())
    }

    /// Inner numerals: rounded and bold, stepped down for two digits so they
    /// stay clear of the stroke. `--icons` prints the resulting fit ratio.
    private static func innerFont(digits: Int, scaledTo scale: CGFloat = 1) -> NSFont {
        let size: CGFloat = (digits >= 2 ? 7.5 : 9.5) * scale
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Shown when the portfolio cannot be read.
    static func warning() -> NSImage {
        symbol("exclamationmark.triangle", description: "Cannot read portfolio")
    }

    /// Shown before a goal has been set.
    ///
    /// A dashed circle rather than a bullseye: it belongs to the same family as
    /// the progress ring and reads as "not set yet", where the much denser
    /// bullseye glyph looked like a different icon altogether.
    static func unset() -> NSImage {
        symbol("circle.dashed", description: "No goal set")
    }

    private static func symbol(_ name: String, description: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
            ?? NSImage(size: NSSize(width: side, height: side))
        image.isTemplate = true
        return image
    }
}
