import XCTest
@testable import ZielzeitCore

/// The market chip and the menu bar caret: which windows are offered, which way
/// they point, and the percentages derived because the payload's own are useless.
///
/// The fixture is the live `sc broker overview --json` response verbatim, including
/// the two details that shaped the design: `performance` is `0` on every entry, and
/// `INTRADAY` and `TWO_DAYS` carry the identical figure because the capture was
/// taken with the market shut.
final class MarketMoveTests: XCTestCase {

    private let payload = Data("""
    {
      "ok": true,
      "command": "broker overview",
      "data": {
        "result": {
          "account_id": "acct",
          "valuation": {"total": 12480.50},
          "performance": [
            {"performance": 0, "simpleAbsoluteReturn": 41.20, "timeframe": "INTRADAY"},
            {"performance": 0, "simpleAbsoluteReturn": 41.20, "timeframe": "TWO_DAYS"},
            {"performance": 0, "simpleAbsoluteReturn": 18.40, "timeframe": "ONE_WEEK"},
            {"performance": 0, "simpleAbsoluteReturn": -260.10, "timeframe": "ONE_MONTH"},
            {"performance": 0, "simpleAbsoluteReturn": 720.0, "timeframe": "THREE_MONTHS"},
            {"performance": 0, "simpleAbsoluteReturn": 1040.0, "timeframe": "SIX_MONTHS"},
            {"performance": 0, "simpleAbsoluteReturn": 1950.0, "timeframe": "ONE_YEAR"},
            {"performance": 0, "simpleAbsoluteReturn": 2310.0, "timeframe": "MAX"}
          ]
        }
      }
    }
    """.utf8)

    private func decoded() throws -> OverviewResult {
        try ScalableClient.decode(OverviewResult.self, from: payload, command: "broker overview")
    }

    // MARK: - Decoding

    func testEveryWindowIsRead() throws {
        let windows = try decoded().trailingReturns
        XCTAssertEqual(windows.count, 8)
        XCTAssertEqual(try XCTUnwrap(windows[.intraday]), 41.20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(windows[.oneWeek]), 18.40, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(windows[.oneMonth]), -260.10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(windows[.oneYear]), 1_950.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(windows[.max]), 2_310.0, accuracy: 0.001)
    }

    /// This is the same call the portfolio valuation comes from, so a broker that
    /// adds a window must cost the window and not the whole read.
    func testUnknownWindowIsSkippedRatherThanFailingTheDecode() throws {
        let payload = Data("""
        {"ok": true, "data": {"result": {"valuation": {"total": 100},
          "performance": [
            {"simpleAbsoluteReturn": 1.0, "timeframe": "ONE_WEEK"},
            {"simpleAbsoluteReturn": 2.0, "timeframe": "TEN_YEARS"}
          ]}}}
        """.utf8)
        let result = try ScalableClient.decode(OverviewResult.self, from: payload, command: "o")
        XCTAssertEqual(result.trailingReturns, [.oneWeek: 1.0])
    }

    /// One storage location, two spellings. Storing the one-year figure separately
    /// would let the headline rate and the "past year" window disagree about the
    /// same number.
    func testOneYearGainIsAViewOntoTheWindows() throws {
        let snapshot = PortfolioSnapshot(total: 12_480.50, returns: try decoded().trailingReturns)
        XCTAssertEqual(try XCTUnwrap(snapshot.oneYearGain), 1_950.0, accuracy: 0.001)

        // The older spelling still works, and lands in the same place.
        let legacy = PortfolioSnapshot(total: 100, oneYearGain: 10)
        XCTAssertEqual(legacy.returns[.oneYear], 10)
        XCTAssertEqual(legacy.oneYearGain, 10)

        // Given both, the full set wins on its own window.
        let both = PortfolioSnapshot(total: 100, oneYearGain: 10, returns: [.oneYear: 20])
        XCTAssertEqual(both.oneYearGain, 20)
    }

    // MARK: - Derived percentage

    /// The payload carries a `performance` field that by its name is exactly this,
    /// and the live CLI returns `0` for every window — including one with a
    /// four-figure return. Hence deriving it.
    func testPercentageIsDerivedBecauseThePayloadsIsAlwaysZero() throws {
        for entry in try XCTUnwrap(decoded().performance) {
            XCTAssertEqual(entry.timeframe.isEmpty, false)
        }

        // Over the value the window *started* at: 18.40 / (12 480.50 − 18.40).
        let move = MarketMove(window: .oneWeek, gain: 18.40, total: 12_480.50)
        XCTAssertEqual(try XCTUnwrap(move.fraction), 18.40 / 12_462.10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(move.fraction), 0.001476, accuracy: 0.00001)

        let month = MarketMove(window: .oneMonth, gain: -260.10, total: 12_480.50)
        XCTAssertEqual(try XCTUnwrap(month.fraction), -0.02042, accuracy: 0.0001)
    }

    /// A gain that accounts for the entire balance leaves nothing to divide by.
    func testNoPercentageWhenTheWindowStartedAtNothing() {
        XCTAssertNil(MarketMove(window: .oneYear, gain: 100, total: 100).fraction)
        XCTAssertNil(MarketMove(window: .oneYear, gain: 150, total: 100).fraction)
    }

    // MARK: - Direction

    func testDirectionFollowsTheSign() {
        XCTAssertEqual(MarketMove(window: .oneWeek, gain: 18.40, total: 1_000).direction, .up)
        XCTAssertEqual(MarketMove(window: .oneMonth, gain: -260.10, total: 1_000).direction, .down)
    }

    /// A caret beside a figure that prints as `€0,00` claims a move the number does
    /// not show, so anything under half a cent is flat.
    func testSubCentMovesAreFlat() {
        XCTAssertEqual(MarketMove(window: .intraday, gain: 0, total: 1_000).direction, .flat)
        XCTAssertEqual(MarketMove(window: .intraday, gain: 0.004, total: 1_000).direction, .flat)
        XCTAssertEqual(MarketMove(window: .intraday, gain: -0.004, total: 1_000).direction, .flat)
        XCTAssertEqual(MarketMove(window: .intraday, gain: 0.006, total: 1_000).direction, .up)
    }

    func testFlatDrawsNoArrow() {
        XCTAssertEqual(Format.arrow(.flat), "")
        XCTAssertEqual(Format.arrow(.up), "▲")
        XCTAssertEqual(Format.arrow(.down), "▼")
    }

    // MARK: - Which windows are offered

    /// `TWO_DAYS` is indistinguishable from `INTRADAY` whenever the market is shut —
    /// the fixture shows both at 41.20 — and `MAX` is the account's whole life
    /// rather than a recent move.
    func testTwoDaysAndMaxAreNotOffered() throws {
        XCTAssertFalse(ReturnWindow.cyclable.contains(.twoDays))
        XCTAssertFalse(ReturnWindow.cyclable.contains(.max))

        let windows = try decoded().trailingReturns
        XCTAssertEqual(windows[.intraday], windows[.twoDays], "Fixture should show them identical.")
    }

    func testCyclableWindowsAreOrderedShortestFirst() {
        XCTAssertEqual(
            ReturnWindow.cyclable,
            [.intraday, .oneWeek, .oneMonth, .threeMonths, .sixMonths, .oneYear]
        )
    }

    private func report(_ returns: [ReturnWindow: Double], total: Double = 12_480.50) -> Report {
        Report(
            goal: 100_000,
            snapshot: PortfolioSnapshot(total: total, monthlySavings: 822.66, returns: returns)
        )
    }

    func testOnlyWindowsThePayloadCarriesAreOffered() throws {
        let full = report(try decoded().trailingReturns)
        XCTAssertEqual(full.availableWindows, ReturnWindow.cyclable)

        let sparse = report([.oneMonth: -10, .oneYear: 100, .max: 500])
        XCTAssertEqual(sparse.availableWindows, [.oneMonth, .oneYear])
    }

    func testNoWindowsMeansNothingToShow() {
        let bare = report([:])
        XCTAssertTrue(bare.availableWindows.isEmpty)
        XCTAssertNil(bare.initialWindow)
        XCTAssertNil(bare.defaultMove)
        XCTAssertTrue(bare.moves.isEmpty)
    }

    // MARK: - The default

    /// Pinned deliberately. Intraday looks livelier and is frozen from Friday's
    /// close to Monday's open, so the caption "today" quietly goes stale for sixty-
    /// four hours every week. A week always contains trading.
    func testDefaultWindowIsOneWeek() throws {
        XCTAssertEqual(Report.defaultWindow, .oneWeek)
        XCTAssertTrue(ReturnWindow.intraday.isSessionBound)
        XCTAssertFalse(ReturnWindow.oneWeek.isSessionBound)

        let subject = report(try decoded().trailingReturns)
        XCTAssertEqual(subject.initialWindow, .oneWeek)
        XCTAssertEqual(subject.defaultMove?.window, .oneWeek)
    }

    func testFallsBackToTheShortestAvailableWhenTheDefaultIsAbsent() {
        XCTAssertEqual(report([.oneMonth: -10, .oneYear: 100]).initialWindow, .oneMonth)
    }

    // MARK: - Cycling

    func testCyclingWrapsThroughEveryAvailableWindow() throws {
        let subject = report(try decoded().trailingReturns)

        var window = try XCTUnwrap(subject.initialWindow)
        var visited = [window]
        for _ in 1..<subject.availableWindows.count {
            window = subject.window(after: window)
            visited.append(window)
        }
        XCTAssertEqual(Set(visited), Set(subject.availableWindows), "Every window must be reachable.")
        XCTAssertEqual(visited.count, Set(visited).count, "No window may be visited twice before wrapping.")
        // One more advance wraps to where the rotation started.
        XCTAssertEqual(subject.window(after: window), visited[0])
    }

    func testCyclingSkipsWindowsThePayloadLacks() {
        let sparse = report([.oneWeek: 10, .oneYear: 100])
        XCTAssertEqual(sparse.window(after: .oneWeek), .oneYear)
        XCTAssertEqual(sparse.window(after: .oneYear), .oneWeek)
    }

    /// A tap must not land on a window with no figure behind it, so with one window
    /// cycling is a no-op rather than a jump to something absent.
    func testCyclingASingleWindowStaysPut() {
        let single = report([.oneYear: 100])
        XCTAssertEqual(single.window(after: .oneYear), .oneYear)
        XCTAssertEqual(single.availableWindows, [.oneYear])
    }

    // MARK: - Formatting

    /// The window is always named. The live account is up on the week and down on
    /// the month, so a bare arrow would be an editorial choice pretending to be a
    /// fact.
    func testChipNamesTheWindow() {
        let move = MarketMove(window: .oneWeek, gain: 18.40, total: 12_480.50)
        let chip = Format.moveChip(move)
        XCTAssertTrue(chip.hasPrefix("▲ "), chip)
        XCTAssertTrue(chip.contains(Format.signedEuro(18.40, decimals: 2)), chip)
        XCTAssertTrue(chip.hasSuffix("this week"), chip)
    }

    func testFlatChipCarriesNoLeadingSpace() {
        let chip = Format.moveChip(MarketMove(window: .intraday, gain: 0, total: 1_000))
        XCTAssertFalse(chip.hasPrefix(" "), chip)
        XCTAssertTrue(chip.hasSuffix("today"), chip)
    }

    func testRowCarriesTheDerivedPercentage() {
        let row = Format.moveRow(MarketMove(window: .oneMonth, gain: -260.10, total: 12_480.50))
        XCTAssertTrue(row.contains("this month"), row)
        XCTAssertTrue(row.contains("▼"), row)
        XCTAssertTrue(row.contains("−2.0%"), row)
    }

    /// The sign is carried once, by an explicit prefix on the magnitude — printing
    /// a negative fraction through `percent` would give `-2.0%` with a hyphen where
    /// every other figure in the app uses a real minus sign.
    func testRowUsesARealMinusSign() {
        let row = Format.moveRow(MarketMove(window: .oneMonth, gain: -260.10, total: 12_480.50))
        XCTAssertFalse(row.contains("-2.0%"), row)
    }

    // MARK: - Text output

    func testTextReportCarriesTheMarketSection() throws {
        let text = report(try decoded().trailingReturns).textReport()
        XCTAssertTrue(text.contains("Market"), text)
        XCTAssertTrue(text.contains("this week"), text)
        XCTAssertTrue(text.contains("this month"), text)
        XCTAssertFalse(text.contains("2 days"), "TWO_DAYS is not offered.")
        XCTAssertFalse(text.contains("all time"), "MAX is not offered.")
    }

    func testTextReportOmitsTheSectionWithNoWindows() {
        XCTAssertFalse(report([:]).textReport().contains("\nMarket"))
    }
}
