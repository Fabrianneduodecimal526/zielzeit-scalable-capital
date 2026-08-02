import Foundation

/// Persistence for the target amount.
///
/// Backed by `UserDefaults` (the app's own preferences domain) rather than a
/// hand-rolled JSON file: it is the idiomatic home for a native app's settings
/// and removes a class of parse and permission errors. `ZIELZEIT_GOAL`
/// overrides it, so `--once` runs are testable without disturbing the real one.
public struct GoalStore {

    private enum Key {
        static let goal = "goal"
    }

    /// The preferences domain everything shares. See `Defaults`.
    public static var suiteName: String { Defaults.suiteName }

    private let defaults: UserDefaults
    private let environment: [String: String]

    public init(
        defaults: UserDefaults? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults ?? Defaults.shared()
        self.environment = environment
    }

    /// The configured goal, or `nil` if unset.
    public var goal: Double? {
        if let override = environment["ZIELZEIT_GOAL"], let parsed = Double(override), parsed > 0 {
            return parsed
        }
        let stored = defaults.double(forKey: Key.goal)
        return stored > 0 ? stored : nil
    }

    public func setGoal(_ amount: Double) {
        defaults.set(amount, forKey: Key.goal)
    }
}

// MARK: - Input parsing

public extension GoalStore {

    /// Parses an amount typed by a person, tolerating the ways money actually
    /// gets written: `100000`, `100.000`, `100 000`, `€100,000.50`, `100k`.
    ///
    /// Returns `nil` for anything that isn't a positive amount.
    static func parseAmount(_ input: String) -> Double? {
        var text = input.lowercased()
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "eur", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let multiplier = extractMultiplier(&text)
        stripGroupingCharacters(&text)
        normalizeDecimalSeparator(&text)

        guard !text.isEmpty, let value = Double(text) else { return nil }
        let amount = value * multiplier
        return amount > 0 ? amount : nil
    }

    /// Consumes a trailing `k` or `m` suffix, returning its scale factor.
    private static func extractMultiplier(_ text: inout String) -> Double {
        if text.hasSuffix("k") {
            text.removeLast()
            return 1_000
        }
        if text.hasSuffix("m") {
            text.removeLast()
            return 1_000_000
        }
        return 1
    }

    /// Removes separators that are never decimal points.
    private static func stripGroupingCharacters(_ text: inout String) {
        for separator in [" ", "\u{00A0}", "\u{202F}", "'", "_"] {
            text = text.replacingOccurrences(of: separator, with: "")
        }
    }

    /// Works out whether remaining `.` and `,` characters are decimal points or
    /// thousands separators, leaving at most one `.` as the decimal point.
    private static func normalizeDecimalSeparator(_ text: inout String) {
        let dots = text.filter { $0 == "." }.count
        let commas = text.filter { $0 == "," }.count

        if dots > 0, commas > 0 {
            // Whichever appears last is the decimal separator.
            guard let lastDot = text.lastIndex(of: "."), let lastComma = text.lastIndex(of: ",") else { return }
            if lastDot > lastComma {
                text = text.replacingOccurrences(of: ",", with: "")
            } else {
                text = text.replacingOccurrences(of: ".", with: "")
                text = text.replacingOccurrences(of: ",", with: ".")
            }
            return
        }

        if commas > 0 {
            // A lone comma with exactly two trailing digits is a decimal comma;
            // anything else is European grouping.
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            if commas == 1, parts.last?.count == 2 {
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
            return
        }

        if dots > 1 {
            text = text.replacingOccurrences(of: ".", with: "")
            return
        }

        if dots == 1 {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            // "100.000" is a hundred thousand, not a hundred.
            if parts.count == 2, parts[1].count == 3, parts[0].count <= 3 {
                text = text.replacingOccurrences(of: ".", with: "")
            }
        }
    }
}
