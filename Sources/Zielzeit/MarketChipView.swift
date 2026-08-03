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

    /// Hover alone cannot carry the affordance — see `cycleGlyph` — but it is
    /// what confirms the guess once the eye has been drawn there.
    @State private var isHovering = false

    var body: some View {
        if let onCycle {
            Button(action: onCycle) { chip(cyclable: true) }
                .buttonStyle(.plain)
                .help(Strings.chipHelp(move.windowLabel))
                .onHover { isHovering = $0 }
                // `pointerStyle` rather than pushing an `NSCursor`: the push/pop
                // pair leaks a cursor off the stack whenever the popover closes
                // with the pointer still over the chip, which is the ordinary way
                // it closes. macOS 15 is the deployment target, so this is free.
                .pointerStyle(.link)
        } else {
            chip(cyclable: false)
        }
    }

    private func chip(cyclable: Bool) -> some View {
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

            if cyclable { cycleGlyph }
        }
        .padding(.leading, 6)
        .padding(.trailing, cyclable ? 4 : 6)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(tint.opacity(isHovering ? 0.22 : 0.10))
            // A hairline ring, not just a darker fill. The fill is already a
            // tint of the same hue the figure is drawn in, so brightening it
            // alone reads as the market moving rather than as a control
            // lighting up. An edge appearing is unambiguously a control.
            Capsule().strokeBorder(tint.opacity(isHovering ? 0.45 : 0), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.2), value: move.window)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(Capsule())
    }

    /// The chip's whole discoverability problem in one glyph.
    ///
    /// Everything else about it reads as a badge: a tinted capsule holding a
    /// figure is the shape *every* read-only status pill in this popover takes,
    /// so nothing said it could be turned. Hover and the pointer cursor both
    /// come too late — they answer a question the reader has no reason to ask.
    /// A pair of chevrons is the one mark macOS already spends on "there are
    /// other values behind this one" (it is what a `Menu` and a `Stepper` wear),
    /// and at 7pt it costs six points of a row that had spare width anyway.
    private var cycleGlyph: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.leading, 1)
    }

    private var tint: Color { Theme.color(forDirection: move.direction) }
}
