import SwiftUI
import ZielzeitCore

/// How the portfolio moved, in the top-right corner of the hero.
///
/// Placed on the `PROJECTED` label's row rather than beside the progress bar,
/// which was the first instinct. Two reasons it does not belong on the bar: that
/// row has no spare width without shortening the bar, and at goal scale the
/// movement is geometrically invisible anyway — a month's −€234 against a
/// €100 000 goal is 0.23pp, about half a point of a 220pt bar. Text carries a
/// magnitude the bar cannot.
///
/// Tapping rotates the window. That is not a convenience: the sign genuinely
/// differs between windows — the account this was built against is up on the week
/// and down on the month — so any single default is an editorial choice. Letting
/// the reader turn it makes the choice theirs.
struct MarketChipView: View {

    let move: MarketMove
    /// `nil` when the payload carries only one window, which leaves nothing to
    /// rotate to and so no reason to look tappable.
    let onCycle: (() -> Void)?

    var body: some View {
        if let onCycle {
            Button(action: onCycle) { chip }
                .buttonStyle(.plain)
                .help(Strings.chipHelp(move.windowLabel))
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: 3) {
            let glyph = Format.arrow(move.direction)
            if !glyph.isEmpty {
                Text(glyph)
                    // Smaller than the figure beside it: the caret is a sign, not a
                    // number, and at the same size it shouts.
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(tint)
            }

            Text(Format.signedEuro(move.gain, decimals: 2))
                .font(Theme.numeric(10, weight: .semibold))
                .foregroundStyle(tint)
                // Rolls the digits when the window changes rather than cross-fading,
                // so a tap reads as the same figure being recomputed.
                .contentTransition(.numericText())

            Text(move.windowLabel)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(tint.opacity(0.10))
        }
        .animation(.snappy(duration: 0.2), value: move.window)
        .contentShape(Capsule())
    }

    private var tint: Color { Theme.color(forDirection: move.direction) }
}
