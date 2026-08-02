import XCTest
@testable import ZielzeitCore

/// The trailing contribution figure: what it counts, what it must not, and what
/// it does to the measured pace.
///
/// The payload below is shaped from a real `sc broker transactions --json`
/// response, including the custody migration that appears as a matched pair of
/// `NON_TRADE_SECURITY_TRANSACTION` entries. Counting those as contributions was
/// the first thing this got wrong by hand, hence the fixture.
final class ContributionsTests: XCTestCase {

    private let payload = Data("""
    {
      "ok": true,
      "command": "broker transactions",
      "data": {
        "result": {
          "account_id": "acct",
          "count": 8,
          "total": 8,
          "items": [
            {"amount": 380.0, "cash_transaction_type": "DEPOSIT", "currency": "EUR",
             "description": "Scalable Capital Broker savings plan",
             "last_event_datetime": "2026-07-23T00:00:00.000Z"},
            {"amount": 300.0, "cash_transaction_type": "DEPOSIT", "currency": "EUR",
             "description": "Scalable Capital Broker savings plan",
             "last_event_datetime": "2025-08-23T00:00:00.000Z"},
            {"amount": -80.0, "cash_transaction_type": "WITHDRAWAL", "currency": "EUR",
             "description": "Scalable Capital Broker withdrawal",
             "last_event_datetime": "2025-08-22T00:00:00.000Z"},
            {"amount": 0.91, "cash_transaction_type": "INTEREST", "currency": "EUR",
             "description": "Interest", "last_event_datetime": "2026-01-02T00:00:00.000Z"},
            {"amount": -102.5, "currency": "EUR", "isin": "IE00EXAMPLE02",
             "description": "Example Europe (Acc)",
             "type": "SECURITY_TRANSACTION",
             "last_event_datetime": "2026-07-27T10:27:15.070Z"},
            {"amount": -2050.0, "currency": "EUR", "isin": "IE00EXAMPLE02",
             "description": "Example Europe (Acc)",
             "type": "NON_TRADE_SECURITY_TRANSACTION",
             "last_event_datetime": "2025-12-05T00:00:00.000Z"},
            {"amount": 2049.0, "currency": "EUR", "isin": "IE00EXAMPLE02",
             "description": "Example Europe (Acc)",
             "type": "NON_TRADE_SECURITY_TRANSACTION",
             "last_event_datetime": "2025-12-06T00:00:00.000Z"}
          ]
        }
      }
    }
    """.utf8)

    private func decoded() throws -> TransactionsResult {
        try ScalableClient.decode(TransactionsResult.self, from: payload, command: "broker transactions")
    }

    // MARK: - What counts

    /// Deposits less withdrawals, and nothing else: 380 + 300 − 80.
    func testCountsDepositsAndWithdrawalsOnly() throws {
        XCTAssertEqual(try decoded().netExternalFlow, 600.0, accuracy: 0.001)
    }

    /// A custody migration moves the whole portfolio out and back in. Counted as
    /// contributions it would swamp a year of deposits and drive the Dietz
    /// denominator negative, reporting "no measurable pace" on a healthy account.
    func testIgnoresCustodyMigrationPairs() throws {
        let result = try decoded()
        let migrationAmounts = 2_049.0 - 2_050.0
        XCTAssertEqual(result.netExternalFlow, 600.0, accuracy: 0.001)
        XCTAssertNotEqual(result.netExternalFlow, 600.0 + migrationAmounts, accuracy: 0.001)
    }

    /// Interest is a return the portfolio earned. Counting it as money paid in
    /// would subtract the portfolio's own earnings from its performance.
    func testIgnoresInterest() throws {
        XCTAssertFalse(try XCTUnwrap(decoded().items).isEmpty)
        XCTAssertEqual(try decoded().netExternalFlow, 600.0, accuracy: 0.001)
    }

    func testIgnoresSecurityTradesWhichCarryNoCashType() throws {
        let trades = try XCTUnwrap(decoded().items).filter { $0.cashTransactionType == nil }
        XCTAssertEqual(trades.count, 3, "Fixture should hold one buy and the migration pair.")
    }

    // MARK: - Paging

    func testEmptyCursorIsTreatedAsNoFurtherPages() throws {
        XCTAssertNil(try decoded().nextCursor)

        let paged = Data("""
        {"ok": true, "data": {"result": {"items": [], "cursor": "abc"}}}
        """.utf8)
        let result = try ScalableClient.decode(TransactionsResult.self, from: paged, command: "t")
        XCTAssertEqual(result.nextCursor, "abc")

        let blank = Data("""
        {"ok": true, "data": {"result": {"items": [], "cursor": ""}}}
        """.utf8)
        XCTAssertNil(
            try ScalableClient.decode(TransactionsResult.self, from: blank, command: "t").nextCursor
        )
    }

    /// Missing keys must not fail the decode: this is a refinement to a rate, and
    /// a schema change should cost the refinement rather than the portfolio read.
    func testDecodesWithNeitherItemsNorCursor() throws {
        let sparse = Data(#"{"ok": true, "data": {"result": {}}}"#.utf8)
        let result = try ScalableClient.decode(TransactionsResult.self, from: sparse, command: "t")
        XCTAssertEqual(result.netExternalFlow, 0)
        XCTAssertNil(result.nextCursor)
    }

    // MARK: - Effect on the rate

    /// The numbers from the portfolio this was built against: an estimate of
    /// 12 × €380 against a measured €3 900.
    func testMeasuredFlowLowersTheOverstatedPace() {
        let estimated = Projection.realizedAnnualRate(
            total: 12_480.50, oneYearGain: 1_950.0, monthlySavings: 380.0
        )
        let measured = Projection.realizedAnnualRate(
            total: 12_480.50, oneYearGain: 1_950.0, monthlySavings: 380.0,
            trailingContributions: 3_900.0
        )
        XCTAssertEqual(try! XCTUnwrap(estimated), 0.23635, accuracy: 0.0005)
        XCTAssertEqual(try! XCTUnwrap(measured), 0.22726, accuracy: 0.0005)
        XCTAssertLessThan(measured!, estimated!, "A ramped-up plan flatters the estimate.")
    }

    /// Someone running a plan *and* buying by hand — the case this was built for.
    ///
    /// The estimate misses the manual money, so it credits the portfolio with
    /// capital it never had and the pace comes out **below** what was achieved.
    /// That is the opposite direction to the step-up bias above, which is the whole
    /// argument for measuring rather than applying a correction factor.
    func testManualBuyingUnderstatesTheEstimatedPace() {
        let estimated = Projection.realizedAnnualRate(
            total: 60_000, oneYearGain: 6_000, monthlySavings: 500
        )
        // Same year, but €18 000 actually went in rather than the €6 000 implied
        // by the plan alone.
        let measured = Projection.realizedAnnualRate(
            total: 60_000, oneYearGain: 6_000, monthlySavings: 500,
            trailingContributions: 18_000
        )
        XCTAssertGreaterThan(measured!, estimated!)
        XCTAssertEqual(estimated!, 6_000 / 51_000, accuracy: 0.0001)
        XCTAssertEqual(measured!, 6_000 / 45_000, accuracy: 0.0001)
    }

    /// Falling back must reproduce the old behaviour exactly, since that is what
    /// every user without the transaction data still gets.
    func testNilFallsBackToTwelveTimesMonthly() {
        XCTAssertEqual(
            Projection.realizedAnnualRate(
                total: 60_000, oneYearGain: 6_000, monthlySavings: 500, trailingContributions: nil
            ),
            Projection.realizedAnnualRate(total: 60_000, oneYearGain: 6_000, monthlySavings: 500)
        )
    }

    /// A withdrawal-heavy year can net out negative, which raises the rate rather
    /// than breaking it: money taken out was not there to earn the gain.
    func testNegativeNetFlowIsUsableRatherThanRejected() {
        let rate = Projection.realizedAnnualRate(
            total: 60_000, oneYearGain: 6_000, monthlySavings: 0,
            trailingContributions: -12_000
        )
        XCTAssertEqual(try! XCTUnwrap(rate), 6_000 / 60_000.0, accuracy: 0.0001)
    }

    // MARK: - Saying which figure was used

    func testDisclaimerFlagsAnEstimatedPaceOnly() {
        func lines(trailing: Double?) -> String {
            let snapshot = PortfolioSnapshot(
                total: 12_480.50, oneYearGain: 1_950.0, monthlySavings: 380.0,
                savingsPlanCount: 4, dynamizationRate: 0.05,
                trailingContributions: trailing
            )
            return Disclaimer.assumptions(for: Report(goal: 1_000_000, snapshot: snapshot))
                .joined(separator: "\n")
        }

        XCTAssertTrue(lines(trailing: nil).contains("deposits ran at today's rate"))
        XCTAssertFalse(lines(trailing: 3_900.0).contains("deposits ran at today's rate"))
    }
}
