import SwiftUI
import ZielzeitCore

/// Fine print: one line always visible, expanding to the assumptions behind the
/// projected year.
///
/// Collapsed by default, but never dismissible and never buried in a menu — a
/// 44pt year with nothing beside it reads as a fact.
struct DisclaimerView: View {

    let report: Report

    @State private var isExpanded: Bool

    /// Seeded through `State(initialValue:)` rather than in `onAppear`, which
    /// `ImageRenderer` never fires — that is what makes `--render caveats` work.
    init(report: Report, initiallyExpanded: Bool = false) {
        self.report = report
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    // Same 13pt column as the facts rows above, so the fine print
                    // reads as the last item in that list rather than a stray line.
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 13)
                    Text(Disclaimer.headline)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Disclaimer.assumptions(for: report) + [Disclaimer.notAdvice], id: \.self) {
                        Text($0)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                // Aligned under the headline's text, past the symbol column.
                .padding(.leading, 18)
                .transition(.opacity)
            }
        }
    }
}
