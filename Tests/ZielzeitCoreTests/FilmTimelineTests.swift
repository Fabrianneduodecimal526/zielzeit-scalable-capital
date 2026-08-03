import XCTest
@testable import ZielzeitCore

/// The film's cut. These are not decoration: an off-by-one at a scene boundary
/// shows as a caption that flashes for one frame or a plate held twice, and
/// neither is visible when reviewing a 25-second video by eye.
final class FilmTimelineTests: XCTestCase {

    func testDurationAndFrameCountAgree() {
        XCTAssertEqual(FilmTimeline.fps, 30)
        XCTAssertEqual(FilmTimeline.duration, 25.0, accuracy: 0.0001)
        XCTAssertEqual(FilmTimeline.frameCount, 750)
    }

    /// The scenes tile the whole duration with no gap and no overlap. A gap
    /// draws an empty frame; an overlap silently drops the later scene.
    func testScenesTileTheDuration() {
        let scenes = FilmTimeline.scenes
        XCTAssertEqual(scenes.first!.start, 0)
        XCTAssertEqual(scenes.last!.end, FilmTimeline.duration, accuracy: 0.0001)
        for (previous, next) in zip(scenes, scenes.dropFirst()) {
            XCTAssertEqual(previous.end, next.start, accuracy: 0.0001,
                           "\(previous.scene) ends where \(next.scene) begins")
            XCTAssertGreaterThan(previous.end, previous.start)
        }
    }

    func testEveryFrameResolvesToAScene() {
        for frame in 0..<FilmTimeline.frameCount {
            _ = FilmTimeline.scene(atFrame: frame)
        }
        XCTAssertEqual(FilmTimeline.scene(atFrame: 0), .title)
        XCTAssertEqual(FilmTimeline.scene(atFrame: FilmTimeline.frameCount - 1), .endCard)
    }

    /// The first frame of a scene is its start, not the tail of the one before.
    func testSceneBoundariesLandOnTheExpectedFrames() {
        XCTAssertEqual(FilmTimeline.scene(atFrame: 83), .title)      // t = 2.766
        XCTAssertEqual(FilmTimeline.scene(atFrame: 84), .approach)   // t = 2.800
        XCTAssertEqual(FilmTimeline.scene(atFrame: 479), .chartPan)  // t = 15.966, still chartPan
        XCTAssertEqual(FilmTimeline.scene(atFrame: 480), .sweep)     // t = 16.000
    }

    func testProgressRunsZeroToOneWithinEachScene() {
        XCTAssertEqual(FilmTimeline.progress(atFrame: 0), 0, accuracy: 0.0001)
        let last = FilmTimeline.frameCount - 1
        XCTAssertGreaterThan(FilmTimeline.progress(atFrame: last), 0.9)
        for frame in 0..<FilmTimeline.frameCount {
            let p = FilmTimeline.progress(atFrame: frame)
            XCTAssertTrue((0...1).contains(p), "frame \(frame) progress \(p)")
        }
    }

    func testEasingIsPinnedAtBothEnds() {
        XCTAssertEqual(FilmTimeline.eased(0), 0, accuracy: 0.0001)
        XCTAssertEqual(FilmTimeline.eased(1), 1, accuracy: 0.0001)
        XCTAssertEqual(FilmTimeline.eased(0.5), 0.5, accuracy: 0.0001)
        // Monotonic, or motion reverses mid-move.
        var previous = -1.0
        for step in 0...100 {
            let value = FilmTimeline.eased(Double(step) / 100)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    /// A caption fades in over `in` seconds and out over `out`, and is fully
    /// opaque in between. A scene shorter than in+out would never reach 1.
    func testCaptionFadeReachesFullOpacityAndReturns() {
        let scene = FilmTimeline.scenes.first { $0.scene == .menuBar }!
        let first = Int((scene.start * 30).rounded())
        let middle = Int(((scene.start + scene.end) / 2 * 30).rounded())
        let last = Int((scene.end * 30).rounded()) - 1
        XCTAssertEqual(FilmTimeline.fade(atFrame: first, in: 0.4, out: 0.4), 0, accuracy: 0.05)
        XCTAssertEqual(FilmTimeline.fade(atFrame: middle, in: 0.4, out: 0.4), 1, accuracy: 0.0001)
        XCTAssertEqual(FilmTimeline.fade(atFrame: last, in: 0.4, out: 0.4), 0, accuracy: 0.06)
    }

    /// The sweep walks the plates out and back, so the loop has no jump cut —
    /// the same ping-pong `RenderMode.demo` uses, and it must touch both ends.
    func testSweepPingPongsAcrossEveryPlate() {
        let scene = FilmTimeline.scenes.first { $0.scene == .sweep }!
        let frames = Int((scene.start * 30).rounded())..<Int((scene.end * 30).rounded())
        let indices = frames.map { FilmTimeline.sweepPlate(atFrame: $0, plateCount: 48) }
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.max(), 47)
        XCTAssertTrue(indices.allSatisfy { (0..<48).contains($0) })
        // Out then back: the maximum is reached somewhere in the middle, not at the end.
        let peak = indices.firstIndex(of: 47)!
        XCTAssertGreaterThan(peak, indices.count / 4)
        XCTAssertLessThan(peak, indices.count * 3 / 4)
        XCTAssertLessThan(indices.last!, 24)
    }
}
