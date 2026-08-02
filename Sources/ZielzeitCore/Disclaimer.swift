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

    public static var headline: String { Strings.disclaimerHeadline }

    public static var notAdvice: String { Strings.notAdvice }

    public static func assumptions(for report: Report) -> [String] {
        var lines: [String] = []

        if report.realizedAnnualRate != nil {
            lines.append(Strings.assumesRate(Format.percent(report.headlineRate)))
            // Only worth saying when it is a guess. With the measured flow the
            // contribution behind the pace is exact; without it the pace is off in
            // whichever direction the plan and any manual buying happen to pull.
            if report.snapshot.trailingContributions == nil {
                lines.append(Strings.paceAssumesDeposits)
            }
        } else {
            lines.append(Strings.underAYearOfHistory(Format.percent(Report.moderateRate)))
        }

        lines.append(Strings.compoundsSmoothly)

        if report.snapshot.monthlySavings > 0 {
            lines.append(Strings.assumesContribution(
                Format.euro(report.snapshot.monthlySavings),
                stepUp: report.snapshot.dynamizationRate > 0
                    ? Format.percent(report.snapshot.dynamizationRate, decimals: 0)
                    : nil
            ))
        }

        if report.snapshot.dynamizationRate > 0 {
            lines.append(Strings.stepUpDateGuessed)
        }

        // Inflation stops being a caveat once the hero states the goal in today's
        // money — at that point the honest line names the assumption behind that
        // figure instead of apologising for its absence.
        if report.realGoalValue != nil {
            lines.append(Strings.beforeTaxWithInflation(
                Format.percent(Projection.assumedInflation, decimals: 0)
            ))
        } else {
            lines.append(Strings.beforeTaxAndInflation)
        }

        return lines
    }

    /// The same lines for `--once`.
    public static func textBlock(for report: Report) -> [String] {
        [headline] + assumptions(for: report).map { "  " + $0 } + ["  " + notAdvice]
    }
}
