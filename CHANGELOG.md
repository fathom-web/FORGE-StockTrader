# Changelog

## 0.4.4 — Shorter scans

Pace serial queries from client readiness with a 0.8-second minimum and backoff. Rank keys during batched indexing. Quick scan includes up to five exploratory keys alongside leads. Full scan retains all keys and shows an estimated remaining duration after five checks.

## 0.4.3 — Buy from the deal details

Buy item rechecks the identical auction, quantity, price, funds and trade filters before opening Blizzard’s buyout confirmation. A higher price requires a fresh click. Commodity purchases use the native quantity and quote flow.

## 0.4.2 — Item icons and NPC sell prices

Show the item icon and sortable NPC sale price per unit in the results. Item details and tooltips also show the total NPC value for an executable quantity.

## 0.4.1 — Copper Rod price-level correction

Exclude multi-unit item-search rows from both scans and live verification. A grouped quantity of 3103 at a displayed 100 copper cannot establish a full-stack buyout of 100 copper. Archive ambiguous legacy history on first use and clear its discovery references. Preserve journal records and settings.

## 0.4.0 — Faster discovery and terminal layout (2026-11-06)

- Quick priority scan (default 60 keys), full scan, early complete-key results, explicit market/selected coverage, pause/resume and shared verification query pacing.
- Redesign native 676x421 content area with aligned columns, status/progress strip, metric cards, readable gold/% settings and labelled journal outcomes. Exactly two trading tabs.
- Automatic deposit adapters for commodities and exact owned variants; one commission setting per market, explicit fallback assumptions and duration-specific validation.
- Passive native commodity quote observation using actual server total/quantity, strict expiry/cancellation and no automatic buying.
- Descriptive forecast-vs-realized journal evidence, duplicate-record guard, bounded copyable diagnostics and no same-scan pricing leakage.
- 83 Lua 5.1 tests; actual UI-code mock renders with control bounds/overlap checks; installation package tooling. Live client acceptance remains pending.

## 0.3.0 — Project Quantum foundation (2026-11-05)

- Replace default replicate-only scanning with full paginated browse and per-key item searches; bounded processing, shared throttle checks, cooperative query cancellation, timeout/error handling, delayed item resolution and staged validation.
- Preserve embedded LibAHTab integration and exactly Vendor Sell / AH Koopjes; add risk controls, sortable/paged results, rejection research, cost assumptions, explainable details and manual journal inside that interface.
- Require precise executable individual auctions for vendor/speculative recommendations; commodity depth and unidentified replicated snapshots cannot masquerade as executable deals.
- Extract testable pricing/risk/history/scanner modules. Correct full-stack integer vendor margins and conservative fee rounding; include refunded/forfeited deposits, break-even, declining-price scenarios, liquidation downside, capital limits and maximum buy threshold.
- Add bounded changed-snapshot history and schema 3 markets, preserving legacy realms without treating old unproven observations as valid model evidence.
- Add exact-auction live re-verification and manual actual purchase/outcome accounting. Optional probability scenarios remain explicitly hypothetical.
- Add 64 Lua 5.1 automated tests, model formulas, API evidence and manual live test checklist.
- No CurseForge publication, repository visibility change, or claim of in-game validation.

## 0.2.0

Integrated native Auction House tab and prominent scan status. Retained as source baseline; the old replicate-only scan and fixed 5% speculative fee assumption are replaced above.
