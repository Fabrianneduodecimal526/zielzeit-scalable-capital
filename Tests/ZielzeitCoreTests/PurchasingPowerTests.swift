import XCTest
@testable import ZielzeitCore

/// The goal restated in today's money.
///
/// Over the horizons this app quotes, inflation is the largest single gap between
/// the headline and reality — bigger than anything else the disclaimer lists — and
/// the app previously handled it by mentioning it in fine print.
final class PurchasingPowerTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 2))!
    }

    // MARK: - The arithmetic

    /// `V / (1 + i)^(t/12)`, geometric like every other rate conversion here.
    func testDiscountsGeometricallyOverWholeYears() {
        XCTAssertEqual(
            Projection.realValue(nominal: 100_000, months: 12, annualInflation: 0.02),
            100_000 / 1.02,
            accuracy: 0.001
        )
        XCTAssertEqual(
            Projection.realValue(nominal: 100_000, months: 120, annualInflation: 0.02),
            100_000 / pow(1.02, 10),
            accuracy: 0.001
        )
    }

    /// Partial years discount partially — a horizon of eighteen months is not two
    /// years of erosion.
    func testPartialYearsDiscountPartially() {
        let year = Projection.realValue(nominal: 100_000, months: 12)
        let eighteen = Projection.realValue(nominal: 100_000, months: 18)
        let two = Projection.realValue(nominal: 100_000, months: 24)
        XCTAssertLessThan(eighteen, year)
        XCTAssertGreaterThan(eighteen, two)
    }

    func testZeroInflationChangesNothing() {
        XCTAssertEqual(
            Projection.realValue(nominal: 100_000, months: 240, annualInflation: 0),
            100_000,
            accuracy: 0.001
        )
    }

    /// Nothing to discount over no time, and a nonsensical rate must not produce a
    /// nonsensical figure — total deflation would divide by zero.
    func testDegenerateInputsReturnTheNominalAmount() {
        XCTAssertEqual(Projection.realValue(nominal: 100_000, months: 0), 100_000)
        XCTAssertEqual(Projection.realValue(nominal: 100_000, months: -12), 100_000)
        XCTAssertEqual(
            Projection.realValue(nominal: 100_000, months: 120, annualInflation: -1),
            100_000
        )
    }

    func testDefaultAssumptionIsTheEuroAreaTarget() {
        XCTAssertEqual(Projection.assumedInflation, 0.02)
        XCTAssertEqual(
            Projection.realValue(nominal: 100_000, months: 120),
            Projection.realValue(nominal: 100_000, months: 120, annualInflation: 0.02)
        )
    }

    // MARK: - On the report

    private func report(goal: Double, total: Double = 12_480.50, monthly: Double = 822.66) -> Report {
        Report(
            goal: goal,
            snapshot: PortfolioSnapshot(
                total: total,
                oneYearGain: 1_733.06,
                monthlySavings: monthly,
                dynamizationRate: 0.05
            ),
            now: now,
            calendar: calendar
        )
    }

    func testGoalIsDiscountedToTheProjectedHorizon() throws {
        let subject = report(goal: 100_000)
        let months = try XCTUnwrap(subject.headlineMonths)
        XCTAssertEqual(
            try XCTUnwrap(subject.realGoalValue),
            Projection.realValue(nominal: 100_000, months: months),
            accuracy: 0.001
        )
        XCTAssertLessThan(try XCTUnwrap(subject.realGoalValue), 100_000)
    }

    /// A further goal is eroded further, which is the whole reason the figure earns
    /// its place: the longer the projection, the less the headline amount means.
    func testALongerHorizonErodesMore() throws {
        let near = try XCTUnwrap(report(goal: 50_000).realGoalValue) / 50_000
        let far = try XCTUnwrap(report(goal: 1_000_000).realGoalValue) / 1_000_000
        XCTAssertLessThan(far, near)
    }

    /// Under a year the restatement would land on essentially the same figure, and a
    /// second amount saying nothing new is noise.
    func testNoFigureForAHorizonUnderAYear() {
        XCTAssertNil(report(goal: 12_000, total: 11_500, monthly: 400).realGoalValue)
    }

    func testNoFigureWhenThereIsNoArrivalToDiscountTo() {
        let unreachable = Report(
            goal: 50_000_000,
            snapshot: PortfolioSnapshot(total: 1_000, oneYearGain: 0, monthlySavings: 0),
            now: now,
            calendar: calendar
        )
        XCTAssertNil(unreachable.headlineMonths)
        XCTAssertNil(unreachable.realGoalValue)
    }

    func testReachedGoalHasNothingToDiscount() {
        let done = report(goal: 5_000)
        XCTAssertEqual(done.headlineMonths, 0)
        XCTAssertNil(done.realGoalValue)
    }

    // MARK: - Text output

    func testTextReportStatesTheFigureAndTheAssumption() {
        let text = report(goal: 100_000).textReport()
        XCTAssertTrue(text.contains("In today's money"), text)
        XCTAssertTrue(text.contains("2% inflation"), text)
        XCTAssertTrue(text.contains(Format.euro(100_000)), text)
    }

    func testTextReportOmitsTheSectionWithNothingToState() {
        XCTAssertFalse(report(goal: 12_000, total: 11_500, monthly: 400)
            .textReport().contains("In today's money"))
    }
}
