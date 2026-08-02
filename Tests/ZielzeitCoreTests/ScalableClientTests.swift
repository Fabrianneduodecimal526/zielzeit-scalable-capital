import XCTest
@testable import ZielzeitCore

/// Decoding is tested against payloads captured verbatim from the real CLI, so
/// a change in the `sc` response shape fails here rather than in the menu bar.
final class ScalableClientTests: XCTestCase {

    // MARK: - Fixtures

    /// Shaped from `sc broker savings-plans --json`, including the
    /// `dynamization_rate: 5` that Scalable applies once a year.
    private let dynamizedPlansJSON = """
    {"ok":true,"command":"broker.savings-plans","data":{"account_id":"acc",
    "result":{"account_id":"acc","count":4,"crypto_count":0,"items":[
    {"amount":95.0,"day_of_month":25,"dynamization_rate":5,"frequency":"MONTHLY",
    "isin":"IE00EXAMPLE01","kind":"security","name":"Example World Small Cap (Acc)",
    "next_execution_date":"2026-08-25","security_type":"ETF"},
    {"amount":95.0,"day_of_month":25,"dynamization_rate":5,"frequency":"MONTHLY",
    "isin":"IE00EXAMPLE02","kind":"security","name":"Example Europe (Acc)",
    "next_execution_date":"2026-08-25","security_type":"ETF"},
    {"amount":95.0,"day_of_month":25,"dynamization_rate":5,"frequency":"MONTHLY",
    "isin":"IE00EXAMPLE03","kind":"security","name":"Example Emerging Markets (Acc)",
    "next_execution_date":"2026-08-25","security_type":"ETF"},
    {"amount":95.0,"day_of_month":25,"dynamization_rate":5,"frequency":"MONTHLY",
    "isin":"IE00EXAMPLE04","kind":"security","name":"Example US Large Cap (Acc)",
    "next_execution_date":"2026-08-25","security_type":"ETF"}],
    "non_crypto_count":4,"total_savings_plan_amount":380.0}}}
    """

    /// Shaped from `sc broker overview --json` output.
    private let overviewJSON = """
    {"ok":true,"command":"broker.overview","data":{"account_id":"acc","portfolio_id":"pf",
    "result":{"account_id":"acc","performance":[
    {"performance":0,"simpleAbsoluteReturn":96.30,"timeframe":"INTRADAY"},
    {"performance":0,"simpleAbsoluteReturn":-260.10,"timeframe":"ONE_MONTH"},
    {"performance":0,"simpleAbsoluteReturn":1950.0,"timeframe":"ONE_YEAR"},
    {"performance":0,"simpleAbsoluteReturn":2310.0,"timeframe":"MAX"}],
    "portfolio_id":"pf","valuation":{"crypto":0,"securities":12480.50,"total":12480.50}}}}
    """

    /// Shaped from `sc broker savings-plans --json` output, from before
    /// the `items` array was read — kept verbatim so the decoder still copes with
    /// a payload that has no per-plan detail at all.
    private let savingsPlansJSON = """
    {"ok":true,"command":"broker.savings-plans","data":{"account_id":"acc",
    "result":{"count":4,"crypto_count":0,"non_crypto_count":4,
    "total_savings_plan_amount":380.0}}}
    """

    private func data(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - Happy path

    func testDecodesOverview() throws {
        let result = try ScalableClient.decode(
            OverviewResult.self, from: data(overviewJSON), command: "broker overview"
        )
        XCTAssertEqual(result.valuation.total, 12_480.50)
        let oneYear = result.performance?.first { $0.timeframe == Timeframe.oneYear }
        XCTAssertEqual(oneYear?.simpleAbsoluteReturn, 1_950.0)
    }

    func testDecodesSavingsPlans() throws {
        let result = try ScalableClient.decode(
            SavingsPlansResult.self, from: data(savingsPlansJSON), command: "broker savings-plans"
        )
        XCTAssertEqual(result.totalSavingsPlanAmount, 380.0)
        XCTAssertEqual(result.count, 4)
    }

    func testPicksTheOneYearTimeframeAndNotTheFirstEntry() throws {
        // INTRADAY comes first in the payload; taking it would be a silent and
        // very wrong reading of annual performance.
        let result = try ScalableClient.decode(
            OverviewResult.self, from: data(overviewJSON), command: "broker overview"
        )
        let oneYear = result.performance?.first { $0.timeframe == Timeframe.oneYear }?.simpleAbsoluteReturn
        XCTAssertNotEqual(oneYear, 96.30)
        XCTAssertEqual(oneYear, 1_950.0)
    }

    // MARK: - Failure modes

    func testReportedFailureSurfacesTheBrokersMessage() {
        let json = #"{"ok":false,"error":"portfolio unavailable"}"#
        assertThrows(OverviewResult.self, json, expected: .failed("portfolio unavailable"))
    }

    func testFailureWithoutAMessageStillDescribesTheCommand() {
        assertThrows(OverviewResult.self, #"{"ok":false}"#,
                     expected: .failed("`sc broker overview` reported a failure"))
    }

    func testMissingResultIsAnUnexpectedResponse() {
        assertThrows(OverviewResult.self, #"{"ok":true,"data":{}}"#,
                     expected: .unexpectedResponse(command: "broker overview"))
    }

    func testPlainTextLoginPromptIsRecognisedAsAnAuthProblem() {
        assertThrows(OverviewResult.self, "error: no saved session, please run sc login",
                     expected: .notLoggedIn)
    }

    func testExpiredSessionIsRecognisedAsAnAuthProblem() {
        assertThrows(OverviewResult.self, "your session has expired", expected: .notLoggedIn)
    }

    func testUnrelatedGarbageIsAnUnexpectedResponse() {
        assertThrows(OverviewResult.self, "<html>502 Bad Gateway</html>",
                     expected: .unexpectedResponse(command: "broker overview"))
    }

    func testMissingValuationIsAnUnexpectedResponse() {
        // `valuation` is non-optional, so its absence must fail loudly rather
        // than defaulting the portfolio to zero.
        assertThrows(OverviewResult.self, #"{"ok":true,"data":{"result":{"account_id":"acc"}}}"#,
                     expected: .unexpectedResponse(command: "broker overview"))
    }

    // MARK: - Process-level guards

    func testMissingExecutableIsReportedWithItsPath() {
        let client = ScalableClient(executablePath: "/nonexistent/sc")
        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            XCTAssertEqual(error as? ScalableError, .notInstalled(path: "/nonexistent/sc"))
        }
    }

    func testAnExecutableProducingNoOutputIsReportedAsFailure() throws {
        let client = ScalableClient(executablePath: "/usr/bin/true", timeout: 5)
        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            XCTAssertEqual(error as? ScalableError, .failed("`sc` produced no output"))
        }
    }

    func testAHangingExecutableTimesOutInsteadOfBlockingForever() throws {
        // Stands in for a wedged network call. Without the timeout this would
        // freeze the menu bar indefinitely.
        let script = try makeExecutableScript("#!/bin/sh\nsleep 30\n")
        defer { try? FileManager.default.removeItem(at: script) }

        let client = ScalableClient(executablePath: script.path, timeout: 1)
        let started = Date()
        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            XCTAssertEqual(error as? ScalableError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testStderrExplanationIsSurfacedWhenThereIsNoStdout() throws {
        let script = try makeExecutableScript("#!/bin/sh\necho 'broker is down' >&2\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: script) }

        let client = ScalableClient(executablePath: script.path, timeout: 5)
        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            XCTAssertEqual(error as? ScalableError, .failed("broker is down"))
        }
    }

    func testLargeOutputDoesNotDeadlockOnAFullPipeBuffer() throws {
        // A payload well past the 64 KB pipe buffer: if stdout were not drained
        // concurrently with waiting, the child would block and this would hang.
        let script = try makeExecutableScript(
            """
            #!/bin/sh
            printf '{"ok":true,"data":{"result":{"valuation":{"total":12480.50},"performance":[{"timeframe":"ONE_YEAR","simpleAbsoluteReturn":1950.0}],"padding":"'
            for i in $(seq 1 20000); do printf 'xxxxxxxx'; done
            printf '"}}}'
            """
        )
        defer { try? FileManager.default.removeItem(at: script) }

        let client = ScalableClient(executablePath: script.path, timeout: 20)
        // Both commands hit the same script; every savings-plan field is
        // optional, so it decodes to zero. Completing at all is the point —
        // an undrained pipe would block the child and hang this test.
        let snapshot = try client.fetchSnapshot()
        XCTAssertEqual(snapshot.total, 12_480.50)
        XCTAssertEqual(snapshot.oneYearGain, 1_950.0)
        XCTAssertEqual(snapshot.monthlySavings, 0)
    }

    private func makeExecutableScript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zielzeit-test-\(UUID().uuidString).sh")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Helpers

    private func assertThrows<T: Decodable>(
        _ type: T.Type,
        _ json: String,
        expected: ScalableError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ScalableClient.decode(type, from: data(json), command: "broker overview"),
            file: file, line: line
        ) { error in
            XCTAssertEqual(error as? ScalableError, expected, file: file, line: line)
        }
    }

    // MARK: - Dynamization

    func testDynamizationRateIsReadAsAnAnnualFraction() throws {
        let plans = try ScalableClient.decode(
            SavingsPlansResult.self,
            from: Data(dynamizedPlansJSON.utf8),
            command: "broker savings-plans"
        )
        // 5 in the payload means 5% p.a. — a fraction here, not whole percent.
        XCTAssertEqual(plans.dynamizationRate, 0.05, accuracy: 1e-12)
        XCTAssertEqual(plans.totalSavingsPlanAmount, 380.0)
        XCTAssertEqual(plans.items?.count, 4)
    }

    /// A payload predating the field must still decode — a required key would
    /// fail the whole response and read as "savings plans stopped loading".
    func testAPayloadWithoutItemsStillDecodesWithNoDynamization() throws {
        let plans = try ScalableClient.decode(
            SavingsPlansResult.self,
            from: Data(savingsPlansJSON.utf8),
            command: "broker savings-plans"
        )
        XCTAssertNil(plans.items)
        XCTAssertEqual(plans.dynamizationRate, 0)
    }

    /// Weighted by contribution, because what matters is how fast the total
    /// grows: 5% on €300 and nothing on €100 is 3.75% of the €400 total.
    func testMixedRatesAreWeightedByContribution() throws {
        let mixed = """
        {"ok":true,"command":"broker.savings-plans","data":{"result":{"count":2,
        "items":[{"amount":300,"dynamization_rate":5},{"amount":100}],
        "total_savings_plan_amount":400}}}
        """
        let plans = try ScalableClient.decode(
            SavingsPlansResult.self, from: Data(mixed.utf8), command: "broker savings-plans"
        )
        XCTAssertEqual(plans.dynamizationRate, 0.0375, accuracy: 1e-12)
    }
}
