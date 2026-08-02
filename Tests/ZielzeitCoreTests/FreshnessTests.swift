import XCTest
@testable import ZielzeitCore

/// How fresh the figures are, and saying so honestly.
///
/// The broker's `valuation_timestamp_utc` sits at the previous session's close
/// outside trading hours — the live account reports Friday 21:00 UTC all weekend —
/// which is the difference between "fetched a minute ago" and "a minute old".
final class FreshnessTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Decoding

    /// Shaped from the live `sc broker overview --json`, whose `timestamps` block is
    /// the only place the as-of time appears.
    func testValuationTimestampIsRead() throws {
        let payload = Data("""
        {"ok": true, "data": {"result": {
          "valuation": {"crypto": 0, "securities": 12480.50, "total": 12480.50},
          "timestamps": {
            "inventory_timestamp_utc": "2026-08-01T01:03:29.602Z",
            "valuation_timestamp_utc": "2026-07-31T21:00:00.000Z"
          },
          "performance": [{"simpleAbsoluteReturn": 18.40, "timeframe": "ONE_WEEK"}]
        }}}
        """.utf8)
        let result = try ScalableClient.decode(OverviewResult.self, from: payload, command: "o")

        let valued = try XCTUnwrap(result.valuationDate)
        XCTAssertEqual(calendar.component(.day, from: valued), 31)
        XCTAssertEqual(calendar.component(.hour, from: valued), 21)
    }

    /// A missing or unparseable timestamp must cost the label and not the read: this
    /// is the same call the portfolio valuation arrives in.
    func testAbsentOrBrokenTimestampIsNotFatal() throws {
        let bare = Data(#"{"ok": true, "data": {"result": {"valuation": {"total": 100}}}}"#.utf8)
        XCTAssertNil(try ScalableClient.decode(OverviewResult.self, from: bare, command: "o").valuationDate)

        let broken = Data("""
        {"ok": true, "data": {"result": {"valuation": {"total": 100},
          "timestamps": {"valuation_timestamp_utc": "last Friday"}}}}
        """.utf8)
        let result = try ScalableClient.decode(OverviewResult.self, from: broken, command: "o")
        XCTAssertEqual(result.valuation.total, 100)
        XCTAssertNil(result.valuationDate)
    }

    func testTimestampsParseWithAndWithoutFractionalSeconds() {
        XCTAssertNotNil(WireTimestamp.parse("2026-07-31T21:00:00.000Z"))
        XCTAssertNotNil(WireTimestamp.parse("2026-07-31T21:00:00Z"))
        XCTAssertNil(WireTimestamp.parse("31 July 2026"))
    }

    // MARK: - Is the valuation current?

    private func report(valued: Date?, now: Date) -> Report {
        Report(
            goal: 100_000,
            snapshot: PortfolioSnapshot(
                total: 12_480.50,
                monthlySavings: 822.66,
                returns: [.intraday: 41.20, .oneWeek: 18.40, .oneMonth: -260.10],
                valuationDate: valued
            ),
            now: now,
            calendar: calendar
        )
    }

    func testValuationFromTodayIsCurrent() {
        let subject = report(valued: at(2026, 7, 31, 21), now: at(2026, 7, 31, 23))
        XCTAssertTrue(subject.isValuationCurrent)
    }

    func testFridayCloseReadOnASundayIsNotCurrent() {
        let subject = report(valued: at(2026, 7, 31, 21), now: at(2026, 8, 2, 14))
        XCTAssertFalse(subject.isValuationCurrent)
    }

    /// No evidence of staleness is not evidence of staleness — the alternative is
    /// captioning perfectly fresh figures as belonging to a previous session.
    func testNoTimestampIsTreatedAsCurrent() {
        XCTAssertTrue(report(valued: nil, now: at(2026, 8, 2)).isValuationCurrent)
    }

    // MARK: - The label that depends on it

    /// The whole point of the change: "today" is a claim about the calendar that a
    /// Friday-evening valuation cannot support on a Sunday.
    func testIntradayDemotesItselfToLastSessionWhenStale() {
        let weekend = report(valued: at(2026, 7, 31, 21), now: at(2026, 8, 2, 14))
        XCTAssertEqual(weekend.move(in: .intraday)?.windowLabel, "last session")

        let trading = report(valued: at(2026, 7, 31, 21), now: at(2026, 7, 31, 23))
        XCTAssertEqual(trading.move(in: .intraday)?.windowLabel, "today")
    }

    /// Every other window is a trailing span ending at the valuation, so its name
    /// stays true whether or not that valuation is today's.
    func testOtherWindowsKeepTheirNames() {
        let weekend = report(valued: at(2026, 7, 31, 21), now: at(2026, 8, 2, 14))
        XCTAssertEqual(weekend.move(in: .oneWeek)?.windowLabel, "this week")
        XCTAssertEqual(weekend.move(in: .oneMonth)?.windowLabel, "this month")
    }

    func testChipAndTextOutputNameTheWindowIdentically() {
        let weekend = report(valued: at(2026, 7, 31, 21), now: at(2026, 8, 2, 14))
        let move = weekend.move(in: .intraday)!
        XCTAssertTrue(Format.moveChip(move).hasSuffix("last session"))
        XCTAssertTrue(Format.moveRow(move).contains("last session"))
    }

    // MARK: - The footer stamp

    /// A bare `21:00` beside figures struck on Friday reads as this evening.
    func testStampCarriesTheDayOnlyWhenItIsNotToday() {
        let sameDay = Format.valuationStamp(
            at(2026, 7, 31, 21), now: at(2026, 7, 31, 23), calendar: calendar
        )
        let earlier = Format.valuationStamp(
            at(2026, 7, 31, 21), now: at(2026, 8, 2, 14), calendar: calendar
        )
        XCTAssertFalse(sameDay.contains("31"), sameDay)
        XCTAssertTrue(earlier.contains("31"), earlier)
        XCTAssertTrue(earlier.hasSuffix(sameDay), "The day is a prefix on the same time.")
    }
}
