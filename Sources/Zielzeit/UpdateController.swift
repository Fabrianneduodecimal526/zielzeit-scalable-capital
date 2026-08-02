import AppKit
import Sparkle

/// Sparkle lives behind this one type. Nothing else in the app imports Sparkle,
/// and `ZielzeitCore` never sees it at all: the updater is AppKit-backed, and
/// the core/UI split is what keeps the projection math testable.
///
/// Updates are silent by design — no "a new version is available" prompt. For a
/// menu bar app the reader deliberately does not look at, that dialog is an
/// interruption offering a decision they have no basis to make. The behaviour is
/// configured in Info.plist (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`)
/// rather than here, and disclosed in the footer menu rather than in a modal.
@MainActor
final class UpdateController {
    /// Nil until `start()` runs, and only the real app path in `main` calls it.
    ///
    /// That is the gate, rather than a flag somewhere that can be forgotten:
    /// `--once`, `--render`, `--shot`, `--icons`, `--appicon`, `--menubar` and `--open` all
    /// return before the app path is reached, so no updater is ever built and no
    /// request is ever made. It matters because `PopoverView` renders its footer
    /// under `--render` and `--shot`, so a view that constructed an updater on
    /// demand would have `make shots` and CI polling the appcast.
    static private(set) var shared: UpdateController?

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    static func start() {
        guard shared == nil else { return }
        shared = UpdateController()
    }

    /// The manual check from the footer menu, which shows Sparkle's standard UI
    /// including "you're up to date" — the one thing the silent path never says.
    /// It exists so the update channel can be poked at all: a feed that has
    /// silently stopped resolving is otherwise indistinguishable from being
    /// current, and this is the only way a reader can tell us which they are.
    ///
    /// The activate call is the same footgun the goal field already pays for: an
    /// accessory app's transient popover does not hold key focus, so a window
    /// opened from it comes up behind everything without this.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

/// Read straight from the bundle rather than through Sparkle, so the footer's
/// version line still renders in the capture modes, which have no app bundle and
/// no updater.
enum AppVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
