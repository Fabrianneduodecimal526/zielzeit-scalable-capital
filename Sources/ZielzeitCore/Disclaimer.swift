import Foundation

/// The caveats behind the projected year.
///
/// Kept in `ZielzeitCore` beside the arithmetic it qualifies, so the popover and
/// `--once` state the same things. Deliberately terse: fine print that runs to
/// paragraphs is fine print nobody reads.
///
/// Each line names a real modelling decision in `Projection`, and the ones that
/// only sometimes apply are omitted when they don't — a caveat about a step-up on
/// a plan that has none is worse than no caveat.
public enum Disclaimer {

    public static let headline = "Projections, not predictions"

    public static let notAdvice = "Not financial advice."

    public static func assumptions(for report: Report) -> [String] {
        var lines: [String] = []

        if report.realizedAnnualRate != nil {
            lines.append("Assumes \(Format.percent(report.headlineRate)) every year, from one trailing year.")
            // Only worth saying when it is a guess. With the measured flow the
            // contribution behind the pace is exact; without it the pace is off in
            // whichever direction the plan and any manual buying happen to pull.
            if report.snapshot.trailingContributions == nil {
                lines.append("Pace assumes deposits ran at today's rate all year.")
            }
        } else {
            lines.append("Under a year of history — assumes \(Format.percent(Report.moderateRate)), not your own pace.")
        }

        lines.append("Compounds smoothly. Real returns don't.")

        if report.snapshot.monthlySavings > 0 {
            var line = "Assumes \(Format.euro(report.snapshot.monthlySavings))/mo"
            if report.snapshot.dynamizationRate > 0 {
                line += ", rising \(Format.percent(report.snapshot.dynamizationRate, decimals: 0))/yr"
            }
            line += ", never paused."
            lines.append(line)
        }

        if report.snapshot.dynamizationRate > 0 {
            lines.append("Step-up date is guessed; Scalable doesn't publish it.")
        }

        // Inflation stops being a caveat once the hero states the goal in today's
        // money — at that point the honest line names the assumption behind that
        // figure instead of apologising for its absence.
        if report.realGoalValue != nil {
            lines.append(
                "Before tax; today's money assumes "
                    + "\(Format.percent(Projection.assumedInflation, decimals: 0)) inflation."
            )
        } else {
            lines.append("Before tax and inflation.")
        }

        return lines
    }

    /// The same lines for `--once`.
    public static func textBlock(for report: Report) -> [String] {
        [headline] + assumptions(for: report).map { "  " + $0 } + ["  " + notAdvice]
    }
}
