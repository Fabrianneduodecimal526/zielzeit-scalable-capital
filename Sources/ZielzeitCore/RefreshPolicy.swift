import Foundation

/// When to try again after a refresh has failed.
///
/// The failure this exists for is a Mac waking from sleep: the hourly timer
/// missed its fire date while asleep and goes off immediately on wake, before
/// the network is back, so the first fetch after a wake routinely fails. Without
/// a retry the app would sit on that failure until the user pressed a button.
public enum RefreshPolicy {

    /// Backoff between consecutive failed refreshes, in seconds.
    ///
    /// Starts short because the usual cause clears in seconds, and stops after
    /// the last entry rather than retrying forever — by then the hourly refresh
    /// is the right cadence, and a failure that has survived a quarter of an
    /// hour is not a network still coming up.
    public static let retryDelays: [TimeInterval] = [15, 60, 300, 900]

    /// The delay before the next attempt, or `nil` once the backoff is spent.
    public static func retryDelay(afterFailures failures: Int) -> TimeInterval? {
        guard failures >= 0, failures < retryDelays.count else { return nil }
        return retryDelays[failures]
    }
}
