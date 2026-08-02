import Foundation
import Observation
import ZielzeitCore

/// UI state shared between the status item and the popover.
///
/// Owns fetching and goal persistence; holds no AppKit and no arithmetic, so the
/// views observe one source of truth and `--render` can drive it directly.
@MainActor
@Observable
final class AppModel {

    /// How often the portfolio is re-fetched in the background.
    static let refreshInterval: TimeInterval = 3600

    /// Opening the popover refreshes only if the data is older than this.
    static let staleAfter: TimeInterval = 300

    var state: ViewState = .loading

    /// Extra monthly contribution being previewed by the slider.
    var extraSavings: Double = 0

    /// Target year for the "reach by" slider.
    ///
    /// A stored property rather than a value computed from the report on demand:
    /// a `Slider` bound to a computed get/set writes its own position back during
    /// layout, which lands the knob on an arbitrary year instead of the seeded
    /// one. `seedTargetYear(for:)` fills it in when a report arrives.
    var chosenTargetYear: Double = 0

    /// Window the market chip is showing. `nil` means the report's own default.
    ///
    /// Held as an override rather than seeded, so the chip follows
    /// `Report.initialWindow` until the reader actually chooses otherwise — and a
    /// payload that stops carrying the chosen window falls back rather than showing
    /// a blank chip.
    var marketWindow: ReturnWindow?

    /// The move currently on show, resolving the override against the report.
    func marketMove(for report: Report) -> MarketMove? {
        guard let window = marketWindow ?? report.initialWindow else { return nil }
        return report.move(in: window)
    }

    /// Advances the chip to the next window the payload carries.
    func cycleMarketWindow(for report: Report) {
        guard let current = marketWindow ?? report.initialWindow else { return }
        marketWindow = report.window(after: current)
    }

    /// Brings everything that depends on the report's bounds back into range.
    ///
    /// Called on every new report, because all three of these move with the data.
    private func align(to report: Report) {
        alignSliders(to: report)
        alignMarketWindow(to: report)
    }

    /// Brings both sliders into range whenever a new report arrives.
    ///
    /// Both bounds move with the data: the target-year range slides with the
    /// calendar, and `extraSavingsCeiling` shrinks as the portfolio grows (a
    /// shorter horizon needs less to halve). A `Slider` holding a value outside
    /// its range pins the knob at the end while the preview keeps computing from
    /// the stale number — the hero would show a year the slider cannot represent.
    private func alignSliders(to report: Report) {
        seedTargetYear(for: report)
        if extraSavings > report.extraSavingsCeiling {
            extraSavings = report.extraSavingsCeiling
        }
    }

    /// Drops a chosen window the new payload no longer reports, so the chip falls
    /// back to the default instead of vanishing. Same class of problem as a slider
    /// holding an out-of-range value.
    private func alignMarketWindow(to report: Report) {
        if let marketWindow, !report.availableWindows.contains(marketWindow) {
            self.marketWindow = nil
        }
    }

    /// Starts the slider at the projected arrival, so it opens showing roughly
    /// what is already being saved rather than an arbitrary year with an alarming
    /// figure beside it. Leaves a year the user has chosen alone unless the report
    /// has moved it out of range.
    private func seedTargetYear(for report: Report) {
        let range = report.targetYearRange
        if chosenTargetYear > 0, range.contains(Int(chosenTargetYear.rounded())) { return }
        if let year = report.headlineYear, range.contains(year) {
            chosenTargetYear = Double(year)
        } else {
            chosenTargetYear = Double(range.lowerBound)
        }
    }

    /// The chosen language, or `.system` to keep following the Mac.
    ///
    /// Observable so that changing it redraws everything: the strings themselves
    /// are plain computed values on `Strings` and have nothing to observe, so this
    /// property is what the popover and the status item watch. `PopoverView`
    /// hangs its `.id` on it and `StatusItemController.observeTitle` tracks it.
    var languagePreference: LanguagePreference {
        didSet {
            guard languagePreference != oldValue else { return }
            languageStore.setPreference(languagePreference)
            AppLanguage.current = languageStore.resolved
        }
    }

    var isEditingGoal = false
    var goalDraft = ""

    var lastFetch: Date?

    /// Why the most recent refresh failed, while a good report is still on
    /// screen. `nil` whenever the data on screen is current.
    var staleReason: String?

    /// Consecutive failed refreshes, driving `RefreshPolicy`'s backoff.
    private var failureCount = 0
    private var retryTask: Task<Void, Never>?

    /// Development only (`--open <state>` / `--render`): freezes the state so
    /// opening the popover does not immediately fetch over the top of it.
    var isPinned = false

    /// Development only (`--render caveats`): opens the disclaimer, which is
    /// otherwise collapsed and so unrenderable.
    var showsCaveats = false

    private let provider: PortfolioProviding
    private let prober: SetupProbing?
    private var goalStore: GoalStore
    private let setupStore: SetupStore
    private let languageStore: LanguageStore
    private var isFetching = false

    /// Once a session has proven itself, later refreshes skip the setup probe.
    ///
    /// Probing costs a `whoami` round-trip, and paying that on every hourly
    /// refresh would double the work for a state that almost never changes. If a
    /// fetch later fails on authentication, the probe runs again.
    private var isKnownConnected = false

    init(
        provider: PortfolioProviding = ScalableClient(),
        prober: SetupProbing? = ScalableClient(),
        goalStore: GoalStore = GoalStore(),
        setupStore: SetupStore = SetupStore(),
        languageStore: LanguageStore = LanguageStore(),
        state: ViewState? = nil
    ) {
        self.provider = provider
        self.prober = prober
        self.goalStore = goalStore
        self.setupStore = setupStore
        self.languageStore = languageStore
        // Read, not written: `main` has already resolved and applied the language
        // by the time a model exists, so this only mirrors it for the menu.
        self.languagePreference = languageStore.preference
        if let state {
            self.state = state
            // `--open`/`--render` hand a finished report straight in, bypassing
            // the fetch that would otherwise seed the slider.
            if case .ready(let report) = state { align(to: report) }
        } else {
            self.state = .loading
        }
    }

    /// When the broker struck the figures on screen, when it says.
    var valuationDate: Date? {
        guard case .ready(let report) = state else { return nil }
        return report.snapshot.valuationDate
    }

    var hasGoal: Bool { goalStore.goal != nil }
    var goal: Double? { goalStore.goal }

    /// Whether the data is old enough to be worth re-fetching.
    var isStale: Bool {
        lastFetch.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true
    }

    // MARK: - Actions

    func refreshIfStale() {
        guard isStale else { return }
        refresh()
    }

    func refresh() {
        guard !isPinned else { return }
        guard !isFetching else { return }
        retryTask?.cancel()
        retryTask = nil
        isFetching = true

        Task { [provider, prober] in
            // Setup is checked first: without a session there is nothing to
            // fetch, and "not connected" is a different problem from "the fetch
            // failed". Skipped once a session has proven itself.
            if let prober, !self.isKnownConnected {
                let setup = await Task.detached { prober.detectSetup() }.value
                guard setup.isConnected else {
                    self.isFetching = false
                    self.state = .setup(setup)
                    return
                }
                self.isKnownConnected = true
            }

            guard self.hasGoal else {
                self.isFetching = false
                self.state = .noGoal
                return
            }

            let outcome: Result<PortfolioSnapshot, Error>
            do {
                // The CLI call is blocking, so keep it off the main actor.
                let snapshot = try await Task.detached { try provider.fetchSnapshot() }.value
                outcome = .success(snapshot)
            } catch {
                outcome = .failure(error)
            }
            self.apply(outcome)
        }
    }

    /// Whether a failure means the session or install is gone, rather than the
    /// portfolio simply being unreadable right now.
    private func isSetupProblem(_ error: Error) -> Bool {
        switch error as? ScalableError {
        case .notLoggedIn, .notInstalled:
            return true
        default:
            return false
        }
    }

    /// Records that the allowlisting email has been sent, and re-probes.
    func markAccessRequested() {
        setupStore.hasRequestedAccess = true
        if case .setup(.notConnected(let code, _)) = state {
            state = .setup(.notConnected(installationCode: code, hasRequestedAccess: true))
        }
    }

    private func apply(_ outcome: Result<PortfolioSnapshot, Error>) {
        isFetching = false
        switch outcome {
        case .success(let snapshot):
            guard let goal = goalStore.goal else {
                state = .noGoal
                return
            }
            lastFetch = Date()
            failureCount = 0
            staleReason = nil
            let report = Report(goal: goal, snapshot: snapshot)
            align(to: report)
            state = .ready(report)
        case .failure(let error):
            // A session that has expired or a CLI that has been uninstalled is a
            // setup problem, not a read failure — send the user back to the steps
            // that fix it rather than showing a dead end.
            if isSetupProblem(error), let prober {
                isKnownConnected = false
                let setup = prober.detectSetup()
                if !setup.isConnected {
                    staleReason = nil
                    state = .setup(setup)
                    return
                }
            }
            // A transient failure must not throw away a perfectly good report.
            // The common one is waking from sleep: the missed hourly timer fires
            // before the network is back, and replacing the report with an error
            // means the menu bar loses its year and only a click brings it back.
            // The figures are kept, marked stale, and a retry restores them.
            if case .ready = state {
                staleReason = error.localizedDescription
            } else {
                state = .failure(error.localizedDescription)
            }
            scheduleRetry()
        }
    }

    /// Tries again after a failure, on `RefreshPolicy`'s backoff.
    private func scheduleRetry() {
        guard !isPinned else { return }
        guard let delay = RefreshPolicy.retryDelay(afterFailures: failureCount) else { return }
        failureCount += 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func beginEditingGoal() {
        goalDraft = goalStore.goal.map { String(format: "%.0f", $0) } ?? ""
        isEditingGoal = true
    }

    func cancelEditingGoal() {
        isEditingGoal = false
    }

    func saveGoal(_ amount: Double) {
        goalStore.setGoal(amount)
        isEditingGoal = false
        extraSavings = 0
        // A new goal invalidates the old target year's figure entirely.
        chosenTargetYear = 0

        // Recompute from the snapshot already in hand rather than re-fetching.
        if case .ready(let report) = state {
            let updated = Report(goal: amount, snapshot: report.snapshot)
            align(to: updated)
            state = .ready(updated)
        } else {
            state = .loading
            refresh()
        }
    }
}
