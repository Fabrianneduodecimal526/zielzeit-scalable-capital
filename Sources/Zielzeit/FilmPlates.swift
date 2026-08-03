import AppKit
import ZielzeitCore

/// Stage 1 of `make film`: the real UI captures the compositor draws from.
///
/// **Why the film is two stages at all.** `RenderMode.capture` hosts the popover
/// in a real offscreen window and waits 1.5 seconds for layout to settle, and it
/// has to: `ImageRenderer` cannot rasterize the AppKit-backed sliders, and a
/// capture taken before SwiftUI's chart transition finishes writes out a curve
/// frozen between two shapes. At 30fps a 25-second film is 750 frames, which
/// captured that way is about nineteen minutes — a target nobody runs twice.
///
/// So the slow, faithful part is bounded to 50 plates (~75 seconds) and the 750
/// frames are composited from them in Core Graphics, where there is no layout to
/// settle. The film cannot show a popover the screenshots would not, because the
/// plates come from the same code path they do.
@MainActor
enum FilmPlates {

    /// Chosen against the cut, not picked round: the sweep scene runs 4.5s ≈ 135
    /// frames, so 48 plates hold ~2.8 frames each ≈ 11fps of moving content.
    /// `demo.gif` already reads acceptably at roughly half that.
    static let sweepCount = 48

    static func capture(into directory: String, dark: Bool, scale: Int) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let base = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            complain("Could not create \(directory): \(error.localizedDescription)")
            return 1
        }

        // Built once purely to read the ceiling the sweep runs to, exactly as
        // `RenderMode.demo` does; every plate gets its own model.
        guard case .success(let probe) = DevState.model(named: "ready"),
              case .ready(let report) = probe.state else {
            complain("The film needs a ready report. Pass ZIELZEIT_GOAL and ZIELZEIT_SC_BIN.")
            return 1
        }
        let ceiling = report.extraSavingsCeiling

        var written = 0
        for index in 0..<sweepCount {
            let value = ceiling * Double(index) / Double(sweepCount - 1)
            guard case .success(let model) = DevState.model(named: "ready") else {
                complain("Could not build plate \(index).")
                return 1
            }
            model.extraSavings = value
            guard let image = RenderMode.capture(model, dark: dark, scale: scale) else {
                complain("Could not capture plate \(index).")
                return 1
            }
            let name = String(format: "popover-%02d.png", index)
            guard write(image, to: base.appendingPathComponent(name)) else { return 1 }
            written += 1
            // Progress, because this takes about eighty seconds and a silent
            // eighty seconds reads as a hang.
            FileHandle.standardError.write(Data("  plate \(written)/\(sweepCount)\r".utf8))
        }

        // One, and only one. A flat-caret plate was specified and cut because the
        // film never shows one (`--icons` is where the caret's three directions are
        // judged). A second "2030" plate was then also cut, for a better reason: the
        // sweep scene used it to move the menu bar's year with the slider, which the
        // app does not do and `ReportTests` guards against. An unused plate is a
        // capture paid for nothing; a *misused* one is a promo that overclaims.
        let bars: [(String, Double, MoveDirection?, String)] = [
            ("menubar-2033.png", 0.17, .up, "2033"),
        ]
        for (name, progress, direction, year) in bars {
            guard let rep = RenderMode.menuBarItem(
                dark: dark, scale: scale, progress: progress, direction: direction, year: year
            ), let png = rep.representation(using: .png, properties: [:]) else {
                complain("Could not render \(name).")
                return 1
            }
            do {
                try png.write(to: base.appendingPathComponent(name))
            } catch {
                complain("Could not write \(name): \(error.localizedDescription)")
                return 1
            }
            written += 1
        }

        // Stated rather than assumed: a missing plate composites as a held frame,
        // which looks like a directing choice instead of an error.
        let expected = sweepCount + bars.count
        guard written == expected else {
            complain("Wrote \(written) plates, expected \(expected).")
            return 1
        }

        print("Wrote \(written) plates → \(directory)  (\(sweepCount) popover @\(scale)×, \(bars.count) menu bar)")
        return 0
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            complain("Could not encode \(url.lastPathComponent).")
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            complain("Could not write \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    private static func complain(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
