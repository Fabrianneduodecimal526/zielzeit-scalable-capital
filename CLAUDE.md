# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**Zielzeit** (German: "finish time") is a macOS menu bar app that answers one question: *when will my
portfolio reach my goal amount?* The menu bar shows progress and a projected arrival year, e.g.
`🎯 12% · 2037`; clicking it opens a SwiftUI popover with a progress ring, a projection chart, the
three scenarios, and a slider that previews saving more.

## Data source

All portfolio data comes from the official **Scalable CLI** (`sc`, installed at
`/opt/homebrew/bin/sc`) — never from scraping or unofficial APIs. Only read-only commands are used,
always with `--json`:

- `sc broker overview --json` — current portfolio value (`data.result.valuation.total`) and trailing
  returns (`data.result.performance[]`, entries keyed by `timeframe`, with `simpleAbsoluteReturn` in
  EUR). **All eight windows are read**, not just `ONE_YEAR`: `INTRADAY`, `TWO_DAYS`, `ONE_WEEK`,
  `ONE_MONTH`, `THREE_MONTHS`, `SIX_MONTHS`, `ONE_YEAR`, `MAX` → `snapshot.returns`, keyed by
  `ReturnWindow`. An unrecognised `timeframe` is skipped rather than failing the decode — this is the
  same call the valuation comes from, so a new window must not take the portfolio read down.
  **Each entry also carries a `performance` field, and it is useless: the live CLI returns `0` for
  every window**, including ones with a four-figure `simpleAbsoluteReturn`. Percentages are therefore
  derived in `MarketMove` as `gain / (total − gain)`; don't "fix" this by reading `performance`.
  `data.result.timestamps.valuation_timestamp_utc` is the broker's **as-of time**, which outside
  trading hours sits at the previous session's close (Friday 21:00 UTC all weekend) — that is the
  difference between "fetched a minute ago" and "a minute old", and it drives both the footer stamp and
  the intraday label. There is **no inception date** anywhere in this payload, so the account's age
  cannot be read and `MAX` cannot be annualised
- `sc broker savings-plans --json` — monthly contribution rate
  (`data.result.total_savings_plan_amount`) and, per plan in `data.result.items[]`,
  `dynamization_rate` — the **annual** step-up Scalable applies to a savings plan (whole percent, so
  `5` means 5% p.a., *not* per month; the options in their UI are 2/3/5/8%). `items` is decoded
  optionally: crypto plans carry no rate and older payloads have no `items` at all, and a required key
  would fail the whole response as "savings plans stopped loading"
- `sc broker transactions --json --page-size 100 --from-time <iso>` — the trailing year's cash flow,
  summed into `snapshot.trailingContributions` so the Dietz contribution is measured rather than
  inferred from the current plan rate. Paged via `data.result.cursor` (an *empty string* also means no
  more pages, so both cases are handled), and only `cash_transaction_type` `DEPOSIT`/`WITHDRAWAL` are
  counted — see the projection notes for what else appears here and why it must not count
- `sc whoami --json` — cheapest session check; also yields the first name
  (`data.result.personOverview.personalDetails.firstName`)
- `sc installation-code --json` — needs no session. **Its payload sits directly under `data`**
  (`display_code`, `installation_code`), not under `data.result` like the broker commands — hence
  `decodeDirect` alongside `decode`

Most responses are wrapped in `{ok, command, data: {result}}`; check `ok`, not just the exit status.

**The CLI is in beta and gated.** A client must be allowlisted by Scalable Capital before it can log
in at all — the user emails their installation code to `cli.beta@scalable.capital` with the subject
"Scalable CLI Allowlisting". That human round-trip cannot be automated away, so onboarding is a
checklist (`SetupView`) that makes every step around it one tap.

The request **must come from the email address registered with Scalable Capital** — they match it to
an account by sender, and one sent from another address is silently never answered. A `mailto:` link
opens the default mail account, which frequently is not that address, so `AccessRequest.senderNote`
is called out in both the popover and `--once`. Keep that warning wherever the request is offered.

Three rules here are deliberate and should not be "optimised" away:

- **Never bundle the CLI.** Apache 2.0 permits it, but Scalable's docs ask users to trust only
  official artifacts, and a broker binary inside a third-party app is what that warns against.
- **Never run `sc login`.** Their guidance is that the user completes login themselves, and it is an
  OAuth device-code flow that wants a browser. Zielzeit shows the command and opens Terminal with it
  typed but *not* executed.
- **Recommend `--local-read-only`.** It stores the session in locally enforced read-only mode, which
  makes the read-only promise structural rather than editorial.

**Invoke `sc` by absolute path.** An app launched from Finder or by launchd inherits a minimal `PATH`
that excludes `/opt/homebrew/bin`, so a bare `sc` works from a shell and fails only in the built app.

## Architecture

A SwiftPM package with a strict split: **all arithmetic in `ZielzeitCore`, all UI in `Zielzeit`.**
That is what makes the projections unit-testable and both UI harnesses possible. Keep it that way —
no `import AppKit`/`SwiftUI` in `ZielzeitCore`, no math in the view layer.

- `Sources/ZielzeitCore/` — `Projection` (compounding math, balance curves), `Report` (view model:
  scenarios, chart curves, what-ifs, summary rows), `Formatting`, `ScalableClient` (read-only `sc`
  invocation + decoding), `PortfolioSnapshot` (model + `PortfolioProviding`), `GoalStore`,
  `Setup` (`SetupState`, `AccessRequest`, `SetupStore`, `SetupProbing`), `Disclaimer` (the caveats),
  `MarketMove` (`ReturnWindow`, `MoveDirection`, derived percentages), `Defaults` (shared domain)
- `Sources/Zielzeit/` — `main` (mode dispatch), `AppModel` (`@Observable` state, fetching, actions),
  `StatusItemController` (status item + popover), `PopoverView`/`HeroView`/`ProjectionChartView`/
  `ScenarioListView`/`WhatIfSliderView`/`MarketChipView`/`GoalEditorView`/`SetupView`/`Theme`
  (SwiftUI), `ViewState`, `LaunchAtLogin`, `StatusItemIcon` (menu bar ring), `AppIconArtwork`
  (app icon), `TextMode`, `RenderMode`, `DevState`
- `Tests/ZielzeitCoreTests/` — 229 tests covering the math, curves, view model, amount parsing, and
  decoding against payloads captured verbatim from the real CLI

Targets macOS 15 (`Package.swift` platforms and `LSMinimumSystemVersion` must stay in step). Swift 5
language mode by choice — strict concurrency buys nothing in a single-window menu bar app.

### Projection math

- Trailing annual return via **simple Dietz**: `rate = gain_1y / (total - gain_1y - contributions/2)`
  where `contributions = 12 × monthly`; clamped to ±30%, and `nil` when the denominator is ≤ 0 (a
  portfolio younger than a year, where deposits rather than growth explain the balance).
- Months to goal: `t = ln((G·r + P) / (V·r + P)) / ln(1 + r)`.
- `Projection.balanceSeries` plots the same recurrence forward for the chart, stopping each curve on
  the goal line. A test asserts the curve meets the goal at exactly the month `monthsToGoal` returns
  — if you touch either, that cross-check is what keeps the chart and the headline honest.
- Annual rates convert to monthly **geometrically** (`(1+a)^(1/12) − 1`), applied identically to
  every scenario so comparisons are meaningful.
- Edge cases all covered by tests and which must stay that way: `V ≥ G`, `r = 0` with and without
  savings, and `r < 0`, where — **with flat contributions** — the balance is capped at `−P/r` and a
  goal above that ceiling is genuinely unreachable (returning `nil`, not a bogus year — the naive
  formula takes the log of a negative number here).
- **Dynamization (`snapshot.dynamizationRate`) makes the contribution a step function**, which the
  closed form cannot express. Rather than solve numerically, `monthsToGoal` walks forward one
  twelve-month block at a time, applying the *same* closed form at that year's contribution. Exact,
  and `balance(afterMonths:)` blocks identically, so the chart and the headline still cannot drift.
  Deposits are end-of-month, so deposits 1…12 are at the base amount and **deposit 13 is the first
  raised one** — `ProjectionTests` checks the blocked form against a month-by-month loop at 11/12/13/
  24/25 because an off-by-one here is a whole year of growth and invisible by eye.
- **Nothing in the payload says when the raise fires** (there is a `next_execution_date` for the
  deposit, no dynamization anniversary), so the first raise is put a full twelve deposits out — the
  latest possible raise, hence the most conservative arrival. That is an assumption, not an API fact.
- **A rising contribution dissolves the `−P/r` ceiling**, so a losing rate is no longer automatically
  unreachable: next year's contribution lifts the ceiling, and a goal out of reach today can come into
  reach later. That is why the loop walks forward instead of returning `nil` on the first unreachable
  block, and both halves are tested.
- The slider's extra dynamizes along with the plan, on the reasoning that saving more here means
  raising the Scalable plan and the raised amount carries the same step-up. Treating it as a flat
  standing transfer would report slightly smaller savings.
- **`realizedAnnualRate` measures the past year's contributions rather than estimating them.**
  `snapshot.trailingContributions` is deposits less withdrawals over the trailing year, walked from
  `sc broker transactions`; `12 × monthly` is only the fallback when that cannot be read. An earlier
  version of this file put the estimate's bias "at about 0.2pp" — measured against a live account it was
  **over 1pp**, so that figure was wrong by five times. `ContributionsTests` pins the same gap on
  synthetic figures; the fixtures carry no real account data and must stay that way.
- The estimate errs in **both** directions, because a bigger contribution means a smaller Dietz
  denominator and so a higher rate. A plan that stepped up during the year makes `12 × monthly` too
  large and **overstates** the pace; manual buying out of the same account makes it too small and
  **understates** it, since the extra capital looks like it was invested all year earning the gain.
  There is no safe direction to lean, which is why this is measured instead of corrected for. Both
  directions are tested in `ContributionsTests`.
- **Cash flows only, and that matters.** A custody migration appears as a matched pair of
  `NON_TRADE_SECURITY_TRANSACTION` entries — out one day, back the next, same ISINs, near-identical
  amounts, a day apart. Counted as contributions those would swamp a
  year of deposits and drive the denominator negative, reporting "no measurable pace" on a healthy
  account, so only `cash_transaction_type` of `DEPOSIT`/`WITHDRAWAL` counts. `INTEREST` is excluded as
  well: it is a return the portfolio earned, not money paid in. **Known gap:** securities transferred
  in from another broker are a real contribution that no cash flow records, and nothing in the payload
  tells them apart from a migration.
- The transaction walk is **deliberately non-fatal** (`try?`) and gives up rather than half-measuring:
  a failure part-way through the pages, or a cursor still outstanding at the ten-page cap, returns
  `nil` so the fallback applies. Reporting a partial year as a whole one would be worse than not
  measuring. When the fallback is in use the disclaimer says so — "Pace assumes deposits ran at
  today's rate all year" — and that line is absent when the flow was measured.
- Three scenarios: cautious (3%), moderate (6%), realized "your pace". The slider previews arbitrary
  extra contributions via `Report.arrival(extraMonthlySavings:)`.
- **The menu bar headline uses the realized "your pace" rate, not the moderate 6% assumption.** The
  widget's whole purpose is that the year adapts to how the portfolio is actually performing, so a
  fixed assumption would defeat it. `Report.headlineRate`/`headlineLabel` carry that choice, and the
  what-ifs, `whatIfHeading` and `arrival(extraMonthlySavings:)` all project at the same rate — a
  what-if at 6% against a headline at 23% reports "time saved" that is really just the gap between
  two assumptions, and can come out negative.
- **The fallback turns on whether a pace could be measured, never on whether it is flattering.** No
  realized rate (portfolio under a year, Dietz denominator ≤ 0) falls back to moderate so a new
  portfolio still shows a year. A measured pace too poor to reach the goal yields **no year** (`—`);
  substituting the moderate year there would show a rosy projection exactly when performance is
  worst. Both halves are tested, and the second is easy to "fix" into the first by accident.
- Accept that the headline year now moves with the trailing year — that is the intent, not a bug. A
  flat year pushes it out by several years. A losing year can make it `—`, but only with flat
  contributions: with the live 5% p.a. dynamization the rising contribution escapes the ceiling and a
  year is still reported.
- The slider still never changes the menu bar; it only previews inside the popover. Tests guard that.
- **The "save more" slider's upper bound is `Report.extraSavingsCeiling`**, not a constant: the larger
  of twice the current contribution or enough extra to *halve* the time to the goal, rounded up to a
  round number. Doubling alone scales with saving habit but not with ambition — it was fine for a
  €50 000 goal and stopped a decade short of the interesting part of a €1 000 000 one, while the
  "reach by" slider was happily quoting figures the other slider could not reach. **Halving, not the
  earliest offered target year**: reaching €1 000 000 by next year needs about €55 000/mo, and a slider
  running that far is worse than one stopping too soon. Falls back to doubling when there is no arrival
  to halve. It lives in `ZielzeitCore` because it is arithmetic; the view just reads it.
- **The second slider inverts the question**: pick a year, get the contribution that meets it
  (`Report.requiredMonthlySavings(byYear:)` → `Projection.requiredMonthlySavings`). Solvable in closed
  form even with dynamization, because the balance is `V·(1+r)^t + P·A` and `A` does not depend on `P`:
  `A` is read off by running the *same* forward walk with no capital and a €1 contribution, so the
  inverse cannot disagree with `balance`. A test asserts the round trip lands on the goal to the cent.
  With dynamization the answer is the amount to **start** at.
- **The horizon runs to December of the chosen year**, because "reach it by 2031" means any time in
  2031. Consequence worth keeping in mind: at the projected year itself the figure comes out *below*
  what is being saved now (you would arrive in January, the horizon allows until December), which reads
  as a bug unless the extra months are named — hence the slider label says **"end of 2030"**, not
  "2030". Don't shorten it.
- `0` from that solve means growth alone reaches the goal, and both the slider and `Format.requiredRow`
  say so in words rather than printing `€0/mo`.
- `AppModel.alignSliders(to:)` brings **both** sliders into range on every new report, and both need
  it: the target-year range slides with the calendar, and `extraSavingsCeiling` *shrinks* as the
  portfolio grows (a shorter horizon needs less to halve). A `Slider` holding an out-of-range value
  pins its knob at the end while the preview keeps computing from the stale number, so the hero shows a
  year the slider cannot represent.
- `AppModel.chosenTargetYear` is a **stored** property seeded by `seedTargetYear(for:)` when a report
  arrives. It was briefly a computed get/set binding, and a `Slider` bound to one writes its own
  position back during layout — the knob landed on an arbitrary year instead of the projected one. If
  the slider ever opens on the wrong year again, that is the cause.
- `Theme.headlineGradient(forScenario:_:)` and `areaGradient(forScenario:)` take the headline
  scenario's own hue (amber for "your pace"), so the hero year matches the curve it describes.
  `ScenarioListView` and `ProjectionChartView` key their emphasis off `report.headlineLabel` rather
  than a literal `"Moderate"` — that is what keeps the highlighted row, the thick curve, the area
  fill and the hero from drifting apart.

## Development commands

- `make once` — print the report as text; fastest check of the numbers, no UI
- `make ui [STATE=…]` — rasterize the popover to `.build/ui-{light,dark}.png` via `ImageRenderer`
- `make icons` — draw the menu bar glyph at every progress value, with fit diagnostics
- `make icon` — regenerate `Zielzeit.icns` from `AppIconArtwork` (`make app` depends on it)
- `make open [STATE=…]` — launch with the popover already open, for a real screenshot
- `make shots` — regenerate the README images in `docs/` (always against `Scripts/sc-demo`, never a
  real account). **Scale is a correctness matter here, not a preference:** the README sets each image's
  display width in HTML, so the source must carry at least twice that in pixels or it reads soft on
  every Retina screen. The popover was shown at 380px from a 2× capture (688px = 1.8×), which is why
  it looked blurry; it is `--scale 4` now against a 480px display width, and the menu bar item
  `--scale 8` against 260px. Multiply, don't
  guess: check `sips -g pixelWidth` against the `width=` in the README before shipping new images.
- `make test`, `make run`, `make install`, `make help`

**`make install` needs an admin account.** `/Applications` is `root:admin`, so on a standard (non-admin)
account the `cp` fails — and the `rm -rf` before it is a silent no-op when nothing is installed, so the
failure destroys nothing. `make run` launches the packaged app straight out of the repo and is the
working path there; `sudo make install` or a user-level `~/Applications` are the alternatives.

`STATE` is one of `ready`, `slider`, `target-year`, `market-down`, `no-goal`, `loading`, `failure`,
`editing`, `setup-cli`, `setup-access`, `setup-requested`, `caveats` (see `DevState`). `market-down`
pins the chip to a window that is actually negative, since which ones are changes daily and the losing
colour is otherwise unreviewable on demand.

### Market movement

The year and the percentage barely move between openings, which is what made the app easy to stop
looking at. The fix is not on the progress bar, and that is worth not re-litigating: **at goal scale
market movement is geometrically invisible.** A month's −€234 against a €100 000 goal is 0.23pp — about
half a point of a 220pt bar; a whole year is 3.8pt. Any tick or ghost marker for recent movement is
sub-pixel, the same arithmetic that killed the 66pt hero ring. And recolouring the bar would break what
it means: it is emerald because it measures progress toward the goal, so a red bar at 12% reads as
"12% is bad", not "this month was down". The movement lives in text and a caret instead.

- **`Report.defaultWindow` is `ONE_WEEK`, deliberately, and not intraday.** Intraday looks livelier and
  is frozen from Friday's close to Monday's open, so the liveliest-looking window spends sixty-four
  hours a week stale under a caption reading "today" (`ReturnWindow.isSessionBound` marks it). A week
  always contains trading. A test pins the choice.
- **`ReturnWindow.cyclable` excludes `TWO_DAYS` and `MAX`.** `TWO_DAYS` is indistinguishable from
  `INTRADAY` whenever the market is shut — the fixture shows both at the same figure — and "two days"
  is not a window anyone thinks in. `MAX` is the account's whole life, not a recent move.
- **The window is always named on screen, and that is a correctness matter, not a label.** The sign
  genuinely differs between windows: an account can be up on the week and **down on the month**. A
  bare arrow with no window attached would be picking whichever answer flattered, which is the same
  thing the fallback-rate rule already refuses.
- **Tapping the chip rotates the window** (`Report.window(after:)`, cycling only through windows the
  payload actually carries, wrapping at the end). With one window it is a no-op and `MarketChipView`
  is handed a `nil` cycle action so it does not look tappable.
- `AppModel.marketWindow` is an **override**, `nil` meaning "use `Report.initialWindow`" — so the chip
  follows the default until the reader chooses, and `alignMarketWindow(to:)` drops a chosen window a
  new payload no longer reports. Same class of bug as a `Slider` holding an out-of-range value, which
  is why `AppModel.align(to:)` now does both (it was `alignSliders(to:)`).
- `MoveDirection.flat` for anything under half a cent, drawn as **no arrow at all**: a caret beside a
  figure that prints as `€0,00` claims a move the number does not show.
- `snapshot.oneYearGain` is now a **computed view onto `snapshot.returns[.oneYear]`**, not its own
  field. Storing it twice would let the Dietz rate and the "past year" window disagree about one
  number. The `oneYearGain:` initialiser parameter still works and writes into `returns`.

**Menu bar caret.** A small triangle beside the ring, emerald up / red down, contrast picked from
`isDarkBar` exactly as the digits are. Two things about it:

- **It is drawn into the *image*, not the button's title.** Colouring one glyph via `attributedTitle`
  takes the whole string out of AppKit's automatic handling, so the year stops inverting when the
  popover highlights the status item. Drawing it costs a wider canvas and leaves `button.title` plain.
- `StatusItemController.observeTitle()` **must track `menuBarDirection`** alongside `menuBarText` and
  `iconProgress`, or the caret keeps the previous refresh's direction whenever a fetch moves the market
  but not the year or the percentage — which is most of them.
- The menu bar always uses the default window: a status item has nothing to tap, so unlike the popover
  it cannot let the reader choose. Judge the caret with `make icons` (it draws up/down/flat at 6×),
  never by eye from a screenshot of the real bar.

**Freshness.** `snapshot.valuationDate` carries the broker's as-of time, and two things read it:

- `Report.isValuationCurrent` → `ReturnWindow.label(isCurrentSession:)` demotes **"today" to "last
  session"** when the valuation is not from today. Only the intraday window changes; every other one is
  a trailing span ending at the valuation, so its name stays true either way. Resolved once into
  `MarketMove.windowLabel` so the chip and `--once` cannot name the same figure differently.
- The footer shows **"Valued <stamp>" in preference to the fetch time**, with the fetch time moved to
  the tooltip. A weekend fetch of Friday's close used to be stamped with the minute it was asked for,
  which claimed a freshness the figures do not have. `Format.valuationStamp` adds the day only when it
  is not today's — a bare `11:00 PM` beside Friday's figures reads as this evening.
- **A missing timestamp counts as current.** No evidence of staleness is not evidence of staleness, and
  the alternative is captioning perfectly fresh figures as belonging to a previous session.

### Purchasing power

`Report.realGoalValue` restates the goal in today's money at the projected horizon
(`Projection.realValue`, discounting geometrically at `Projection.assumedInflation` = 2%). The hero
carries it as a small line under the sentence — *"that's about €91 775 in today's money"* — and `--once`
as an `In today's money` block.

- **Always shown, not behind a toggle.** Over the horizons this app quotes, inflation is the largest
  single gap between the headline and reality — larger than anything else the disclaimer lists — and a
  caveat behind a disclosure triangle is one nobody reads.
- **The goal is discounted, not the contribution inflated.** The goal is the number the user chose and
  the one they picture, so restating it is what makes the erosion legible: "€100 000 then is €91 775
  now" lands where "you'll need €108 000" does not.
- Absent under a twelve-month horizon (the restatement would be the same figure), when there is no
  arrival to discount to, and while the slider is previewing — two amounts moving at once is one too
  many.
- **The disclaimer's inflation line is now conditional**: "Before tax; today's money assumes 2%
  inflation." when the figure is on screen, "Before tax and inflation." when it is not. Asserted in both
  directions, because a caveat claiming the projection ignores inflation while an inflation-adjusted
  figure sits on screen is exactly the drift those tests exist to catch.

**Menu bar icon.** A progress ring drawn in `StatusItemIcon` with the percentage *inside* it (a
checkmark at 100%), and the projected year beside it as text (`Report.menuBarText` — the year alone,
since the ring carries the percentage). `Report.statusTitle` still holds the older one-line
`🎯 23% · 2030` form, now used by `--once` only. **The status item deliberately has no tooltip**
(`button.toolTip = nil`): hovering repeated what the ring and year already show.

`StatusItemIcon.Style` has three variants and the default is deliberate:

- `.brand` (in use) — the app icon's gradient ring, in colour. Because it is *not* a template image,
  AppKit will not retint it, so it must pick its own contrast from the bar (`isDarkBar`) **and** be
  redrawn when the theme changes. `StatusItemController.observeAppearance()` does that via
  `AppleInterfaceThemeChangedNotification`, reading `effectiveAppearance` a beat later because the
  notification arrives before it updates. Delete that observer and the icon silently keeps the old
  theme's colours.
- `.template` — the monochrome original, which AppKit tints for free. Kept as the fallback if the
  colour version ever proves a problem.
- `.plate` — the full app icon, squircle and all. **Rejected, and worth not re-litigating:** the plate
  costs roughly a third of the digit size at 20pt (compare `make icons` against
  `--icons … --plate`), and a dark squircle on a dark menu bar barely reads as a shape.

The `unset` and `warning` states stay SF Symbol templates, so those still adapt automatically.

Judge the glyph with `make icons` (add `--plate` or `--template` to compare), never by eye from a
screenshot of the real bar: at 20pt, magnification blur reads as digits colliding with the stroke when
they are not. `--icons` prints a fit ratio per value for exactly that reason.

**Hero layout.** Full width, stacked: label *and the market chip on the same row*, year at 44pt, the
sentence, then a slim progress bar. The chip shares the label's row because that row's right-hand side
was empty, so it costs no height — and the top-right corner is where a ticker reads naturally.
**The 66pt progress ring it used to sit beside is gone, on purpose** — at the fractions this app
actually shows (1% against a €1m goal) a ring is a nub on a near-empty track, which reads as a
rendering fault rather than as progress, and it consumed the third of the width the sentence needed,
forcing a large goal onto two lines. `ProgressBar` replaces it and inherits the ring's one real lesson:
a round-capped fill narrower than its own height renders as a floating dot, so the fill has a width
floor. The percentage label beside it is fixed at 36pt — sized for `100%`, which truncates to `10…` if
that width is set by eye from a low value. The bar stays emerald even when the headline is amber,
because it measures progress toward the goal rather than the projection. The menu bar keeps its ring;
that one carries a percentage inside it at 20pt and works there.

**The facts list carries only Portfolio, Saving and Past year.** Goal and Remaining were removed: the
hero states the goal amount in prose and the bar states the percentage, so both rows restated the top
of the popover in a smaller font. One consequence to accept — the goal amount now appears **once**, in
the hero sentence, and `Remaining` is not shown at all.

**The chart's goal line is deliberately unlabelled.** The hero states the goal amount immediately
above it, and annotating the `RuleMark` too put the same figure twice within a few points of vertical
space. Curves stopping dead on the line carry it.

**Hero caption.** Prose rather than a data row: `In 15.6 years you'll have about €1 000 000`, from
`Format.duration(months:)` (which switches to whole months under two years, since "1.5 years" is a
strange way to say eighteen months). It is built by **concatenating `Text` runs**, not as one string,
so the two figures carry weight the joining words do not — `HeroView.projection(months:)`. The amount
takes the goal's emerald rather than the headline hue: the 44pt year directly above is already amber,
and a second amber number beside it competes instead of complementing. The duration comes *first* so a
large goal wraps before the amount instead of stranding "in" at the end of a line, and the `Text`
needs both `.lineLimit(2)` and `.fixedSize(horizontal: false, vertical: true)` or SwiftUI truncates it
mid-figure rather than wrapping. The balance-so-far that used to sit here is in the Portfolio and Goal
rows.

**App icon.** Also drawn in code (`AppIconArtwork`), emitted as an `.iconset` by `--appicon` and
converted by `make icon` into `Zielzeit.icns`, which is committed and copied into
`Contents/Resources` by `make app` (`CFBundleIconFile` in `Info.plist`). Two drawing gotchas are
already paid for: AppKit cannot stroke with a gradient, so the arc's gradient comes from
`CGPath.copy(strokingWithWidth:)` and clipping to that outline; and a radial highlight whose bounds
fall inside the plate leaves its own edge visible as a crescent, so the sheen is linear.

**The disclaimer.** `Disclaimer.assumptions(for:)` builds the caveats *from the report*, so they quote
the rate, contribution and goal actually on screen — "assumes a constant return" is easy to nod past,
"assumes 22.7% every year" is not. Three of the lines are conditional and must stay that way: no claim
of a measured pace when the rate is the moderate fallback, no step-up caveat for a flat plan, no
contribution caveat without a savings plan. `DisclaimerTests` asserts each of those in *both*
directions, since only the absence assertions catch a caveat that has stopped matching the arithmetic.

One line each, under 70 characters, enforced by a test: an earlier draft ran to five sentences of
hedging and read as filler, which is a disclaimer nobody takes in. `DisclaimerView` shows the headline
collapsed and expands to the list — collapsed by default, never dismissible, never behind a menu, since
a 44pt year with nothing beside it reads as a fact. `initiallyExpanded` seeds `@State` through
`State(initialValue:)` rather than `onAppear`, which `ImageRenderer` never fires; that is what makes
`STATE=caveats` render the open state.

**Exit codes for `--once`:** `0` success, `1` read failure, `2` no goal set, `3` setup incomplete.

**Verifying UI changes.** A popover cannot be opened by a script without accessibility permission, so
there are two harnesses and each has a blind spot:

- `make ui` is offscreen and crisp, but `ImageRenderer` cannot rasterize AppKit-backed controls — the
  slider and the `Menu` come out as coloured blocks. Do not read that as a bug.
- `make open` shows the real thing including those controls, then `screencapture -R<x,y,w,h>` around
  the status item and read the PNG.

**Walking the real onboarding while connected.** `--open setup-access` shows pinned mock states, but
`isPinned` makes "Check again" dead and the installation code is fake. To exercise real detection
without disturbing your session, point `ZIELZEIT_SC_BIN` at a stub that fails everything except
`installation-code`, which it forwards to the real CLI (that command needs no session):

```sh
cat > .build/sc-no-session <<'EOF'
#!/bin/sh
case "$1" in
  installation-code) exec /opt/homebrew/bin/sc "$@" ;;
  *) echo "error: no saved session, please run sc login" >&2; exit 1 ;;
esac
EOF
chmod +x .build/sc-no-session
ZIELZEIT_SC_BIN=$PWD/.build/sc-no-session ./Zielzeit.app/Contents/MacOS/Zielzeit --open &
```

`ZIELZEIT_SC_BIN=/nonexistent/sc` gives the `cliMissing` step the same way. Afterwards, `make run`
restores the real app, and clear the test residue with
`defaults delete com.zielzeit.Zielzeit hasRequestedAccess`.

Environment overrides, honoured by every mode:

- `ZIELZEIT_GOAL` — use a goal without touching the saved one
- `ZIELZEIT_SC_BIN` — point at a stub to exercise failure states (`/usr/bin/false` for no output, a
  script printing `please run sc login` for the auth path)

## Footguns already paid for

- **`GoalStore` domain.** The goal lives in `com.zielzeit.Zielzeit`, reached two different ways:
  inside the packaged app that name *is* the bundle identifier and `UserDefaults(suiteName:)` refuses
  it (logging "does not make sense and will not work" and returning an unusable store), so it falls
  back to `.standard`, which is already that domain. Outside the bundle `.standard` is a *different*
  domain, so the suite is required. Get this wrong and a goal set in the app is invisible to `--once`,
  or the app silently stops persisting.
- **Sleep wipes the data unless a failed refresh keeps the last report.** The hourly timer misses its
  fire date while the Mac sleeps and goes off *immediately* on wake, before the network is back, so
  the first fetch after every wake fails. `AppModel.apply` therefore keeps a `.ready` report on
  failure and only records `staleReason` (an orange marker in the footer, the reason in its tooltip);
  `.failure` is for when there is nothing to show. Setup problems still take over the state, since
  those need the user. Recovery is automatic from two sides: `RefreshPolicy`'s backoff (15s, 1m, 5m,
  15m, then the hourly refresh takes over) and `StatusItemController.observeWake()`, which refetches
  five seconds after `NSWorkspace.didWakeNotification`. Revert either half and the menu bar drops its
  year overnight and waits for a click.
- **Popover sizing.** `NSHostingController.sizingOptions = [.preferredContentSize]` is required, or
  the popover keeps a default size, centres the content, and clips the bottom.
- **Keyboard focus.** The goal field needs `NSApp.activate(ignoringOtherApps:)` when the popover
  opens; an accessory app's transient popover will not take key input otherwise.
- **Pinned dev states.** Opening the popover calls `refreshIfStale()`, which would overwrite a state
  forced by `--open`/`--render`; `DevState` sets `AppModel.isPinned` to prevent that.
- **Setup probing is cached.** `AppModel.isKnownConnected` stops the `whoami` probe running on every
  hourly refresh. It is cleared when a fetch fails with `.notLoggedIn`/`.notInstalled`, which sends
  the user back to the onboarding steps instead of a dead-end error.
- **`notConnected` is genuinely ambiguous.** Whether a failing session means "not allowlisted" or
  "not logged in" cannot be told apart without starting a login, so the UI shows both steps rather
  than guessing. `SetupStore.hasRequestedAccess` records the part that is not detectable.

## Constraints

- Never invoke `sc broker trade ...` or any write command. This project is strictly read-only against
  the broker, and `ScalableClient.Command` enumerates the only five commands it may run: `broker
  overview`, `broker savings-plans`, `broker transactions`, `whoami`, `installation-code`.
- Ask the user before installing anything on their machine or creating files outside this repo.
