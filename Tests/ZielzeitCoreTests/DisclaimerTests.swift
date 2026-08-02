import XCTest
@testable import ZielzeitCore

/// The disclaimer names specific modelling decisions, so these tests are what
/// stop it going stale: change an assumption in `Projection` without changing the
/// text and one of these fails.
///
/// Each conditional line is asserted in both directions — present when it
/// applies, absent when it does not. A caveat that no longer matches the
/// arithmetic is worse than none, and only the absence assertions catch that.
final class DisclaimerTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 31))!
    }

    private func report(
        oneYearGain: Double? = 1_950.0,
        monthlySavings: Double = 380.0,
        dynamizationRate: Double = 0.05,
        goal: Double = 1_000_000
    ) -> Report {
        Report(
            goal: goal,
            snapshot: PortfolioSnapshot(
                total: 12_480.50,
                oneYearGain: oneYearGain,
                monthlySavings: monthlySavings,
                savingsPlanCount: 4,
                dynamizationRate: dynamizationRate
            ),
            now: now,
            calendar: calendar
        )
    }

    private func text(_ report: Report) -> String {
        Disclaimer.assumptions(for: report).joined(separator: "\n")
    }

    // MARK: - The rate on screen

    /// Quoting the figure is the point: "assumes a constant return" is easy to
    /// nod past, "assumes 23.0% every year" is not.
    func testQuotesTheRateTheHeadlineActuallyUsed() {
        let subject = report()
        XCTAssertTrue(text(subject).contains(Format.percent(subject.headlineRate)))
    }

    /// With no measurable pace the headline silently borrows the moderate
    /// assumption. That substitution is exactly what a user should be told.
    func testSaysWhenTheRateIsBorrowedRatherThanMeasured() {
        let subject = report(oneYearGain: nil)
        XCTAssertNil(subject.realizedAnnualRate)

        let lines = text(subject)
        XCTAssertTrue(lines.contains("Under a year of history"))
        XCTAssertTrue(lines.contains(Format.percent(Report.moderateRate)))
        XCTAssertFalse(
            lines.contains("from one trailing year"),
            "Nothing was measured, so the text must not imply it was."
        )
    }

    // MARK: - Conditional lines

    /// The twelve-deposit delay before the first raise is an assumption, not an
    /// API fact — the payload carries no dynamization anniversary.
    func testDisclosesTheGuessedStepUpWhenThePlanDynamizes() {
        let lines = text(report())
        XCTAssertTrue(lines.contains("Step-up date is guessed"))
        XCTAssertTrue(lines.contains("rising 5%/yr"))
    }

    func testInventsNoStepUpForAFlatPlan() {
        let lines = text(report(dynamizationRate: 0))
        XCTAssertFalse(lines.contains("Step-up"))
        XCTAssertFalse(lines.contains("rising"))
    }

    func testStatesTheContributionItAssumesContinues() {
        XCTAssertTrue(text(report()).contains(Format.euro(380.0)))
    }

    func testSaysNothingAboutContributionsWithoutASavingsPlan() {
        XCTAssertFalse(text(report(monthlySavings: 0, dynamizationRate: 0)).contains("never paused"))
    }

    // MARK: - Unconditional lines

    func testAlwaysWarnsAboutSmoothCompoundingAndTax() {
        let sparse = report(oneYearGain: nil, monthlySavings: 0, dynamizationRate: 0)
        for subject in [report(), sparse] {
            XCTAssertTrue(text(subject).contains("Real returns don't"))
            XCTAssertTrue(text(subject).contains("Before tax"))
        }
    }

    /// Inflation is disclaimed only while it is unaccounted for. Once the hero states
    /// the goal in today's money the honest line names the assumption behind that
    /// figure instead — claiming the projection ignores inflation while a
    /// inflation-adjusted figure sits on screen would be the caveat contradicting the
    /// arithmetic, which is exactly what these tests exist to catch.
    func testInflationIsDisclaimedOnlyWhileItIsUnaccountedFor() {
        // A long horizon carries the today's-money figure.
        let long = report()
        XCTAssertNotNil(long.realGoalValue)
        XCTAssertTrue(text(long).contains("today's money assumes 2% inflation"))
        XCTAssertFalse(text(long).contains("Before tax and inflation"))

        // A goal already within a year has nothing to discount to.
        let near = Report(
            goal: 12_000,
            snapshot: PortfolioSnapshot(total: 11_500, oneYearGain: 500, monthlySavings: 400)
        )
        XCTAssertNil(near.realGoalValue)
        XCTAssertTrue(Disclaimer.assumptions(for: near).contains("Before tax and inflation."))
    }

    // MARK: - Reaching the user

    /// `--once` is the whole product for anyone reading the numbers from a
    /// terminal, so it carries the same lines rather than a shortened version.
    func testTextReportCarriesEveryLine() {
        let subject = report()
        let output = subject.textReport()
        XCTAssertTrue(output.contains(Disclaimer.headline))
        XCTAssertTrue(output.contains(Disclaimer.notAdvice))
        for line in Disclaimer.assumptions(for: subject) {
            XCTAssertTrue(output.contains(line), "Missing from --once: \(line)")
        }
    }

    /// Tax and inflation still apply to a figure being celebrated.
    func testPresentEvenWhenTheGoalIsReached() {
        let reached = Report(
            goal: 10_000,
            snapshot: PortfolioSnapshot(total: 12_480.50, oneYearGain: 1_818.86, monthlySavings: 380.0),
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(reached.isGoalReached)
        XCTAssertTrue(reached.textReport().contains(Disclaimer.headline))
    }

    /// Short enough to be read. The whole point of the rewrite was that nobody
    /// reads a paragraph of hedging, so length is part of the contract.
    func testEveryLineIsShortEnoughToRead() {
        for line in Disclaimer.assumptions(for: report()) {
            XCTAssertLessThanOrEqual(line.count, 70, "Too long to be fine print: \(line)")
        }
    }
}
