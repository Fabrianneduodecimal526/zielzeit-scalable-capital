import SwiftUI
import ZielzeitCore

/// Drag to add to the monthly contribution and watch the projection move.
///
/// This is the one interactive part of the app: the maths is pure and instant,
/// so the chart, the scenario years and the headline all follow the drag live.
struct WhatIfSliderView: View {

    @Binding var extraSavings: Double
    let report: Report

    /// Derived in `ZielzeitCore` — the bound is arithmetic, and this layer holds
    /// none. See `Report.extraSavingsCeiling` for why it is what it is.
    private var maximum: Double { report.extraSavingsCeiling }

    private var arrival: (months: Double?, year: Int?, yearsSaved: Double?) {
        report.arrival(extraMonthlySavings: extraSavings)
    }

    /// Shows the resulting contribution, not just the increment, so the number
    /// next to the label is never ambiguous about what it refers to.
    @ViewBuilder
    private var total: some View {
        if extraSavings > 0 {
            HStack(spacing: 3) {
                Text(Format.euro(report.snapshot.monthlySavings))
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text("\(Format.euro(report.snapshot.monthlySavings + extraSavings))\(Strings.perMonth)")
                    .foregroundStyle(Theme.accent)
            }
            .font(Theme.numeric(11, weight: .semibold))
            .contentTransition(.numericText())
        } else {
            Text(Strings.nowPerMonth(Format.euro(report.snapshot.monthlySavings)))
                .font(Theme.numeric(11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel(text: Strings.saveMore)
                Spacer()
                total
            }

            Slider(value: $extraSavings, in: 0...maximum, step: 25)
                .controlSize(.mini)
                .tint(Theme.accent)

            HStack(spacing: 0) {
                Text("+\(Format.euro(0))")
                Spacer()
                Text("+\(Format.euro(maximum))")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }
}
