import AppKit

/// The app icon, drawn rather than shipped as a PNG so it stays crisp at every
/// size and can be tuned in one place.
///
/// The mark is a target — "Ziel" is German for *target* — rendered as the same
/// progress ring the menu bar uses, so the icon and the running app share a
/// glyph. A near-black squircle with a luminous ring reads well next to
/// colourful icons in the Dock and stays legible down to 16pt, where saturated
/// mid-tone icons turn to mud.
enum AppIconArtwork {

    /// Sizes an `.iconset` needs, as (point size, scale).
    static let iconSetSizes: [(points: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
    ]

    // MARK: - Palette

    private static let backgroundTop = NSColor(srgbRed: 0.10, green: 0.27, blue: 0.25, alpha: 1)
    private static let backgroundBottom = NSColor(srgbRed: 0.01, green: 0.05, blue: 0.05, alpha: 1)
    // Shared with the menu bar ring and the popover via `Theme.Brand`.
    private static let arcStart = Theme.Brand.mint
    private static let arcEnd = Theme.Brand.deep

    /// Draws the icon into a bitmap `pixels` wide and tall.
    static func image(pixels: Int) -> NSImage {
        let side = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current else { return image }
        context.imageInterpolation = .high

        // macOS icons sit inside their canvas rather than filling it.
        let inset = side * 0.055
        let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        // Apple's squircle corner radius is a fixed fraction of the plate.
        let radius = plate.width * 0.2237

        // Below this, fine detail turns to mud and only the bold shapes survive.
        let isSmall = side <= 32

        drawPlate(plate, radius: radius, side: side, detailed: !isSmall)
        drawRing(in: plate, side: side, detailed: !isSmall)

        return image
    }

    // MARK: - Plate

    private static func drawPlate(_ plate: NSRect, radius: CGFloat, side: CGFloat, detailed: Bool) {
        let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        if detailed {
            // Grounding shadow, so the plate sits on the desktop rather than
            // floating on it.
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = side * 0.03
            shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
            shadow.set()
        }
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()

        NSGradient(starting: backgroundTop, ending: backgroundBottom)?
            .draw(in: plate, angle: -68)

        if detailed {
            // Sheen from above, the light source Apple's icons assume.
            //
            // Linear rather than a radial oval: an oval whose bounds fall inside
            // the plate leaves its own edge visible as a crescent across the
            // artwork, which reads as a rendering artifact rather than as light.
            let sheen = NSRect(
                x: plate.minX,
                y: plate.midY,
                width: plate.width,
                height: plate.height / 2
            )
            NSGradient(
                starting: NSColor.white.withAlphaComponent(0),
                ending: NSColor.white.withAlphaComponent(0.15)
            )?.draw(in: sheen, angle: 90)
        }
        NSGraphicsContext.restoreGraphicsState()

        if detailed {
            // Crisp lit edge.
            NSGraphicsContext.saveGraphicsState()
            let edge = NSBezierPath(
                roundedRect: plate.insetBy(dx: side * 0.004, dy: side * 0.004),
                xRadius: radius, yRadius: radius
            )
            edge.lineWidth = side * 0.008
            NSColor.white.withAlphaComponent(0.13).setStroke()
            edge.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - Ring

    private static func drawRing(in plate: NSRect, side: CGFloat, detailed: Bool) {
        let centre = NSPoint(x: plate.midX, y: plate.midY)
        let radius = plate.width * (detailed ? 0.285 : 0.30)
        let lineWidth = plate.width * (detailed ? 0.105 : 0.135)

        // The unfilled remainder, so the ring reads as progress rather than as a
        // plain circle. Dropped at small sizes where it only adds noise.
        if detailed {
            let track = NSBezierPath(
                ovalIn: NSRect(
                    x: centre.x - radius, y: centre.y - radius,
                    width: radius * 2, height: radius * 2
                )
            )
            track.lineWidth = lineWidth
            NSColor.white.withAlphaComponent(0.11).setStroke()
            track.stroke()
        }

        // Progress arc: clockwise from twelve o'clock, leaving a gap at the top.
        let sweep: CGFloat = detailed ? 292 : 300
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: centre,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - sweep,
            clockwise: true
        )

        // AppKit cannot stroke with a gradient, and clipping to a path clips its
        // *fill*, not its stroke. So take the outline of the stroke as its own
        // shape — round caps included — and both fill and clip against that.
        let outline = arc.cgPath.copy(
            strokingWithWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0
        )

        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }

        if detailed {
            // Glow, laid down by filling the outline flat.
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = arcEnd.withAlphaComponent(0.75)
            glow.shadowBlurRadius = side * 0.045
            glow.shadowOffset = .zero
            glow.set()
            cgContext.addPath(outline)
            cgContext.setFillColor(arcEnd.cgColor)
            cgContext.fillPath()
            NSGraphicsContext.restoreGraphicsState()

            // Then the gradient, clipped to the same outline.
            NSGraphicsContext.saveGraphicsState()
            cgContext.addPath(outline)
            cgContext.clip()
            NSGradient(starting: arcStart, ending: arcEnd)?.draw(in: plate, angle: -55)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGraphicsContext.saveGraphicsState()
            cgContext.addPath(outline)
            cgContext.setFillColor(arcStart.cgColor)
            cgContext.fillPath()
            NSGraphicsContext.restoreGraphicsState()
        }

        // The target's centre — "Ziel".
        let dotRadius = plate.width * (detailed ? 0.072 : 0.085)
        let dot = NSBezierPath(ovalIn: NSRect(
            x: centre.x - dotRadius, y: centre.y - dotRadius,
            width: dotRadius * 2, height: dotRadius * 2
        ))
        NSGraphicsContext.saveGraphicsState()
        if detailed {
            let glow = NSShadow()
            glow.shadowColor = arcStart.withAlphaComponent(0.6)
            glow.shadowBlurRadius = side * 0.03
            glow.shadowOffset = .zero
            glow.set()
        }
        NSColor.white.setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
