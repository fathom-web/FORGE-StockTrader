# Validation — 0.4.0 (2026-11-06)

## What has actually been checked

- **83/83 automated tests passed on Lua 5.1** (`lupa.lua51`). Includes original arithmetic/history/risk/migration coverage plus priority scheduling, full scope, incremental complete-key publication, pause/resume, automatic deposit adapters, variant/quantity/duration checks, native-quote server totals, unrelated/stale/cancelled/expired quotes, journal duplicate protection, descriptive forecast comparison, and bounded diagnostics.
- The actual Lua UI declarations were rendered with synthetic data through frame mocks for results, details, settings and journal. Visible controls are checked for staying within the 676×421 native content area and for overlap. The four rendered states were visually inspected. Native WoW fonts, textures, taint and screen scaling are not reproduced by that renderer.
- TOC load paths compile; the install package validates every listed Lua dependency and excludes tests/development files.

**No live Forever client was available. No actual auction was bought or sold, and live scan completion remains unverified.** Steps that require a running game and real transaction outcomes cannot be declared complete by offline tests.

## API evidence inspected

Source files inspected on the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source):

- `Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua`: full browse/search results, pagination, throttle readiness, replicate completeness, deposit API signatures, restricted commodity-quote start, cancellation and quote price-event payloads.
- `Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua`: native `SelectBrowseResult` navigation and native commodity confirmation flow. The user requests the native quote; the addon only observes the API request and its events.
- `Blizzard_AuctionHouseCommoditiesBuyFrame.lua` and `Blizzard_AuctionHouseItemSellFrame.lua` in that same folder: native commodity buy interaction and `CalculateItemDeposit(itemLocation, duration, quantity)` usage.
- [ForeverPlusPlus API notes](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md): supporting field evidence for browse pagination/shared throttle and lack of demonstrated replicate completion. API existence is not treated as proof of live server behaviour.

The earlier requested wiki ReplicateItems page returned HTTP 403. No unverified retail commission rate was imported. Commission is set by the user; live deposit API values are labelled by source. Missing automatic deposit information does not become zero.

## Scan invariants and scope

1. Full browse pagination establishes the index only. Aggregate minima are scheduling hints.
2. Quick mode selects 60 supported keys by default (10–300 configurable); full mode selects all. The UI states both selected and market key counts.
3. Each selected key requires complete result pagination and successful item-data resolution before publication. Row batches are <=100 per tick; group analysis runs one pending variant per tick.
4. Successfully completed keys produce immediate results/history. If a later key fails, those earlier independent observations remain; the overall scope stays FAILED/PARTIAL and last successful scope time is unchanged. Incomplete-key rows never publish.
5. Pause drains the current key, then releases the shared query stream. Resume advances to the next key. Verification shares the two-second query budget. Another active query cancels an active scan, not a paused selection.
6. Response/throttle wait limit 45 seconds; a single key has a two-minute limit; full scope has a two-hour limit excluding time paused. Safety bounds: 10000 keys, 200000 rows, 5000 rows per variant. Exceeding a limit fails openly.
7. Own/account, bid-only and pet listings are outside opportunity scope. No invisible truncation claims whole-market verification. Duplicate browse keys are suppressed.
8. Experimental replicate data remains research-only without executable auction identity. The default route no longer depends on it.

## Commodity quote invariants

Depth alone cannot enter Vendor Sell. The player opens the native AH, selects quantity and requests its quote. StockTrader associates the observed start with its selected commodity; unrelated events are ignored. It recalculates using the server's total for the chosen quantity. The addon never invokes Start/ConfirmCommoditiesPurchase or PlaceBid.

A different request supersedes previous advice. Cancellation, unavailable price, purchase result, AH close or five-second expiry removes executable status and clears the native advisory label. Speculative quotes still require history, explicit fee knowledge and risk limits. The native dialog remains the only purchase confirmation.

## Player-run acceptance checklist

| Check | Action | Expected evidence |
|---|---|---|
| Install / layout | Install 0.4.0, enable `/console scriptErrors 1`, open AH with and without Auctionator. | One StockTrader bottom tab; exactly two trading tabs; no clipping at your UI scale. |
| Quick scan | Run Quick scan on a populated AH. | Index loaded is separate from checked keys; first checked results appear before completion; declared quick scope finishes or fails honestly. |
| Pause / verify / resume | Pause after a result appears; reverify it; resume. | Current item completes first, no overlapping queries, selected remaining keys continue. |
| Full scan | Run Full scan while AH otherwise idle. | All supported selected keys checked before full success; responsive UI and usable Stop. |
| Failures | Close AH, start another addon's search, or observe a blocked/timed-out response. | No green completion; complete earlier keys remain labelled partial; diagnostics explain the stop. |
| Vendor arithmetic | Find an ordinary vendor-sellable item; manually calculate full buyout versus vendor value. | Exact integer-copper agreement; changed/removed auction rejected on live recheck. |
| Commodity quote | Open a commodity from research, change quantity in native AH, request its quote without confirming immediately. | Advice uses server total for that quantity, including multiple price levels. Cancelling/expiry clears it. No addon-initiated purchase. |
| Deposit sources | Select an owned exact variant and a commodity; compare deposit to native Sell duration/quantity. | API-derived source and amount agree. Unowned variant without a reliable API answer stays unknown until explicitly entered. |
| Fees / outcomes | Enter commission for your actual market. Make a small manual transaction and compare mail/vendor proceeds. | Fee/refund assumptions checked against real receipts; journal uses actual gross, fees and forfeited deposits. |
| History / safeguards | Collect changed observations across >=6 hours; inspect reasons and adjust settings. | No invented demand; conservative limits hold; current scan cannot create its own reference. |
| Persistence | Reload after records/settings/history. | Existing data retained; settings, positions, source/duration and journal survive. |

Use **Diagnostics → Select diagnostic text** or `/fst diag` to report a failed scan. No log is uploaded automatically.

## Remaining limitations

Live scan completion, native quote-event timing, exact Forever fee mechanics, native dialog annotation placement, Auctionator coexistence and UI scaling still require the checks above. There is no calibrated sale probability, automatic mail reconciliation, partial-position exit or verified neutral-market auto-detection. Market history remains partitioned by region/interface/ruleset/faction; do not mix fee assumptions from different market types. User-selected fee values are assumptions even when deposit values came from an API. Native or third-party queries outside the known hook set may require further client-specific handling. Exact full item strings can conservatively fragment otherwise equivalent gear. The score remains an uncalibrated policy heuristic.
