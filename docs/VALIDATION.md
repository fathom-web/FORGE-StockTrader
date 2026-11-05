# Validation and API evidence

## Automated result

**64/64 tests passed using Lua 5.1 through `lupa.lua51` on 2026-11-05.** Run `python3 tests/run.py`. Coverage includes full-stack integer arithmetic, median/weighted median/outliers, historical expiry and future exclusion, variant identity, downward trends, fee rounding, deposits, break-even minimality, downside, budget limits, hypothetical EV, migration, retention, journal outcomes, scanner throttles/timeouts/repeated events/delayed data, bounded processing, AH close/reopen, native tab deduplication and switching, sorting/filters, error feedback, and full Core live re-verification.

These are mocks, not a running WoW client. No visual WoW render, actual purchase, seller fee, real server throttle, live scan completion or Auctionator coexistence was tested here.

## Source evidence inspected

- [ForeverPlusPlus API notes](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md), inspected 2026-11-05. Notes describe build 70755 and distinguish executable symbol presence from demonstrated behaviour. Its Auction House section documents empty browse search with pagination and shared throttling. A completed replicate scan remains unconfirmed there. This is supporting field evidence, not Blizzard's server guarantee.
- [Forever client API definitions](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua), inspected 2026-11-05. Defines browse/search structures, itemKey identity fields, item-search auction IDs/full links/quantity/buyout, commodity depth, full-results predicates and more-results calls; replicate's 18th return is `hasAllInfo`.
- [Forever AH utility code](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseUtil.lua) was also inspected.
- Requested [ReplicateItems wiki reference](https://warcraft.wiki.gg/wiki/API:C_AuctionHouse.ReplicateItems) returned HTTP 403 to the research fetch. It was not used to establish live behaviour.

The client definitions expose `CalculateItemDeposit(ItemLocation, duration, quantity)`. It requires an actual owned item location, not merely an auction hyperlink. Commodity deposit APIs exist but no executable commodity quote is built here. We therefore **do not guess item deposits before acquisition**. Per-stack user assumptions are required for AH candidates. Actual Forever cut rates, faction/neutral treatment, refunded deposits and rounding must be validated in game; no hardcoded retail 5% assumption survives. The net-proceeds formula deliberately rounds the fee upward as a conservative scenario. Durations are not inferred or offered as supposedly verified settings.

## Scanner implementation and declared scope

Default: full browse pagination → individual complete search for every supported browse key → bounded resolution (<=100 rows per tick) → staged per-variant analysis → validated commit. Requests are >=2 seconds apart and require the shared throttle to report ready. The original 0.2.0 replicate-only dependency is removed from the default path.

A scanner may be IDLE, REQUESTING, RECEIVING, PROCESSING, VALIDATING, COMPLETE, THROTTLED, ERROR, TIMEOUT or CANCELLED. One pending request at a time. Duplicate completion events are ignored when no matching response is expected. A missing cache record gets eight seconds to resolve; unresolved data fails the scan. Waiting/throttle timeout is 45 seconds; total scan timeout is two hours. Safety limits: 10000 browse keys, 200000 rows, 5000 rows per exact variant. Exceeding any limit fails instead of silently claiming completeness.

Pet keys, own/account auctions and bid-only auctions are intentionally outside opportunity scope and excluded; this is not a promise to cover every AH product. Commodity and replicate snapshots remain non-executable research data. Count/age details are shown; browsing has no fabricated percentage. Detail key progress has a meaningful denominator. Global browse snapshots are not simultaneous; older rows may already be stale at completion. Very large markets can time out and yield no new published history. No automatic fallback presents aggregate prices as purchasable vendor deals.

Hooked outgoing AH query methods cancel a scan when another query takes over. This is cooperative conflict detection, not a cross-addon lock or formal Auctionator queue integration. Native and third-party calls not in the hook list may still need client-specific handling. No Auctionator private globals are modified and no shared pricing data is silently imported.

History is staged until the scan and model validation finish; errors/cancellation retain previous history/last-success time. New scans clear session results to prevent old results appearing to belong to a new scan. One enabled chat notification follows validated completion. There are no repeated sounds, invented high-confidence alerts or automatic buys.

## Live checklist (required before treating this as proven)

1. Back up SavedVariables; enable `/console scriptErrors 1`. Install all modules and restart. Verify version 0.3.0, one StockTrader AH bottom tab and exactly two trading tabs. Test with Auctionator enabled and disabled. Confirm no separate window, clipping or overlapping labels at your UI scale.
2. Open, close and reopen AH. Switch native Buy/Sell/Auctions and Auctionator tabs. Check native posting/search still works. Start StockTrader, then another query; it should cancel and never announce success. Restart after the other query is idle.
3. Scan a small market. Observe phase, elapsed time, processed listings, key progress, excluded rows, completion banner and exactly one chat notification. Verify a truly empty query completes. Check large-market responsiveness and Cancel. A large full detail scan can take many minutes.
4. Interrupt connection / close AH / wait for a blocked request. Confirm red timeout or cancellation, no new last-success timestamp, no new historical evidence from the aborted scan. Simulate uncached item links and verify delayed resolution or explicit failure.
5. Find a known vendor-sellable item. Compare stack buyout, quantity, full vendor value, copper profit and ROI manually. Verify exact live listing, then buy manually. If removed/changed, expect STALE OPPORTUNITY or DO NOT BUY. Test same item ID with different suffix/enchant; do not accept mismatches.
6. Compare commodity depth with native buy quote. It must **not** appear as verified vendor arbitrage. Replicate is opt-in and research-only; test its timeout and local cooldown separately. Its successful live completion is not assumed.
7. Build changed history over >=6 hours. Confirm unchanged scans do not add evidence and the current scan does not create its own reference. Enter actual fee/deposit assumptions for that stack, inspect conservative price, decline scenarios, liquidation downside, max-buy threshold, rejection reason and score explanation.
8. Verify real fee rate, duration, deposit refund/loss and copper rounding with a small manually controlled sale in the actual market. Compare to mail proceeds. Until then costs are assumptions, not verified mechanics.
9. Record actual purchase amount, mark a real sold/vendored/abandoned outcome, and independently check fees, lost deposits, holding period and realized profit. Reload and confirm journal, market separation and legacy `realms` data survive. No unrecorded trade should be inferred.
10. Test settings, column sorting, pagination, tooltips, optional EV scenario, alerts off, journal capacity and full-stack limits. Confirm stale rows are marked, and none become a buy recommendation simply because the result list is empty.

## Explicit remaining work / uncertainty

Live client verification is outstanding, so the original scanner hang is addressed architecturally but **not proven fixed in game**. Fee mechanics are scenario inputs. Commodity execution/quotes, automatic journal capture, partial exits, seller concentration analysis, calibrated demand probabilities, richer source sharing, backtesting and specialized deterioration alerts are not implemented. Exact item-string identity can be over-restrictive. Market partitioning uses available region/interface/ruleset/faction identifiers; neutral-market semantics need a live check. UI geometry is inherited from the 0.2.0 native frame and mocked, not visually certified at every scale. These limitations are not hidden behind a completed-project claim.
