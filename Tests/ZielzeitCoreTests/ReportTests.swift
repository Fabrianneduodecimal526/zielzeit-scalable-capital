import XCTest
@testable import ZielzeitCore

final class ReportTests: XCTestCase {

    /// A fixed reference date so the projected years in these assertions are
    /// stable rather than drifting with the calendar.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 31))!
    }

    /// The live portfolio, as read from `sc`, with dynamization deliberately
    /// left off so the year literals below isolate one variable at a time.
    private var snapshot: PortfolioSnapshot {
        PortfolioSnapshot(
            total: 12_480.50,
            oneYearGain: 1_950.0,
            monthlySavings: 380.0,
            savingsPlanCount: 4
        )
    }

    /// The same portfolio as it actually stands: all four plans carry Scalable's
    /// 5% p.a. dynamization.
    private var dynamizedSnapshot: PortfolioSnapshot {
        PortfolioSnapshot(
            total: 12_480.50,
            oneYearGain: 1_950.0,
            monthlySavings: 380.0,
            savingsPlanCount: 4,
            dynamizationRate: 0.05
        )
    }

    private func report(goal: Double = 100_000, snapshot: PortfolioSnapshot? = nil) -> Report {
        Report(goal: goal, snapshot: snapshot ?? self.snapshot, now: now, calendar: calendar)
    }

    // MARK: - Headline

    func testStatusTitleShowsProgressAndYear() {
        XCTAssertEqual(report().statusTitle, "🎯 12% · 2032")
    }

    /// The widget exists to adapt to how the portfolio is actually performing,
    /// so the headline tracks the realized pace rather than a fixed assumption.
    func testHeadlineFollowsTheRealizedPaceNotTheModerateAssumption() throws {
        let report = self.report()
        let moderate = try XCTUnwrap(report.scenarios.first { $0.label == "Moderate" })
        let yourPace = try XCTUnwrap(report.scenarios.first { $0.label == "Your pace" })

        XCTAssertEqual(report.headlineYear, yourPace.year)
        XCTAssertEqual(report.headlineLabel, "Your pace")
        XCTAssertEqual(report.headlineRate, try XCTUnwrap(report.realizedAnnualRate))
        // Guard against slipping back to the fixed assumption: at 24% these
        // years genuinely differ, so the assertion above has teeth.
        XCTAssertNotEqual(moderate.year, yourPace.year)
    }

    /// The fallback turns on whether a pace could be measured at all — a brand
    /// new portfolio still gets a year instead of a dash.
    func testHeadlineFallsBackToModerateWhenThereIsNoMeasurablePace() throws {
        let young = PortfolioSnapshot(total: 3_000, oneYearGain: 50, monthlySavings: 1_000)
        let report = Report(goal: 100_000, snapshot: young, now: now, calendar: calendar)
        let moderate = try XCTUnwrap(report.scenarios.first { $0.label == "Moderate" })

        XCTAssertNil(report.realizedAnnualRate)
        XCTAssertEqual(report.headlineRate, Report.moderateRate)
        XCTAssertEqual(report.headlineLabel, "Moderate")
        XCTAssertEqual(report.headlineYear, moderate.year)
        XCTAssertNotNil(report.headlineYear)
    }

    /// ...but it never borrows the moderate year to paper over a bad pace. A
    /// portfolio losing money reports no arrival, which is the honest answer.
    func testALosingPaceReportsNoYearRatherThanBorrowingModerates() throws {
        // −10% over the year with *flat* contributions: the balance converges on
        // a ceiling of about €47 100 (−P/r), so a €50 000 goal is out of reach.
        // A dynamized plan escapes that ceiling — see the companion test below.
        let losing = PortfolioSnapshot(total: 12_400, oneYearGain: -1_200, monthlySavings: 380.0)
        let report = Report(goal: 50_000, snapshot: losing, now: now, calendar: calendar)
        let moderate = try XCTUnwrap(report.scenarios.first { $0.label == "Moderate" })

        XCTAssertLessThan(try XCTUnwrap(report.realizedAnnualRate), 0)
        XCTAssertNil(report.headlineYear)
        XCTAssertEqual(report.menuBarText, "—")
        XCTAssertNotNil(moderate.year, "moderate still arrives — the headline must not fall back to it")
    }

    func testReachedGoalIsAnnouncedRatherThanProjected() {
        let report = self.report(goal: 10_000)
        XCTAssertTrue(report.isGoalReached)
        XCTAssertEqual(report.statusTitle, "🎯 100% · reached")
        XCTAssertEqual(report.progress, 1)
        XCTAssertEqual(report.remaining, 0)
    }

    func testGoalBeyondTheHorizonShowsADashInsteadOfAYear() {
        // A flat year with no contributions is a measured pace of exactly 0%,
        // so the balance never moves and no goal above it is ever reached.
        let small = PortfolioSnapshot(total: 5_000, oneYearGain: 0, monthlySavings: 0)
        let report = Report(goal: 50_000_000, snapshot: small, now: now, calendar: calendar)
        XCTAssertNil(report.headlineYear)
        XCTAssertEqual(report.statusTitle, "🎯 0% · —")
    }

    func testADistantButReachableGoalStillShowsItsYear() throws {
        // Inside the horizon the year is reported even if it is absurdly far
        // off. €500 on €4 500 of capital is a measured pace of ~11%, which
        // compounds €5 000 to €1m in about fifty years.
        let small = PortfolioSnapshot(total: 5_000, oneYearGain: 500, monthlySavings: 0)
        let report = Report(goal: 1_000_000, snapshot: small, now: now, calendar: calendar)
        let yourPace = try XCTUnwrap(report.scenarios.first { $0.label == "Your pace" })

        XCTAssertEqual(report.headlineYear, yourPace.year)
        XCTAssertGreaterThan(try XCTUnwrap(report.headlineYear), 2060)
    }

    // MARK: - Scenarios

    func testScenarioOrderAndLabels() {
        XCTAssertEqual(report().scenarios.map(\.label), ["Cautious", "Moderate", "Your pace"])
    }

    func testCautiousScenarioNeverArrivesBeforeModerate() throws {
        let scenarios = report().scenarios
        let cautious = try XCTUnwrap(scenarios[0].months)
        let moderate = try XCTUnwrap(scenarios[1].months)
        XCTAssertGreaterThan(cautious, moderate)
    }

    func testYourPaceIsMarkedUnavailableWithoutEnoughHistory() throws {
        // Contributions swamp the capital base, so no rate can be derived.
        let young = PortfolioSnapshot(total: 3_000, oneYearGain: 50, monthlySavings: 1_000)
        let report = Report(goal: 100_000, snapshot: young, now: now, calendar: calendar)
        let yourPace = try XCTUnwrap(report.scenarios.first { $0.label == "Your pace" })

        XCTAssertNil(yourPace.annualRate)
        XCTAssertNil(yourPace.months)
        XCTAssertEqual(Format.scenarioRow(yourPace), "Your pace   —       not enough history")
    }

    // MARK: - What-ifs

    func testWhatIfsAreOrderedAndEachSavesTime() throws {
        // Both fixtures: dynamizing the extra along with the plan compresses the
        // differences between the rows, so monotonicity has to hold either way.
        for snapshot in [snapshot, dynamizedSnapshot] {
            let report = self.report(snapshot: snapshot)
            XCTAssertEqual(report.whatIfs.map(\.extraPerMonth), Report.whatIfIncrements)

            var previous = 0.0
            for whatIf in report.whatIfs {
                let saved = try XCTUnwrap(whatIf.yearsSaved)
                XCTAssertGreaterThan(saved, previous)
                previous = saved
            }
        }
    }

    func testWhatIfsAreOmittedOnceTheGoalIsReached() {
        let text = report(goal: 10_000).textReport()
        XCTAssertFalse(text.contains("If I saved more"))
    }

    // MARK: - Summary rows

    func testSummaryRowsCoverTheEssentials() {
        let labels = report().summaryRows.map(\.label)
        // Goal and Remaining are the hero's job now, not this list's.
        XCTAssertEqual(labels, ["Portfolio", "Saving", "Past year"])
    }

    func testPastYearRowIsOmittedWhenTheBrokerReportsNoFigure() {
        let noHistory = PortfolioSnapshot(total: 12_480.50, oneYearGain: nil, monthlySavings: 380.0)
        let labels = report(snapshot: noHistory).summaryRows.map(\.label)
        XCTAssertFalse(labels.contains("Past year"))
    }

    func testSavingRowNamesThePlanCount() throws {
        let rows = report().summaryRows
        let saving = try XCTUnwrap(rows.first { $0.label == "Saving" })
        XCTAssertTrue(saving.value.contains("(4 plans)"), saving.value)

        let single = PortfolioSnapshot(total: 100, monthlySavings: 50, savingsPlanCount: 1)
        let singleRow = try XCTUnwrap(report(snapshot: single).summaryRows.first { $0.label == "Saving" })
        XCTAssertTrue(singleRow.value.contains("(1 plan)"), singleRow.value)
    }

    // MARK: - Text output

    func testTextReportContainsEverySection() {
        let text = report().textReport()
        for expected in ["🎯 12% · 2032", "Portfolio", "Projections", "Cautious", "Your pace", "If I saved more"] {
            XCTAssertTrue(text.contains(expected), "missing \(expected)")
        }
    }

    /// The slider's continuous what-if must use the same calendar as the fixed
    /// scenarios, or the two could report different years for the same month
    /// count under a non-default calendar.
    func testArrivalUsesTheInjectedCalendarNotTheCurrentOne() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        let report = Report(goal: 100_000, snapshot: snapshot, now: now, calendar: buddhist)

        // Buddhist years run ~543 ahead, so a Gregorian fallback would be
        // obvious here.
        XCTAssertEqual(report.arrival(extraMonthlySavings: 0).year, report.headlineYear)
        XCTAssertGreaterThan(try XCTUnwrap(report.headlineYear), 2500)
    }

    // MARK: - Menu bar

    /// The menu bar shows the year beside a progress ring, so the text must not
    /// repeat the percentage the ring already conveys.
    func testMenuBarTextIsTheYearAlone() {
        XCTAssertEqual(report().menuBarText, "2032")
        XCTAssertFalse(report().menuBarText.contains("%"))
        XCTAssertFalse(report().menuBarText.contains("🎯"))
    }

    func testMenuBarTextWhenReached() {
        XCTAssertEqual(report(goal: 10_000).menuBarText, "Reached")
    }

    func testMenuBarTextWhenUnreachable() {
        let small = PortfolioSnapshot(total: 5_000, oneYearGain: 0, monthlySavings: 0)
        let report = Report(goal: 50_000_000, snapshot: small, now: now, calendar: calendar)
        XCTAssertEqual(report.menuBarText, "—")
    }

    func testMenuBarTextFollowsTheHeadline() throws {
        XCTAssertEqual(report().menuBarText, String(try XCTUnwrap(report().headlineYear)))
    }

    /// The slider previews inside the popover only; dragging it must never move
    /// the number in the menu bar.
    func testTheSliderDoesNotMoveTheMenuBarYear() {
        let report = self.report()
        let before = report.menuBarText
        XCTAssertNotEqual(report.arrival(extraMonthlySavings: 500).year, report.headlineYear)
        XCTAssertEqual(report.menuBarText, before)
    }

    // MARK: - Dynamization

    /// The savings plans step up 5% a year, so the same portfolio reaches the
    /// goal sooner than a flat contribution would suggest.
    func testDynamizationBringsEveryScenarioForward() throws {
        let flat = report(goal: 50_000)
        let dynamized = report(goal: 50_000, snapshot: dynamizedSnapshot)

        XCTAssertLessThan(
            try XCTUnwrap(dynamized.headlineMonths),
            try XCTUnwrap(flat.headlineMonths)
        )
        for label in [Report.cautiousLabel, Report.moderateLabel, Report.realizedLabel] {
            let flatMonths = try XCTUnwrap(flat.scenarios.first { $0.label == label }?.months)
            let dynMonths = try XCTUnwrap(dynamized.scenarios.first { $0.label == label }?.months)
            XCTAssertLessThan(dynMonths, flatMonths, label)
        }
    }

    /// The rate is an input the projections lean on heavily, so it is shown
    /// rather than left implicit.
    func testSavingRowShowsTheAnnualStepUp() throws {
        let rows = report(snapshot: dynamizedSnapshot).summaryRows
        let saving = try XCTUnwrap(rows.first { $0.label == "Saving" })
        XCTAssertTrue(saving.value.contains("4 plans"), saving.value)
        XCTAssertTrue(saving.value.contains("+5%/yr"), saving.value)

        // Nothing to say when no plan dynamizes.
        let flatRow = try XCTUnwrap(report().summaryRows.first { $0.label == "Saving" })
        XCTAssertFalse(flatRow.value.contains("/yr"), flatRow.value)
    }

    /// A rising contribution lifts the negative-rate ceiling every year, so a
    /// goal that is unreachable on flat contributions comes into reach. The
    /// headline must find it by walking forward rather than giving up on the
    /// first unreachable year.
    func testALosingPaceWithDynamizationEventuallyReachesTheGoal() throws {
        let losing = PortfolioSnapshot(
            total: 12_400, oneYearGain: -1_200, monthlySavings: 380.0,
            savingsPlanCount: 4, dynamizationRate: 0.05
        )
        let report = Report(goal: 50_000, snapshot: losing, now: now, calendar: calendar)

        XCTAssertLessThan(try XCTUnwrap(report.realizedAnnualRate), 0)
        XCTAssertNotNil(report.headlineYear, "the rising contribution escapes the ceiling")
        XCTAssertNotEqual(report.menuBarText, "—")
    }

    /// The chart's curve and the headline month must still agree once the
    /// contribution is a step function — the cross-check that keeps them honest.
    func testDynamizedCurveAndHeadlineAgree() throws {
        let report = self.report(goal: 50_000, snapshot: dynamizedSnapshot)
        let months = try XCTUnwrap(report.headlineMonths)
        let curve = try XCTUnwrap(report.curves().first { $0.label == report.headlineLabel })
        let arrival = try XCTUnwrap(curve.arrivalMonths)
        XCTAssertEqual(arrival, months, accuracy: 1e-6)
    }

    // MARK: - Slider bounds

    /// The floor: never narrower than doubling what is saved now.
    func testTheSaveMoreCeilingIsAtLeastDoubleTheCurrentContribution() {
        let ceiling = report(goal: 50_000, snapshot: dynamizedSnapshot).extraSavingsCeiling
        XCTAssertGreaterThanOrEqual(ceiling, snapshot.monthlySavings * 2)
    }

    /// The point of the change: an ambitious goal widens the slider, where the
    /// old doubling rule left it stopping a decade short.
    func testAnAmbitiousGoalWidensTheSaveMoreCeiling() {
        let modest = report(goal: 50_000, snapshot: dynamizedSnapshot).extraSavingsCeiling
        let ambitious = report(goal: 1_000_000, snapshot: dynamizedSnapshot).extraSavingsCeiling
        XCTAssertGreaterThan(ambitious, modest * 2)
    }

    /// And it is the *right* width: dragging to the end roughly halves the wait.
    func testDraggingToTheCeilingRoughlyHalvesTheTimeToGoal() throws {
        for goal in [50_000.0, 1_000_000.0] {
            let report = self.report(goal: goal, snapshot: dynamizedSnapshot)
            let base = try XCTUnwrap(report.headlineMonths)
            let atCeiling = try XCTUnwrap(
                report.arrival(extraMonthlySavings: report.extraSavingsCeiling).months
            )
            // Rounding the bound up means it always reaches at least halfway.
            XCTAssertLessThanOrEqual(atCeiling, base / 2, "goal \(goal)")
            XCTAssertGreaterThan(atCeiling, base / 4, "goal \(goal) — not absurdly wide")
        }
    }

    func testTheCeilingIsARoundNumber() {
        let modest = report(goal: 50_000, snapshot: dynamizedSnapshot).extraSavingsCeiling
        XCTAssertEqual(modest.truncatingRemainder(dividingBy: 50), 0, "\(modest)")

        let ambitious = report(goal: 1_000_000, snapshot: dynamizedSnapshot).extraSavingsCeiling
        XCTAssertEqual(ambitious.truncatingRemainder(dividingBy: 250), 0, "\(ambitious)")
    }

    /// An unreachable goal has no horizon to halve, so it falls back to doubling.
    func testTheCeilingFallsBackToDoublingWhenThereIsNoArrival() {
        let losing = PortfolioSnapshot(total: 12_400, oneYearGain: -1_200, monthlySavings: 380.0)
        let report = Report(goal: 50_000, snapshot: losing, now: now, calendar: calendar)
        XCTAssertNil(report.headlineMonths)
        XCTAssertEqual(report.extraSavingsCeiling, 800)
    }

    // MARK: - Target year

    func testTargetYearRangeStartsNextYearAndSpansTwentyYears() {
        let range = report().targetYearRange
        XCTAssertEqual(range.lowerBound, 2027)
        XCTAssertEqual(range.upperBound, 2046)
        // The projected arrival must be inside it, since that is where the
        // slider starts.
        XCTAssertTrue(range.contains(2032))
    }

    /// The horizon runs to December: "reach it by 2031" means any time in 2031,
    /// so quoting a January figure would demand nearly a year's worth too much.
    func testTheHorizonRunsToTheEndOfTheChosenYear() {
        // July 2026 → December 2031 is 65 months.
        XCTAssertEqual(report().monthsUntilEndOf(year: 2031), 65)
        XCTAssertNil(report().monthsUntilEndOf(year: 2025), "a past year has no horizon")
    }

    /// The quoted contribution must actually deliver the goal in that year — the
    /// round trip through the forward projection is the whole guarantee.
    func testRequiredSavingsActuallyReachesTheGoalInThatYear() throws {
        let report = self.report(goal: 50_000, snapshot: dynamizedSnapshot)
        let required = try XCTUnwrap(report.requiredMonthlySavings(byYear: 2029))
        let months = try XCTUnwrap(report.monthsUntilEndOf(year: 2029))

        let landed = Projection.balance(
            value: report.snapshot.total,
            monthlyRate: Projection.monthlyRate(annual: report.headlineRate),
            monthlySavings: required,
            afterMonths: months,
            dynamizationRate: report.snapshot.dynamizationRate
        )
        XCTAssertEqual(landed, 50_000, accuracy: 0.01)
    }

    func testAnEarlierTargetYearCostsMorePerMonth() throws {
        let report = self.report(goal: 50_000, snapshot: dynamizedSnapshot)
        var previous = Double.infinity
        for year in [2027, 2028, 2029, 2031, 2033] {
            let required = try XCTUnwrap(report.requiredMonthlySavings(byYear: year))
            XCTAssertLessThan(required, previous, "year \(year)")
            previous = required
        }
        // By 2033 this portfolio clears €50 000 on growth alone at its own pace.
        XCTAssertEqual(try XCTUnwrap(report.requiredMonthlySavings(byYear: 2033)), 0)
    }

    /// Dragging past the projected arrival answers the opposite question — how
    /// much could I ease off and still make it — so the figure must fall below
    /// what is being saved now.
    func testALaterYearThanProjectedNeedsLessThanIsSavedNow() throws {
        let report = self.report(goal: 50_000, snapshot: dynamizedSnapshot)
        let projected = try XCTUnwrap(report.headlineYear)
        let required = try XCTUnwrap(report.requiredMonthlySavings(byYear: projected + 3))
        XCTAssertLessThan(required, report.snapshot.monthlySavings)
    }

    /// At the projected year itself the answer should be roughly what is already
    /// being saved — the two calculations are inverses of each other.
    func testAtTheProjectedYearTheRequirementMatchesWhatIsAlreadySaved() throws {
        let report = self.report(goal: 50_000, snapshot: dynamizedSnapshot)
        let projected = try XCTUnwrap(report.headlineYear)
        let required = try XCTUnwrap(report.requiredMonthlySavings(byYear: projected))

        // Not exact: the arrival lands mid-year while the horizon runs to
        // December, so the extra months buy a little slack.
        XCTAssertLessThan(required, report.snapshot.monthlySavings)
        XCTAssertGreaterThan(required, report.snapshot.monthlySavings * 0.5)
    }

    func testTargetYearSamplesStraddleTheProjectedArrival() throws {
        let report = self.report(goal: 50_000, snapshot: dynamizedSnapshot)
        let projected = try XCTUnwrap(report.headlineYear)
        XCTAssertEqual(report.targetYearSamples.count, 3)
        XCTAssertTrue(report.targetYearSamples.contains(projected))
        // One either side, so the text output shows both directions of the trade.
        XCTAssertLessThan(report.targetYearSamples[0], projected)
        XCTAssertGreaterThan(report.targetYearSamples[2], projected)
    }

    func testTextReportIncludesTheRequiredContributions() {
        let text = report(goal: 50_000, snapshot: dynamizedSnapshot).textReport()
        XCTAssertTrue(text.contains("To reach it by"), text)
        XCTAssertTrue(text.contains("end of"), text)
        XCTAssertTrue(text.contains("vs now"), text)
    }

    func testRequiredRowNamesTheZeroCaseInWords() {
        let row = Format.requiredRow((year: 2040, required: 0, delta: -380.0))
        XCTAssertTrue(row.contains("growth alone"), row)
        XCTAssertFalse(row.contains("€0"), row)
    }

    func testProgressIsCappedAtOneHundredPercent() {
        XCTAssertEqual(report(goal: 1_000).progress, 1)
    }

    func testZeroGoalDoesNotProduceNaNProgress() {
        let report = Report(goal: 0, snapshot: snapshot, now: now, calendar: calendar)
        XCTAssertEqual(report.progress, 0)
        XCTAssertFalse(report.progress.isNaN)
    }
}

final class FormattingTests: XCTestCase {

    func testScenarioRowColumnsAlign() {
        let rows = [
            Scenario(label: "Cautious", annualRate: 0.03, months: 163.2, year: 2040),
            Scenario(label: "Your pace", annualRate: 0.242, months: 70.4, year: 2032),
        ].map { Format.scenarioRow($0) }

        // The year must start at the same offset in every row, since the menu
        // draws these in a monospaced font.
        let offsets = rows.map { row -> Int? in
            guard let range = row.range(of: "20") else { return nil }
            return row.distance(from: row.startIndex, to: range.lowerBound)
        }
        XCTAssertNotNil(offsets[0])
        XCTAssertEqual(offsets[0], offsets[1])
    }

    func testDurationReadsAsProse() {
        XCTAssertEqual(Format.duration(months: 188.4), "15.7 years")
        XCTAssertEqual(Format.duration(months: 42), "3.5 years")
        // Under two years reads better in months than as a fraction of a year.
        XCTAssertEqual(Format.duration(months: 18), "18 months")
        XCTAssertEqual(Format.duration(months: 1), "1 month")
        XCTAssertEqual(Format.duration(months: 0.4), "under a month")
    }

    func testUnreachableScenarioSaysSoPlainly() {
        let scenario = Scenario(label: "Cautious", annualRate: 0.03, months: nil, year: nil)
        XCTAssertTrue(Format.scenarioRow(scenario).contains("never at this pace"))
    }

    func testReachedScenarioIsCelebrated() {
        let scenario = Scenario(label: "Moderate", annualRate: 0.06, months: 0, year: 2026)
        XCTAssertTrue(Format.scenarioRow(scenario).contains("reached 🎉"))
    }

    func testWhatIfRowShowsYearsSavedOnlyWhenMeaningful() {
        let negligible = WhatIf(extraPerMonth: 50, year: 2037, yearsSaved: 0.01)
        XCTAssertFalse(Format.whatIfRow(negligible).contains("−"))

        let real = WhatIf(extraPerMonth: 200, year: 2035, yearsSaved: 2.6)
        XCTAssertTrue(Format.whatIfRow(real).contains("−2.6 yrs"))
    }

    func testSignedEuroUsesATypographicMinus() {
        XCTAssertTrue(Format.signedEuro(-240).hasPrefix("−"))
        XCTAssertTrue(Format.signedEuro(240).hasPrefix("+"))
    }

    func testPercentFormatting() {
        XCTAssertEqual(Format.percent(0.06), "6.0%")
        XCTAssertEqual(Format.percent(0.2423, decimals: 1), "24.2%")
    }
}