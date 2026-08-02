import Foundation

/// A read-only snapshot of the portfolio — everything a projection needs.
public struct PortfolioSnapshot: Equatable {

    /// Total portfolio valuation in EUR.
    public let total: Double

    /// Every trailing return the broker reported, in EUR, keyed by window.
    ///
    /// The overview payload carries eight of these and the app used to read one.
    /// Keeping them all is what lets the popover rotate windows and the menu bar
    /// show a direction, at no extra cost — they arrive in the call already being
    /// made.
    public let returns: [ReturnWindow: Double]

    /// Trailing one-year absolute return in EUR, when the broker reports one.
    ///
    /// A view onto `returns` rather than its own field. It is what the Dietz rate
    /// consumes and what most of the tests are written against, so it keeps its
    /// name — but storing it twice would let the headline rate and the "past year"
    /// window disagree about the same number.
    public var oneYearGain: Double? { returns[.oneYear] }

    /// Combined monthly savings plan contribution in EUR.
    public let monthlySavings: Double

    /// Number of active savings plans, shown for context in the menu.
    public let savingsPlanCount: Int

    /// Annual dynamization as a fraction, e.g. `0.05` for Scalable's 5% p.a.
    /// step-up. Zero when no plan dynamizes.
    public let dynamizationRate: Double

    /// Net external money that actually arrived over the trailing year — deposits
    /// less withdrawals — or `nil` when it could not be read.
    ///
    /// Kept optional rather than defaulted to `12 × monthlySavings` so the rest of
    /// the app can tell a measured figure from an estimated one, and say which it
    /// used. Someone who runs a savings plan *and* buys by hand out of the same
    /// account is exactly who the estimate gets wrong — there, it credits the
    /// portfolio with capital it never had, and the pace comes out *below* what was
    /// actually achieved.
    public let trailingContributions: Double?

    /// When the broker struck these figures, as opposed to when they were fetched.
    ///
    /// Outside trading hours this sits at the previous session's close — the live
    /// account reports Friday 21:00 UTC all weekend — which is what lets the footer
    /// stop implying the numbers are as fresh as the request, and lets the intraday
    /// window admit it is showing the last session rather than "today".
    ///
    /// `nil` when the broker did not report it, in which case nothing claims
    /// staleness: no evidence of it is not evidence of it.
    public let valuationDate: Date?

    /// `oneYearGain` and `returns` are two spellings of the same storage: whichever
    /// is given lands in `returns`, and giving both is allowed — `returns` wins on
    /// the one-year window, since a caller passing the full set is passing the
    /// broker's own answer.
    public init(
        total: Double,
        oneYearGain: Double? = nil,
        monthlySavings: Double = 0,
        savingsPlanCount: Int = 0,
        dynamizationRate: Double = 0,
        trailingContributions: Double? = nil,
        returns: [ReturnWindow: Double]? = nil,
        valuationDate: Date? = nil
    ) {
        self.valuationDate = valuationDate
        self.total = total
        var windows = returns ?? [:]
        if let oneYearGain, windows[.oneYear] == nil { windows[.oneYear] = oneYearGain }
        self.returns = windows
        self.monthlySavings = monthlySavings
        self.savingsPlanCount = savingsPlanCount
        self.dynamizationRate = dynamizationRate
        self.trailingContributions = trailingContributions
    }
}

/// Source of portfolio data.
///
/// The app layer depends on this rather than on `ScalableClient` directly, so
/// UI behaviour can be exercised against a stub that never touches the network.
public protocol PortfolioProviding {
    func fetchSnapshot() throws -> PortfolioSnapshot
}
