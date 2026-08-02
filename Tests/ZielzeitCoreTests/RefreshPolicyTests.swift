import XCTest
@testable import ZielzeitCore

final class RefreshPolicyTests: XCTestCase {

    /// The first retry has to come quickly: the case it exists for is a wake
    /// with the network still coming up, which clears in seconds.
    func testFirstRetryIsPrompt() {
        XCTAssertEqual(RefreshPolicy.retryDelay(afterFailures: 0), 15)
    }

    func testBackoffLengthens() {
        let delays = (0..<RefreshPolicy.retryDelays.count).compactMap {
            RefreshPolicy.retryDelay(afterFailures: $0)
        }
        XCTAssertEqual(delays.count, RefreshPolicy.retryDelays.count)
        XCTAssertEqual(delays, delays.sorted())
    }

    /// Retrying is bounded: a failure that has outlived the backoff is not a
    /// network coming up, and the hourly refresh is the right cadence for it.
    func testBackoffIsSpentEventually() {
        XCTAssertNil(RefreshPolicy.retryDelay(afterFailures: RefreshPolicy.retryDelays.count))
        XCTAssertNil(RefreshPolicy.retryDelay(afterFailures: 99))
    }

    /// Guards the array index rather than trapping, since the caller counts
    /// failures.
    func testNegativeFailureCountHasNoDelay() {
        XCTAssertNil(RefreshPolicy.retryDelay(afterFailures: -1))
    }

    /// The whole backoff fits inside the hourly refresh, so the two cannot
    /// drift into a gap where nothing is retrying.
    func testBackoffFitsWithinAnHour() {
        XCTAssertLessThan(RefreshPolicy.retryDelays.reduce(0, +), 3600)
    }
}
