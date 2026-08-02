import Foundation

/// Display formatting shared by the menu and the `--once` text output, so both
/// render identically from one set of rules.
public enum Format {

    /// Column width for the label in a projection or what-if row. Rows are
    /// drawn in a monospaced font, so padding is what lines the columns up.
    private static let labelWidth = 11
    private static let rateWidth = 7

    private static let euroFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}" // narrow no-break space
        return formatter
    }()

    public static func euro(_ amount: Double, decimals: Int = 0) -> String {
        let formatter = euroFormatter
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let number = formatter.string(from: amount as NSNumber) ?? String(amount)
        return "€\(number)"
    }

    /// Signed amount using a real minus sign, e.g. `+€1 819` / `−€240`.
    public static func signedEuro(_ amount: Double, decimals: Int = 0) -> String {
        (amount >= 0 ? "+" : "−") + euro(abs(amount), decimals: decimals)
    }

    public static func percent(_ rate: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", rate * 100)
    }

    public static func years(_ months: Double) -> String {
        String(format: "%.1f yrs", months / 12)
    }

    /// A duration for prose rather than a data row, e.g. `15.7 years`.
    ///
    /// Short horizons are given in months: "1.5 years" is a stranger way to say
    /// eighteen months, and a decimal fraction of a year reads as false precision
    /// when the whole number is small.
    public static func duration(months: Double) -> String {
        if months < 1 { return "under a month" }
        if months < 24 {
            let whole = Int(months.rounded())
            return whole == 1 ? "1 month" : "\(whole) months"
        }
        return String(format: "%.1f years", months / 12)
    }

    /// The broker's valuation time, dated only when it is not from today.
    ///
    /// A bare `21:00` beside figures struck on Friday reads as this evening, so the
    /// day comes along whenever it is not today's — and stays out of the way when it
    /// is, which is most of the time during the week.
    public static func valuationStamp(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let time = timeFormatter.string(from: date)
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        return "\(dayFormatter.string(from: date)) \(time)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    /// Direction as a glyph. Empty for `flat`: an arrow beside a figure that rounds
    /// to zero claims a move the number does not show.
    public static func arrow(_ direction: MoveDirection) -> String {
        switch direction {
        case .up: return "▲"
        case .down: return "▼"
        case .flat: return ""
        }
    }

    /// The compact market chip, e.g. `▲ €10,07 this week`.
    ///
    /// The window is always named. The sign differs between windows on a real
    /// account — up on the week, down on the month — so an unlabelled arrow would
    /// be an editorial choice pretending to be a fact.
    public static func moveChip(_ move: MarketMove) -> String {
        let glyph = arrow(move.direction)
        let amount = signedEuro(move.gain, decimals: 2)
        return glyph.isEmpty ? "\(amount) \(move.windowLabel)" : "\(glyph) \(amount) \(move.windowLabel)"
    }

    /// One market row for the text output, e.g. `this week    ▲  +€10,07   +0.1%`.
    ///
    /// The label column is two wider than elsewhere: "last session" is exactly
    /// `labelWidth + 1` characters, so at the usual width it butts straight against
    /// the arrow with no space at all.
    public static func moveRow(_ move: MarketMove) -> String {
        let label = pad(move.windowLabel, to: labelWidth + 3)
        let glyph = pad(arrow(move.direction), to: 2)
        let amount = pad(signedEuro(move.gain, decimals: 2), to: 12)
        guard let fraction = move.fraction else { return "\(label)\(glyph) \(amount)" }
        let sign = fraction >= 0 ? "+" : "−"
        return "\(label)\(glyph) \(amount) \(sign)\(percent(abs(fraction)))"
    }

    /// One projection row, e.g. `Moderate    6.0%   2038  (11.6 yrs)`.
    public static func scenarioRow(_ scenario: Scenario) -> String {
        let label = pad(scenario.label, to: labelWidth)
        guard let rate = scenario.annualRate else {
            return "\(label) \(pad("—", to: rateWidth)) not enough history"
        }
        let ratePart = pad(percent(rate), to: rateWidth)
        guard let months = scenario.months, let year = scenario.year else {
            return "\(label) \(ratePart) never at this pace"
        }
        if months == 0 {
            return "\(label) \(ratePart) reached 🎉"
        }
        return "\(label) \(ratePart) \(year)  (\(years(months)))"
    }

    /// One what-if row, e.g. `+€100/mo    2036  (−1.8 yrs)`.
    public static func whatIfRow(_ whatIf: WhatIf) -> String {
        let label = pad("+\(euro(whatIf.extraPerMonth))/mo", to: labelWidth + rateWidth + 1)
        guard let year = whatIf.year else { return "\(label) never" }
        guard let saved = whatIf.yearsSaved, saved > 0.05 else { return "\(label) \(year)" }
        return "\(label) \(year)  (\(String(format: "−%.1f yrs", saved)))"
    }

    /// One "to reach it by" row, e.g. `end of 2028    €770/mo  (+€358)`.
    public static func requiredRow(_ row: (year: Int, required: Double?, delta: Double?)) -> String {
        let label = pad("end of \(row.year)", to: labelWidth + rateWidth + 1)
        guard let required = row.required else { return "\(label) —" }
        guard required > 0 else { return "\(label) nothing — growth alone gets there" }
        let amount = pad("\(euro(required))/mo", to: 12)
        guard let delta = row.delta, abs(delta) >= 1 else { return "\(label) \(amount)" }
        return "\(label) \(amount) (\(signedEuro(delta)) vs now)"
    }

    /// A labelled summary row, e.g. `Portfolio   €11 795.78`.
    public static func summaryRow(_ label: String, _ value: String) -> String {
        "\(pad(label, to: labelWidth + 1))\(value)"
    }

    private static func pad(_ text: String, to width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
