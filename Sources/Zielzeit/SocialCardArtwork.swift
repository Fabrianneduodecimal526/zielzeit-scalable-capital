import AppKit
import ZielzeitCore

/// The GitHub social preview card, drawn rather than designed in an image editor
/// for the same reason the app icon is: it stays in step with the palette, and
/// regenerating it after a change is one command.
///
/// **This is the only place in the app that holds display text outside `Strings`,
/// and deliberately.** The card is a documentation artifact rather than UI: it is
/// baked into a PNG uploaded once to a repository setting, so there is no reader
/// whose language it could follow, and the repository it describes is English.
/// Same reasoning as the sample year `--menubar` draws.
@MainActor
enum SocialCardArtwork {

    /// GitHub's recommended size, and the aspect every unfurler crops toward.
    /// Every coordinate below is in these points; `scale` decides the pixels.
    static let size = NSSize(width: 1280, height: 640)

    private static let title = "Zielzeit"
    private static let tagline = "When will my portfolio reach my goal?"
    private static let footer = "macOS menu bar · Scalable Capital · read-only · open source"

    // Shared with the app icon and the menu bar ring via `Theme.Brand`.
    private static let backgroundTop = NSColor(srgbRed: 0.10, green: 0.27, blue: 0.25, alpha: 1)
    private static let backgroundBottom = NSColor(srgbRed: 0.01, green: 0.05, blue: 0.05, alpha: 1)

    /// Renders the card, drawn at `supersample ×` and resolved down to 1280×640.
    ///
    /// **The output stays 1280×640, and that is the considered answer rather than the
    /// default one.** It is tempting to publish 2560×1280 and call it higher quality,
    /// and it is worse on both counts: unfurlers lay these cards out at roughly 500–600
    /// CSS pixels, so 1280 device pixels is already the 2× source that renders
    /// pixel-exact on a Retina display — the same arithmetic the README screenshots
    /// follow. Everything past that is resampled away, and a 2560-wide PNG of this
    /// gradient comes out near 3MB, over GitHub's 1MB ceiling, where the rejection is
    /// a silent fall back to the automatic card.
    ///
    /// What supersampling *does* buy is the drawing: the arc's round terminals, the
    /// glow falloff and the vignette are all computed at 3× and box-filtered down, so
    /// the gradients resolve without the stepping a flat 1× pass leaves on a curve
    /// this large. Quality in the sampling, not in the dimensions.
    static func rep(supersample: Int = 3) -> NSBitmapImageRep? {
        guard let drawn = draw(scale: supersample) else { return nil }
        guard supersample > 1 else { return drawn }

        // Resolve down. `.high` interpolation is what makes this a filtered downsample
        // rather than a nearest-neighbour decimation that would undo the whole point.
        let source = NSImage(size: size)
        source.addRepresentation(drawn)

        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        output.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return output
    }

    private static func draw(scale: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        // Point size against a larger pixel count is what asks AppKit to draw
        // magnified, so every coordinate below stays in points.
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        let canvas = NSRect(origin: .zero, size: size)
        drawBackground(canvas)
        // Behind the text, so the headline stays the first thing read.
        drawRing(canvas)
        // After the ring, so the corners darken over it too and the ring recedes
        // where it leaves the frame instead of stopping dead at the edge.
        drawVignette(canvas)
        drawText(canvas, scale: scale)

        return rep
    }

    // MARK: - Background

    private static func drawBackground(_ canvas: NSRect) {
        NSGradient(starting: backgroundTop, ending: backgroundBottom)?.draw(in: canvas, angle: -68)

        // Sheen from above, the same linear-not-radial choice the icon makes: an
        // oval whose bounds fall inside the canvas leaves its own edge visible.
        let sheen = NSRect(x: 0, y: canvas.midY, width: canvas.width, height: canvas.height / 2)
        NSGradient(
            starting: NSColor.white.withAlphaComponent(0),
            ending: NSColor.white.withAlphaComponent(0.10)
        )?.draw(in: sheen, angle: 90)
    }

    /// Darkens the corners. Two jobs: it lifts the headline off the background
    /// without having to brighten the text, and it stops the ring from ending
    /// abruptly at the right edge — a bled shape that fades reads as continuing
    /// past the frame, one that keeps full brightness reads as cropped.
    private static func drawVignette(_ canvas: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Radial, and unlike the icon's sheen that is safe here: the gradient is
        // centred on the canvas and its outer circle encloses every corner, so no
        // edge of its own falls inside the artwork.
        let centre = CGPoint(x: canvas.midX, y: canvas.midY)
        let outer = hypot(canvas.width, canvas.height) / 2
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor.black.withAlphaComponent(0).cgColor,
                // Restrained on purpose: pushed further it greys the plate's emerald
                // and puts a visible grey cast across the white centre dot, which
                // reads as a dirty render rather than as depth.
                NSColor.black.withAlphaComponent(0.26).cgColor,
            ] as CFArray,
            locations: [0.58, 1]
        ) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: outer,
            options: []
        )
    }

    // MARK: - Ring

    /// The icon's mark, enlarged and bled off the right edge so it reads as the
    /// card's texture rather than as a second logo competing with the headline.
    private static func drawRing(_ canvas: NSRect) {
        let centre = NSPoint(x: 1_070, y: 316)
        let radius: CGFloat = 236
        let lineWidth: CGFloat = 46

        let track = NSBezierPath(ovalIn: NSRect(
            x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2
        ))
        track.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.07).setStroke()
        track.stroke()

        // Clockwise from twelve o'clock with a gap at the top, exactly as the icon.
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: centre, radius: radius,
            startAngle: 90, endAngle: 90 - 292, clockwise: true
        )

        // AppKit cannot stroke with a gradient, so take the outline of the stroke —
        // round caps included — and clip the gradient to that.
        let outline = arc.cgPath.copy(
            strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0
        )
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = Theme.Brand.deep.withAlphaComponent(0.55)
        glow.shadowBlurRadius = 60
        glow.shadowOffset = .zero
        glow.set()
        context.addPath(outline)
        context.setFillColor(Theme.Brand.deep.cgColor)
        context.fillPath()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        context.addPath(outline)
        context.clip()
        NSGradient(starting: Theme.Brand.mint, ending: Theme.Brand.deep)?
            .draw(in: canvas, angle: -55)
        NSGraphicsContext.restoreGraphicsState()

        // The target's centre — "Ziel". Held to the icon's dot-to-ring proportion
        // (0.25) rather than sized by eye, so the mark stays recognisably the same
        // one at 24pt in the Dock and at 236pt here. Its glow is dialled back from
        // the icon's: at this radius the icon's setting blooms into the track and
        // the whole centre reads as one white blob.
        let dotRadius: CGFloat = radius * 0.25
        NSGraphicsContext.saveGraphicsState()
        let dotGlow = NSShadow()
        dotGlow.shadowColor = Theme.Brand.mint.withAlphaComponent(0.35)
        dotGlow.shadowBlurRadius = 26
        dotGlow.shadowOffset = .zero
        dotGlow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: centre.x - dotRadius, y: centre.y - dotRadius,
            width: dotRadius * 2, height: dotRadius * 2
        )).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Text

    private static func drawText(_ canvas: NSRect, scale: Int) {
        let margin: CGFloat = 84
        // Stops short of the ring, so a wrapped tagline never runs into it.
        let column: CGFloat = 700
        // A cursor walking down from the top, because `draw(in:)` lays text out from
        // the top of its rect and stacking by hand is where the spacing bugs live.
        // The start point centres the whole block: 124 + 8 + 56 + 44 + 88 + 40 + 34
        // is 394 tall, so 123 of margin above and below it.
        var top = canvas.height - 123

        func place(_ text: NSAttributedString, height: CGFloat, gap: CGFloat) {
            text.draw(in: NSRect(x: margin, y: top - height, width: column, height: height))
            top -= height + gap
        }

        // Negative tracking on the headline only. The system font's default spacing is
        // set for reading sizes; at 104pt it leaves the word looking loosely spelt
        // out. The tagline is at a reading size and gets the default.
        place(
            string(title, size: 104, weight: .heavy, alpha: 1, tracking: -3),
            height: 124, gap: 8
        )
        place(
            string(tagline, size: 40, weight: .regular, alpha: 0.86),
            height: 56, gap: 44
        )

        // The real status item, at the size it is legible in a thumbnail. Drawn
        // through `RenderMode.menuBarItem` so the card cannot show a pill the app
        // does not draw.
        //
        // The pill is magnified `4 × scale`, not 4: it is a bitmap being composited
        // into this one, so at 1× the card's supersampling it would be the only
        // element resolved at half resolution — the exact softness the rest of this
        // artwork pays file size to avoid. Drawn back down to 4× in points.
        if let rep = RenderMode.menuBarItem(dark: true, scale: 4 * scale) {
            let pill = NSImage(size: NSSize(
                width: rep.pixelsWide / scale, height: rep.pixelsHigh / scale
            ))
            pill.addRepresentation(rep)
            let box = NSRect(
                x: margin, y: top - pill.size.height,
                width: pill.size.width, height: pill.size.height
            )
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).addClip()
            pill.draw(in: box)
            NSGraphicsContext.restoreGraphicsState()
            top -= pill.size.height + 40
        }

        place(
            string(footer, size: 25, weight: .medium, alpha: 0.52, tracking: 0.4),
            height: 34, gap: 0
        )
    }

    private static func string(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat,
        tracking: CGFloat = 0
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .kern: tracking,
        ])
    }
}
