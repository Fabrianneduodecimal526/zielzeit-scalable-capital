import SwiftUI
import ZielzeitCore

/// The inverse question to `WhatIfSliderView`: pick a year, see what it costs.
///
/// "Save more, arrive sooner" only answers half of what people want to know. The
/// other half is starting from a date — a deadline you already have in mind — and
/// working back to the contribution that meets it.
///
/// Unlike `WhatIfSliderView`, this one deliberately previews **nothing** outside
/// its own section: it does not move the hero year, the chart, or the scenario
/// rows. That is not an oversight. The what-if slider changes an input the whole
/// projection depends on, so everything downstream should follow it; here the
/// year *is* the input the user is choosing and the answer is an amount, so there
/// is nothing for the rest of the popover to restate. Wiring it into the hero
/// would show a year the user themselves just picked.
struct TargetYearSliderView: View {

    @Binding var targetYear: Double
    let report: Report

    /// Clamped, so a value that has not been seeded yet can never render as
    /// year zero.
    private var year: Int {
        min(max(Int(targetYear.rounded()), report.targetYearRange.lowerBound), report.targetYearRange.upperBound)
    }

    private var required: Double? { report.requiredMonthlySavings(byYear: year) }

    /// How the needed amount compares with what is being saved now. Positive
    /// means saving more; negative means this year is reachable on less.
    private var delta: Double? {
        required.map { $0 - report.snapshot.monthlySavings }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel(text: "Reach by")
                Spacer()
                amount
            }

            Slider(
                value: $targetYear,
                in: Double(report.targetYearRange.lowerBound)...Double(report.targetYearRange.upperBound),
                step: 1
            )
            .controlSize(.mini)
            .tint(Theme.color(forScenario: report.headlineLabel))

            HStack(spacing: 0) {
                Text(String(report.targetYearRange.lowerBound))
                Spacer()
                // "end of" is load-bearing, not padding: the horizon runs to
                // December, so at the projected year itself the figure comes out
                // *below* what is saved now — right, but it reads as a mistake
                // unless the extra months are named.
                Text("end of \(String(year))")
                    .font(Theme.numeric(10, weight: .bold))
                    .foregroundStyle(Theme.color(forScenario: report.headlineLabel))
                    .contentTransition(.numericText())
                Spacer()
                Text(String(report.targetYearRange.upperBound))
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)

            if let delta, abs(delta) >= 1 {
                comparison(delta)
            }
        }
    }

    /// The headline of this section: the contribution the chosen year demands.
    @ViewBuilder
    private var amount: some View {
        if let required {
            if required <= 0 {
                // A real answer rather than a blank: far enough out, compounding
                // clears the goal on its own.
                Text("no savings needed")
                    .font(Theme.numeric(11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(Format.euro(required))/mo")
                    .font(Theme.numeric(11, weight: .semibold))
                    .foregroundStyle(Theme.color(forScenario: report.headlineLabel))
                    .contentTransition(.numericText())
            }
        } else {
            Text("—")
                .font(Theme.numeric(11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func comparison(_ delta: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text(
                delta > 0
                    ? "\(Format.euro(delta))/mo more than now"
                    : "\(Format.euro(-delta))/mo less than now"
            )
            // The step-up is why a smaller starting amount can still get there,
            // so naming it here stops the figure reading as a mistake.
            if report.snapshot.dynamizationRate > 0 {
                Text("· to start")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(Theme.caption)
        .foregroundStyle(delta > 0 ? .secondary : Theme.accent)
        .transition(.opacity)
    }
}
