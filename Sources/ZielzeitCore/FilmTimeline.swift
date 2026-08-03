import Foundation

/// The promo film's cut, as arithmetic.
///
/// This is here rather than beside the drawing for the reason every other number
/// in this package is: it is the part that can be wrong invisibly. A scene
/// boundary off by one frame shows as a caption that flashes once or a plate held
/// twice, and neither is findable by watching a 25-second video. `FilmArtwork` in
/// the app target owns the pixels and the caption copy; this owns *when*.
///
/// It holds no text, no colours and no sizes, so `ZielzeitCore` stays free of
/// AppKit and of display strings outside `Strings`.
public enum FilmTimeline {

    public static let fps = 30
    public static let duration: Double = 25.0
    public static var frameCount: Int { Int((duration * Double(fps)).rounded()) }

    public enum Scene: String {
        case title, approach, menuBar, popoverOpen, chartPan, sweep, safety, endCard
    }

    /// Scene boundaries in seconds. Contiguous by construction: each entry's
    /// length is listed and the starts are accumulated, so a gap or an overlap
    /// cannot be introduced by editing one number.
    private static let lengths: [(scene: Scene, length: Double)] = [
        (.title, 2.8),
        (.approach, 3.7),
        (.menuBar, 3.0),
        (.popoverOpen, 3.0),
        (.chartPan, 3.5),
        (.sweep, 4.5),
        (.safety, 3.0),
        (.endCard, 1.5),
    ]

    public static let scenes: [(scene: Scene, start: Double, end: Double)] = {
        var start = 0.0
        return lengths.map { entry in
            let span = (scene: entry.scene, start: start, end: start + entry.length)
            start += entry.length
            return span
        }
    }()

    public static func time(ofFrame frame: Int) -> Double {
        Double(frame) / Double(fps)
    }

    public static func scene(atFrame frame: Int) -> Scene {
        let t = time(ofFrame: frame)
        // The last scene wins the final boundary, so frameCount-1 is not off the end.
        return scenes.last { t >= $0.start }?.scene ?? .title
    }

    public static func span(of scene: Scene) -> (start: Double, end: Double) {
        guard let found = scenes.first(where: { $0.scene == scene }) else { return (0, 0) }
        return (found.start, found.end)
    }

    /// Where this frame sits inside its own scene, 0…1.
    public static func progress(atFrame frame: Int) -> Double {
        let bounds = span(of: scene(atFrame: frame))
        let length = bounds.end - bounds.start
        guard length > 0 else { return 0 }
        return min(1, max(0, (time(ofFrame: frame) - bounds.start) / length))
    }

    /// Smoothstep. Pinned at 0 and 1 and symmetric about 0.5, so a move starts
    /// and stops without the mechanical feel of a linear ramp.
    public static func eased(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// Opacity for something that fades in at the head of its scene and out at
    /// the tail. Held fully opaque between the two.
    public static func fade(atFrame frame: Int, in rise: Double, out fall: Double) -> Double {
        let bounds = span(of: scene(atFrame: frame))
        let elapsed = time(ofFrame: frame) - bounds.start
        let remaining = bounds.end - time(ofFrame: frame)
        let rising = rise > 0 ? eased(elapsed / rise) : 1
        let falling = fall > 0 ? eased(remaining / fall) : 1
        return min(rising, falling)
    }

    /// Which sweep plate this frame shows, ping-ponging out to the last plate and
    /// back so the film can be watched twice without a jump cut — the same choice
    /// `RenderMode.demo` makes for `demo.gif`, for the same reason.
    public static func sweepPlate(atFrame frame: Int, plateCount: Int) -> Int {
        guard plateCount > 1 else { return 0 }
        let bounds = span(of: .sweep)
        let length = bounds.end - bounds.start
        guard length > 0 else { return 0 }
        let t = min(1, max(0, (time(ofFrame: frame) - bounds.start) / length))
        // Triangle wave: 0 → 1 → 0 across the scene.
        let triangle = t <= 0.5 ? t * 2 : (1 - t) * 2
        let index = Int((triangle * Double(plateCount - 1)).rounded())
        return min(plateCount - 1, max(0, index))
    }
}
