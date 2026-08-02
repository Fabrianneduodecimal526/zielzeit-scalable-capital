import Foundation

/// One projection scenario: a growth assumption and what it implies.
public struct Scenario: Equatable {
    public let label: String
    /// `nil` for the realized scenario when there is not enough history.
    public let annualRate: Double?
    /// Months until the goal; `nil` means it is never reached.
    public let months: Double?
    public let year: Int?

    public var isReachable: Bool { months != nil }
}

/// The effect of adding a fixed amount to the monthly contribution.
public struct WhatIf: Equatable {
    public let extraPerMonth: Double
    public let year: Int?
    /// Years shaved off the headline projection.
    public let yearsSaved: Double?
}

/// The complete view model: everything the UI shows, derived once from a
/// snapshot and a goal.
///
/// Deliberately free of AppKit so the entire display can be rendered as text
/// and asserted on in tests.
public struct Report {

    /// A deliberately conservative growth assumption.
    public static let cautiousRate = 0.03

    /// A long-run equity return, and the headline's fallback when the portfolio
    /// has no measurable pace of its own yet.
    public static let moderateRate = 0.06

    /// Scenario labels. Named rather than spelled out at each use site so the
    /// headline, the highlighted row and the emphasised curve cannot drift apart.
    public static let cautiousLabel = "Cautious"
    public static let moderateLabel = "Moderate"
    public static let realizedLabel = "Your pace"

    /// Extra monthly contributions offered as what-if rows.
    public static let whatIfIncrements: [Double] = [50, 100, 200]

    public let goal: Double
    public let snapshot: PortfolioSnapshot
    public let asOf: Date
    /// Retained so every date derived later — including the slider's continuous
    /// what-if — uses the same calendar the fixed scenarios did.
    public let calendar: Calendar

    /// Fraction of the goal already reached, capped at 1.
    public let progress: Double

    /// Trailing return implied by the past year, or `nil` if not derivable.
    public let realizedAnnualRate: Double?

    /// The rate the headline, the what-ifs and the slider all project with: the
    /// realized pace when there is one, otherwise the moderate assumption.
    public let headlineRate: Double

    /// Which scenario the headline came from, so the UI can highlight that row
    /// and emphasise that curve without hardcoding a label.
    public let headlineLabel: String

    public let headlineMonths: Double?
    public let headlineYear: Int?
    public let scenarios: [Scenario]
    public let whatIfs: [WhatIf]

    public var isGoalReached: Bool { snapshot.total >= goal }
    public var remaining: Double { max(goal - snapshot.total, 0) }

    public init(goal: Double, snapshot: PortfolioSnapshot, now: Date = Date(), calendar: Calendar = .current) {
        self.goal = goal
        self.snapshot = snapshot
        self.asOf = now
        self.calendar = calendar
        self.progress = goal > 0 ? min(snapshot.total / goal, 1) : 0

        let realized = Projection.realizedAnnualRate(
            total: snapshot.total,
            oneYearGain: snapshot.oneYearGain,
            monthlySavings: snapshot.monthlySavings,
            trailingContributions: snapshot.trailingContributions
        )
        self.realizedAnnualRate = realized

        // The headline follows the portfolio's own measured pace — the whole
        // point of the widget is that the year adapts to how the portfolio is
        // actually doing. The fallback turns on whether a rate could be measured
        // at all, never on whether the answer is flattering: a pace too poor to
        // reach the goal yields no year rather than borrowing the moderate one.
        let headlineRate = realized ?? Self.moderateRate
        self.headlineRate = headlineRate
        self.headlineLabel = realized == nil ? Self.moderateLabel : Self.realizedLabel

        let headline = Projection.monthsToGoal(
            value: snapshot.total,
            goal: goal,
            annualRate: headlineRate,
            monthlySavings: snapshot.monthlySavings,
            dynamizationRate: snapshot.dynamizationRate
        )
        self.headlineMonths = headline
        self.headlineYear = headline.map { Projection.arrivalYear(months: $0, from: now, calendar: calendar) }

        self.scenarios = [
            (Self.cautiousLabel, Self.cautiousRate),
            (Self.moderateLabel, Self.moderateRate),
            (Self.realizedLabel, realized),
        ].map { label, rate in
            Self.makeScenario(
                label: label,
                annualRate: rate,
                goal: goal,
                snapshot: snapshot,
                now: now,
                calendar: calendar
            )
        }

        self.whatIfs = Self.whatIfIncrements.map { extra in
            Self.makeWhatIf(
                extra: extra,
                goal: goal,
                snapshot: snapshot,
                annualRate: headlineRate,
                headlineMonths: headline,
                now: now,
                calendar: calendar
            )
        }
    }

    // MARK: - Derivation

    private static func makeScenario(
        label: String,
        annualRate: Double?,
        goal: Double,
        snapshot: PortfolioSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Scenario {
        guard let annualRate else {
            return Scenario(label: label, annualRate: nil, months: nil, year: nil)
        }
        let months = Projection.monthsToGoal(
            value: snapshot.total,
            goal: goal,
            annualRate: annualRate,
            monthlySavings: snapshot.monthlySavings,
            dynamizationRate: snapshot.dynamizationRate
        )
        return Scenario(
            label: label,
            annualRate: annualRate,
            months: months,
            year: months.map { Projection.arrivalYear(months: $0, from: now, calendar: calendar) }
        )
    }

    private static func makeWhatIf(
        extra: Double,
        goal: Double,
        snapshot: PortfolioSnapshot,
        annualRate: Double,
        headlineMonths: Double?,
        now: Date,
        calendar: Calendar
    ) -> WhatIf {
        // Must be the headline's own rate: comparing a what-if projected at one
        // rate against a headline projected at another would report time saved
        // that is really just the difference between the two assumptions.
        let months = Projection.monthsToGoal(
            value: snapshot.total,
            goal: goal,
            annualRate: annualRate,
            monthlySavings: snapshot.monthlySavings + extra,
            dynamizationRate: snapshot.dynamizationRate
        )
        var saved: Double?
        if let months, let headlineMonths {
            saved = (headlineMonths - months) / 12
        }
        return WhatIf(
            extraPerMonth: extra,
            year: months.map { Projection.arrivalYear(months: $0, from: now, calendar: calendar) },
            yearsSaved: saved
        )
    }

    // MARK: - Chart data

    /// A scenario's balance curve, ready to plot.
    public struct Curve: Identifiable {
        public let label: String
        public let annualRate: Double
        /// Monthly samples, ending on the goal line if the goal is reached.
        public let points: [Projection.BalancePoint]
        /// Months to the goal, `nil` if never reached within the horizon.
        public let arrivalMonths: Double?

        public var id: String { label }
        public var reachesGoal: Bool { arrivalMonths != nil }
    }

    /// How far the chart's x-axis runs, in months.
    ///
    /// Chosen so the slowest scenario that does arrive fits with a little room
    /// to spare; falls back to 40 years when nothing arrives at all.
    public func chartHorizonMonths(extraMonthlySavings: Double = 0) -> Int {
        let arrivals = scenarioRates.compactMap { rate in
            Projection.monthsToGoal(
                value: snapshot.total,
                goal: goal,
                annualRate: rate,
                monthlySavings: snapshot.monthlySavings + extraMonthlySavings,
                dynamizationRate: snapshot.dynamizationRate
            )
        }
        guard let slowest = arrivals.max() else { return 480 }
        return max(Int((slowest * 1.08).rounded(.up)), 12)
    }

    /// Balance curves for every scenario, each stopping at the goal line.
    ///
    /// Recomputing this is cheap arithmetic, so the what-if slider can call it
    /// on every drag.
    public func curves(extraMonthlySavings: Double = 0) -> [Curve] {
        let horizon = chartHorizonMonths(extraMonthlySavings: extraMonthlySavings)
        // Thin the samples on long horizons; ~120 points is plenty for a
        // smooth line at this width.
        let step = max(horizon / 120, 1)
        let savings = snapshot.monthlySavings + extraMonthlySavings

        return scenarios.compactMap { scenario -> Curve? in
            guard let annualRate = scenario.annualRate else { return nil }
            let monthlyRate = Projection.monthlyRate(annual: annualRate)
            let arrival = Projection.monthsToGoal(
                value: snapshot.total,
                goal: goal,
                monthlyRate: monthlyRate,
                monthlySavings: savings,
                dynamizationRate: snapshot.dynamizationRate
            )
            return Curve(
                label: scenario.label,
                annualRate: annualRate,
                points: Projection.balanceSeries(
                    value: snapshot.total,
                    monthlyRate: monthlyRate,
                    monthlySavings: savings,
                    months: horizon,
                    step: step,
                    ceiling: goal,
                    dynamizationRate: snapshot.dynamizationRate
                ),
                arrivalMonths: arrival
            )
        }
    }

    /// The rates actually plotted: the two fixed scenarios plus the realized one
    /// when it is derivable.
    private var scenarioRates: [Double] {
        scenarios.compactMap(\.annualRate)
    }

    /// Arrival for an arbitrary extra monthly contribution at the headline's own
    /// rate, so the previewed year is comparable with the one it replaces.
    public func arrival(
        extraMonthlySavings: Double
    ) -> (months: Double?, year: Int?, yearsSaved: Double?) {
        arrival(extraMonthlySavings: extraMonthlySavings, annualRate: headlineRate)
    }

    /// The same preview at an explicit rate, for `ScenarioListView`'s per-row
    /// years. Deliberately non-optional: a `nil` rate means "no year at all",
    /// and silently substituting the headline's rate would print a year on the
    /// row that is supposed to read `—`.
    ///
    /// The extra dynamizes along with the plan. Raising what you save here means
    /// raising the Scalable savings plan, and that raised amount carries the same
    /// annual step-up — treating the extra as a flat standing transfer instead
    /// would report slightly smaller savings.
    public func arrival(
        extraMonthlySavings: Double,
        annualRate: Double
    ) -> (months: Double?, year: Int?, yearsSaved: Double?) {
        let months = Projection.monthsToGoal(
            value: snapshot.total,
            goal: goal,
            annualRate: annualRate,
            monthlySavings: snapshot.monthlySavings + extraMonthlySavings,
            dynamizationRate: snapshot.dynamizationRate
        )
        var saved: Double?
        if let months, let headlineMonths {
            saved = (headlineMonths - months) / 12
        }
        return (
            months,
            months.map { Projection.arrivalYear(months: $0, from: asOf, calendar: calendar) },
            saved
        )
    }

    // MARK: - Purchasing power

    /// The goal amount restated in today's money, at the projected horizon.
    ///
    /// Always shown rather than hidden behind a toggle, and not because inflation is
    /// a caveat — it is the difference between the goal meaning what the user thinks
    /// it means and not. Over the horizons this app quotes it is the largest single
    /// distortion in the number, larger than anything the disclaimer lists, and a
    /// caveat behind a disclosure triangle is one nobody reads.
    ///
    /// `nil` when there is no arrival to discount to, or when the horizon is so short
    /// that the restatement would be the same figure.
    public var realGoalValue: Double? {
        guard let months = headlineMonths, months >= 12 else { return nil }
        return Projection.realValue(nominal: goal, months: months)
    }

    // MARK: - Market movement

    /// The window the chip and the menu bar arrow open on.
    ///
    /// One week rather than intraday, which was the more obvious choice and the
    /// wrong one: `INTRADAY` is frozen from Friday's close until Monday's open, so
    /// the liveliest-looking window is the one that spends every weekend stale
    /// under a caption reading "today". A week always contains trading.
    public static let defaultWindow = ReturnWindow.oneWeek

    /// Whether the broker's valuation was struck today.
    ///
    /// `true` when the broker reported no timestamp at all: no evidence of staleness
    /// is not evidence of staleness, and the alternative is captioning perfectly
    /// fresh figures as belonging to a previous session.
    public var isValuationCurrent: Bool {
        guard let valued = snapshot.valuationDate else { return true }
        return calendar.isDate(valued, inSameDayAs: asOf)
    }

    /// The move over `window`, or `nil` when the broker did not report it.
    public func move(in window: ReturnWindow) -> MarketMove? {
        guard let gain = snapshot.returns[window] else { return nil }
        return MarketMove(
            window: window,
            gain: gain,
            total: snapshot.total,
            isCurrentSession: isValuationCurrent
        )
    }

    /// The windows worth offering: the cyclable ones this payload actually carries,
    /// shortest first.
    ///
    /// Filtered rather than assumed, so tapping never lands on a window with no
    /// figure behind it.
    public var availableWindows: [ReturnWindow] {
        ReturnWindow.cyclable.filter { snapshot.returns[$0] != nil }
    }

    /// Where the rotation starts: the default when it is available, otherwise the
    /// shortest window that is.
    public var initialWindow: ReturnWindow? {
        let available = availableWindows
        return available.contains(Self.defaultWindow) ? Self.defaultWindow : available.first
    }

    /// The next window in the rotation, wrapping at the end.
    ///
    /// Returns `window` itself when it is the only one available, so a tap on a
    /// single-window payload is a no-op rather than a jump to something absent.
    public func window(after window: ReturnWindow) -> ReturnWindow {
        let available = availableWindows
        guard let index = available.firstIndex(of: window), available.count > 1 else { return window }
        return available[(index + 1) % available.count]
    }

    /// The move shown when nothing has been chosen — and the only one the menu bar
    /// ever shows, since a status item has nothing to tap.
    public var defaultMove: MarketMove? {
        initialWindow.flatMap { move(in: $0) }
    }

    /// Every available move, for the text output.
    public var moves: [MarketMove] {
        availableWindows.compactMap { move(in: $0) }
    }

    // MARK: - Slider bounds

    /// Upper bound for the "save more" slider, as an *extra* monthly amount.
    ///
    /// Whichever is larger of: twice the current contribution, or enough extra to
    /// **halve the time to the goal**.
    ///
    /// The doubling alone scales with saving habit but not with ambition — it was
    /// a sensible span for a €50 000 goal and stopped well short of the
    /// interesting part of a €1 000 000 one, where the whole slider still left a
    /// decade to run. Halving the horizon is the ambition the goal itself implies,
    /// and it also keeps the two sliders on the same ground: "reach by" can quote
    /// a figure this one can now actually reach.
    ///
    /// Halving is used rather than the earliest offered target year on purpose —
    /// reaching €1 000 000 by next year needs about €55 000 a month, and a slider
    /// running that far is worse than one stopping too soon.
    public var extraSavingsCeiling: Double {
        let doubled = max(snapshot.monthlySavings, 100) * 2

        guard let months = headlineMonths, months >= 2 else { return Self.tidyBound(doubled) }
        let halved = max(Int((months / 2).rounded()), 1)
        let required = Projection.requiredMonthlySavings(
            value: snapshot.total,
            goal: goal,
            annualRate: headlineRate,
            months: halved,
            dynamizationRate: snapshot.dynamizationRate
        ) ?? 0

        let extra = max(required - snapshot.monthlySavings, 0)
        return Self.tidyBound(max(doubled, extra))
    }

    /// Rounds a slider bound up to a round number, coarser as it grows, so the
    /// end label reads as a bound someone chose rather than as arithmetic.
    private static func tidyBound(_ amount: Double) -> Double {
        let increment: Double = amount < 1_000 ? 50 : 250
        return (amount / increment).rounded(.up) * increment
    }

    // MARK: - Target year

    /// Years the "reach by" slider offers: next year through twenty years out.
    ///
    /// It starts next year rather than this one because a horizon of a few
    /// remaining months demands an absurd contribution, and it deliberately
    /// extends past the projected arrival — dragging *later* answers "how much
    /// could I ease off and still make it?", which is as useful as the other
    /// direction.
    public var targetYearRange: ClosedRange<Int> {
        let thisYear = calendar.component(.year, from: asOf)
        return (thisYear + 1)...(thisYear + 20)
    }

    /// Months from now to the end of `year` — the horizon behind
    /// `requiredMonthlySavings(byYear:)`.
    ///
    /// Measured to December because "reach it by 2031" means any time in 2031,
    /// so the horizon is the whole year. Anchoring on January instead would
    /// quote a contribution nearly a year's worth too aggressive.
    public func monthsUntilEndOf(year: Int) -> Int? {
        let components = DateComponents(year: year, month: 12, day: 31)
        guard let end = calendar.date(from: components) else { return nil }
        let months = calendar.dateComponents([.month], from: asOf, to: end).month ?? 0
        return months > 0 ? months : nil
    }

    /// A few target years worth quoting in the text output: side-stepping the
    /// projected arrival so `--once` shows both directions of the trade.
    public var targetYearSamples: [Int] {
        let range = targetYearRange
        let anchor = headlineYear ?? range.lowerBound + 2
        return [anchor - 2, anchor, anchor + 2]
            .map { min(max($0, range.lowerBound), range.upperBound) }
            .reduce(into: []) { unique, year in
                if !unique.contains(year) { unique.append(year) }
            }
    }

    /// `(year, required, delta against what is saved now)` per sampled year.
    public var requiredSavingsRows: [(year: Int, required: Double?, delta: Double?)] {
        targetYearSamples.map { year in
            let required = requiredMonthlySavings(byYear: year)
            return (year, required, required.map { $0 - snapshot.monthlySavings })
        }
    }

    /// The monthly contribution needed to reach the goal by the end of `year`, at
    /// the headline rate.
    ///
    /// With dynamization this is the amount to *start* at — it steps up annually
    /// from there, exactly like the plan it would replace. `0` means growth alone
    /// gets there; `nil` means the year is not in the future.
    public func requiredMonthlySavings(byYear year: Int) -> Double? {
        guard let months = monthsUntilEndOf(year: year) else { return nil }
        return Projection.requiredMonthlySavings(
            value: snapshot.total,
            goal: goal,
            annualRate: headlineRate,
            months: months,
            dynamizationRate: snapshot.dynamizationRate
        )
    }

    // MARK: - Menu bar title

    /// The compact one-line summary, e.g. `🎯 12% · 2037`.
    ///
    /// Used by the text output. The menu bar itself draws a progress ring and
    /// shows `menuBarText` beside it.
    public var statusTitle: String {
        if isGoalReached { return "🎯 100% · reached" }
        let percent = Int((progress * 100).rounded())
        guard let headlineYear else { return "🎯 \(percent)% · —" }
        return "🎯 \(percent)% · \(headlineYear)"
    }

    /// What sits next to the menu bar ring: the year, and nothing else.
    ///
    /// The percentage is what the ring is for, so repeating it as text would
    /// just make the menu bar noisy.
    public var menuBarText: String {
        if isGoalReached { return "Reached" }
        guard let headlineYear else { return "—" }
        return String(headlineYear)
    }

    // MARK: - Row models
    //
    // Both the menu and the text output build from these, so the two renderings
    // can never drift apart.

    /// The labelled summary rows at the top of the menu.
    public var summaryRows: [(label: String, value: String)] {
        // Goal and Remaining deliberately absent: the hero already states the goal
        // amount in prose and the bar states the percentage, so both rows were
        // restating the top of the popover in a smaller font.
        var rows: [(String, String)] = [
            ("Portfolio", Format.euro(snapshot.total, decimals: 2)),
        ]

        var saving = "\(Format.euro(snapshot.monthlySavings, decimals: 2))/mo"
        var notes: [String] = []
        if snapshot.savingsPlanCount > 0 {
            let noun = snapshot.savingsPlanCount == 1 ? "plan" : "plans"
            notes.append("\(snapshot.savingsPlanCount) \(noun)")
        }
        // Worth showing rather than leaving implicit: it is the difference between
        // a flat contribution and one that keeps pace with inflation, and every
        // projected year on screen depends on it.
        if snapshot.dynamizationRate > 0 {
            notes.append("+\(Format.percent(snapshot.dynamizationRate, decimals: 0))/yr")
        }
        if !notes.isEmpty {
            saving += "  (\(notes.joined(separator: " · ")))"
        }
        rows.append(("Saving", saving))

        if let gain = snapshot.oneYearGain {
            rows.append(("Past year", Format.signedEuro(gain, decimals: 2)))
        }
        return rows
    }

    /// Heading for the what-if section.
    public var whatIfHeading: String {
        "If I saved more (at \(Format.percent(headlineRate)))"
    }

    /// A plain-text rendering of the whole menu, so the app can be checked from
    /// a terminal without launching the UI.
    public func textReport() -> String {
        var lines = [statusTitle, ""]
        lines += summaryRows.map { Format.summaryRow($0.label, $0.value) }

        let moves = self.moves
        if !moves.isEmpty {
            lines += ["", "Market"]
            lines += moves.map { "  " + Format.moveRow($0) }
        }

        lines += ["", "Projections"]
        lines += scenarios.map { "  " + Format.scenarioRow($0) }
        if let real = realGoalValue, let year = headlineYear {
            lines += ["", "In today's money"]
            lines += ["  \(Format.euro(goal)) in \(year) ≈ \(Format.euro(real))"
                + "  (at \(Format.percent(Projection.assumedInflation, decimals: 0)) inflation)"]
        }

        if !isGoalReached {
            lines += ["", whatIfHeading]
            lines += whatIfs.map { "  " + Format.whatIfRow($0) }

            lines += ["", "To reach it by"]
            lines += requiredSavingsRows.map { "  " + Format.requiredRow($0) }
        }
        lines += [""] + Disclaimer.textBlock(for: self)
        return lines.joined(separator: "\n")
    }
}
