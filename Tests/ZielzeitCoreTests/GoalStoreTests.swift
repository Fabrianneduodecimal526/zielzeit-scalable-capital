import XCTest
@testable import ZielzeitCore

final class GoalStoreTests: XCTestCase {

    /// An isolated defaults domain so tests never touch the real preferences.
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.zielzeit.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Persistence

    func testGoalIsNilBeforeAnythingIsSet() {
        let store = GoalStore(defaults: defaults, environment: [:])
        XCTAssertNil(store.goal)
    }

    func testGoalRoundTrips() {
        let store = GoalStore(defaults: defaults, environment: [:])
        store.setGoal(100_000)
        XCTAssertEqual(store.goal, 100_000)
    }

    func testEnvironmentOverrideWinsOverStoredValue() {
        let store = GoalStore(defaults: defaults, environment: ["ZIELZEIT_GOAL": "250000"])
        store.setGoal(100_000)
        XCTAssertEqual(store.goal, 250_000)
    }

    func testNonsenseEnvironmentOverrideFallsBackToStoredValue() {
        let store = GoalStore(defaults: defaults, environment: ["ZIELZEIT_GOAL": "banana"])
        store.setGoal(100_000)
        XCTAssertEqual(store.goal, 100_000)
    }

    // MARK: - Input parsing

    func testPlainNumber() {
        XCTAssertEqual(GoalStore.parseAmount("100000"), 100_000)
    }

    func testEuropeanGrouping() {
        XCTAssertEqual(GoalStore.parseAmount("100.000"), 100_000)
        XCTAssertEqual(GoalStore.parseAmount("1.000.000"), 1_000_000)
    }

    func testAngloGrouping() {
        XCTAssertEqual(GoalStore.parseAmount("100,000"), 100_000)
        XCTAssertEqual(GoalStore.parseAmount("1,000,000"), 1_000_000)
    }

    func testSpaceGrouping() {
        XCTAssertEqual(GoalStore.parseAmount("100 000"), 100_000)
        XCTAssertEqual(GoalStore.parseAmount("100\u{202F}000"), 100_000)
    }

    func testCurrencySymbolIsIgnored() {
        XCTAssertEqual(GoalStore.parseAmount("€100000"), 100_000)
        XCTAssertEqual(GoalStore.parseAmount("100000 EUR"), 100_000)
        XCTAssertEqual(GoalStore.parseAmount("  €100.000  "), 100_000)
    }

    func testShorthandSuffixes() {
        XCTAssertEqual(GoalStore.parseAmount("100k"), 100_000)
        XCTAssertEqual(GoalStore.parseAmount("1.5k"), 1_500)
        XCTAssertEqual(GoalStore.parseAmount("2m"), 2_000_000)
    }

    func testDecimalComma() {
        XCTAssertEqual(GoalStore.parseAmount("1500,50"), 1_500.50)
    }

    func testDecimalPointWithAngloGrouping() {
        XCTAssertEqual(GoalStore.parseAmount("100,000.50"), 100_000.50)
    }

    func testDecimalCommaWithEuropeanGrouping() {
        XCTAssertEqual(GoalStore.parseAmount("100.000,50"), 100_000.50)
    }

    func testSmallDecimalIsNotMistakenForGrouping() {
        // Two trailing digits after a point is a genuine decimal.
        XCTAssertEqual(GoalStore.parseAmount("1500.50"), 1_500.50)
    }

    func testRejectsNonNumbers() {
        for input in ["", "   ", "banana", "€", "k", "-", "abc123def"] {
            XCTAssertNil(GoalStore.parseAmount(input), "should reject \(input.debugDescription)")
        }
    }

    func testRejectsZeroAndNegatives() {
        XCTAssertNil(GoalStore.parseAmount("0"))
        XCTAssertNil(GoalStore.parseAmount("-5000"))
    }
}
