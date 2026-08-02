import XCTest
@testable import ZielzeitCore

/// The bundled app and `--once` must read the same preferences domain.
///
/// `UserDefaults.standard` resolves to the main bundle identifier, which the
/// packaged app has and a bare `swift run Zielzeit --once` does not. Relying on
/// it meant a goal set in the app was invisible to the development loop.
final class GoalStoreDomainTests: XCTestCase {

    func testDomainIsNamedExplicitlyAndMatchesTheAppBundleIdentifier() {
        // Must stay in step with CFBundleIdentifier in Info.plist and with the
        // domain `make uninstall` deletes.
        XCTAssertEqual(GoalStore.suiteName, "com.zielzeit.Zielzeit")
    }

    /// Inside the packaged app the suite name equals the bundle identifier, and
    /// `UserDefaults(suiteName:)` refuses that case — it logs "does not make
    /// sense and will not work" and hands back an unusable store. The store has
    /// to fall back to `.standard`, which is already that same domain.
    func testSuiteNamedAfterOwnBundleIdentifierIsRejectedByFoundation() throws {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw XCTSkip("no bundle identifier in this test host")
        }
        let ownSuite = UserDefaults(suiteName: bundleID)
        let sentinel = 987_654.0
        ownSuite?.set(sentinel, forKey: "zielzeit-suite-probe")
        // Foundation does not honour writes to such a suite; if this ever starts
        // working, the fallback in GoalStore can be simplified.
        XCTAssertNotEqual(
            UserDefaults.standard.double(forKey: "zielzeit-suite-probe"), sentinel,
            "Foundation now supports own-bundle-id suites; revisit GoalStore.sharedDefaults()"
        )
        ownSuite?.removeObject(forKey: "zielzeit-suite-probe")
        UserDefaults.standard.removeObject(forKey: "zielzeit-suite-probe")
    }

    func testDefaultStoreDoesNotUseTheStandardDomain() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: GoalStore.suiteName))
        let sentinel = 424_242.0

        let existing = UserDefaults.standard.double(forKey: "goal")
        let previous = suite.double(forKey: "goal")
        defer {
            if previous > 0 { suite.set(previous, forKey: "goal") } else { suite.removeObject(forKey: "goal") }
        }

        suite.set(sentinel, forKey: "goal")
        // A default-initialised store must see the suite value, whether or not
        // the standard domain happens to hold something different.
        XCTAssertEqual(GoalStore(environment: [:]).goal, sentinel)
        XCTAssertNotEqual(sentinel, existing, "sentinel collided with a real standard-domain value")
    }
}
