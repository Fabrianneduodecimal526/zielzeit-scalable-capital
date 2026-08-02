import AppKit
import SwiftUI
import ZielzeitCore

/// Owns the menu bar item and the popover it presents.
///
/// All state lives in `AppModel` and all arithmetic in `ZielzeitCore`, leaving
/// this type responsible only for AppKit wiring.
@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate {

    private let model: AppModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var refreshTimer: Timer?

    /// Development flag (`--open`): present the popover on launch so the real
    /// thing — AppKit controls, popover material and all — can be screenshotted
    /// without a click that scripts are not permitted to make.
    var opensOnLaunch = false

    init(model: AppModel? = nil) {
        // Constructed here rather than as a default argument: `AppModel` is main
        // actor-isolated and default arguments are evaluated outside that context.
        self.model = model ?? AppModel()
        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // Right-click needs to reach the same handler so the fallback menu works.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        let hosting = NSHostingController(
            rootView: PopoverView(model: model, onQuit: { NSApp.terminate(nil) })
        )
        // Without this the popover keeps a default size: the content gets
        // centred inside it and the bottom is clipped. Publishing the preferred
        // size lets the popover track the content, including when it changes
        // height (goal editor, error state).
        hosting.sizingOptions = [.preferredContentSize]

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
        self.popover = popover

        observeTitle()
        observeAppearance()
        observeWake()

        // A model handed in already carrying state (development `--open`) must
        // not have it overwritten by a fetch.
        if model.hasGoal, case .loading = model.state {
            model.refresh()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: AppModel.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }

        if opensOnLaunch {
            // Give the status item a beat to acquire its position, otherwise the
            // popover has nothing to anchor to.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    // MARK: - Menu bar appearance

    /// Keeps the icon and title in step with the model.
    ///
    /// `withObservationTracking` fires once per change, so it re-arms itself
    /// after every update.
    private func observeTitle() {
        withObservationTracking {
            _ = model.state.menuBarText
            _ = model.state.iconProgress
            // Tracked as well, or the caret keeps the previous refresh's direction
            // whenever a fetch moves the market but not the year or the percentage —
            // which is most of them.
            _ = model.state.menuBarDirection
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusItem()
                self.observeTitle()
            }
        }
        updateStatusItem()
    }

    /// Redraws the icon when the system switches between light and dark.
    ///
    /// A template image would not need this — AppKit retints those itself — but
    /// the brand ring is a colour image and has to be redrawn for the new bar.
    private func observeAppearance() {
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification arrives before `effectiveAppearance` catches up,
            // so read it a beat later or the icon redraws for the old theme.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.updateStatusItem()
            }
        }
    }

    /// Re-fetches after the Mac wakes from sleep.
    ///
    /// The hourly timer does fire on wake, but it fires immediately — before the
    /// network is back — so on its own it only produces a failed fetch. This
    /// gives the connection a few seconds first; `AppModel`'s backoff covers a
    /// wake that takes longer than that.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                Task { @MainActor in self?.model.refresh() }
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let state = model.state

        if let progress = state.iconProgress {
            // The brand ring is a colour image, so it cannot be tinted by AppKit
            // and has to pick its own contrast from the bar's appearance.
            let isDarkBar = button.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            button.image = StatusItemIcon.ring(
                progress: progress,
                direction: state.menuBarDirection,
                style: .brand,
                isDarkBar: isDarkBar
            )
        } else if case .failure = state {
            button.image = StatusItemIcon.warning()
        } else {
            // Not connected yet.
            button.image = StatusItemIcon.unset()
        }

        let text = state.menuBarText
        // A leading space separates the glyph from the text; AppKit does not
        // inset them from each other.
        button.title = text.isEmpty ? "" : " \(text)"
        // No tooltip: the ring and the year already say everything it said, so
        // hovering only produced a redundant label. `statusTitle` still backs
        // `--once`.
        button.toolTip = nil
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return togglePopover() }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showFallbackMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        model.refreshIfStale()
        // An accessory app must activate before the popover will accept
        // keyboard input — without this the goal field cannot be typed into.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Right-click menu, so quitting never depends on the popover rendering.
    private func showFallbackMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: Strings.setGoalEllipsis, action: #selector(setGoal), keyEquivalent: "").target = self
        menu.addItem(withTitle: Strings.refreshNow, action: #selector(refresh), keyEquivalent: "").target = self
        if LaunchAtLogin.isSupported {
            let item = menu.addItem(withTitle: Strings.launchAtLogin, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            item.target = self
            item.state = LaunchAtLogin.isEnabled ? .on : .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: Strings.quitZielzeit, action: #selector(quit), keyEquivalent: "q").target = self

        // Popped up directly rather than assigned to `statusItem.menu` and
        // clicked. A non-nil `statusItem.menu` makes AppKit swallow the button
        // action, so if the assign/click/unassign dance ever failed to unassign,
        // left-click would stop opening the popover permanently — and on an
        // LSUIElement app there is no ⌘Q to recover with.
        guard let button = statusItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func setGoal() {
        model.beginEditingGoal()
        togglePopover()
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.toggle()
        } catch {
            let alert = NSAlert()
            alert.messageText = Strings.couldNotChangeLoginItem
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
