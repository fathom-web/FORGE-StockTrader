# FORGE StockTrader — Project Quantum 0.3.0

**Buy Low. Sell High. Protect Your Gold.** Built by [Novyx Forge](https://novyxforge.com) for WoW Forever, interface 16001. Private-use project; no CurseForge release. Repository visibility is unchanged.

StockTrader stays inside the native Auction House using the bundled LibAHTab. Exactly two trading tabs: **Vendor Sell** and **AH Koopjes**. This is an implementation with automated tests, **not an in-game-certified release**.

## Install / upgrade

1. Back up `WTF/Account/<account>/SavedVariables/FORGEStockTraderDB.lua` while WoW is closed.
2. Download this repository and copy its **FORGE_StockTrader** directory into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the old addon folder. Keep all five Lua modules and the bundled Lib folder together.
3. Restart WoW. Open an Auction House, then select **StockTrader**, or type `/fst`.
4. Press **SCAN AH**. Leave the AH open and avoid other searches. Browse pages first, then every supported item key is searched individually. A large market can take a long time: requests are at least two seconds apart, with one outstanding request and shared throttle checks.
5. Green **SCAN COMPLETE** means the declared scan scope was fully received, resolved and validated. Red means failure; previous history is preserved. Closing AH or another addon starting an AH query cancels the scan. **Cancel** is always available.
6. Click a result for calculations, then **Verify exact live listing**. The same auction ID, full item string, quantity and current buyout must still qualify. Buy manually through Blizzard's AH. There is no purchase automation or invented executable commodity quote.

## What each tab means

**Vendor Sell** contains positive integer-copper margins from identified individual auctions: vendor unit value × full quantity − full buyout − known acquisition costs. Default minimum profit is 1 silver. Tooltip includes quantity, ROI, profit per item, timestamp and verification state. Old entries are marked STALE; their arithmetic is historical, not a guarantee that the auction remains available.

**AH Koopjes** requires changed historical snapshots spanning at least six hours, recent references, robust conservative prices, sufficient listing depth, an executable listing, explicit cost assumptions, acceptable downside and budget. No suitable items means **NO TRADE RECOMMENDED**. Open **Rejections / research** to see reasons and select an item to enter costs. This view is explicitly not a purchase recommendation.

In item details, supply the assumed **fee percent** and **deposit in gold for the complete stack**. Costs belong to that exact variant and stack quantity. No 5% fee is silently assumed. These are user assumptions, not live-verified Forever rules. Save costs and rescan (or live-reverify the selected research item). Commodity depth and experimental replicate data are research only: they cannot produce vendor deals or speculative buy recommendations without an executable listing.

**Risk / filters** exposes profit, ROI, discount, exposure, downside and failed-posting settings. Defaults: 10% of current liquid gold per item variant, 25% total recorded speculative exposure, 30% ROI, 30% discount, at most 2% of current gold and 50% of purchase cost lost at vendor liquidation, two failed postings. These are cautious policy choices, not empirically optimal settings. Caps include manually recorded open positions; unrecorded purchases are unknown. Successful-sale deposits are refunded in the model; failed deposits are expenses. The current posting deposit also reserves cash.

## Journal

Inside **AH Koopjes**, click an item and use **I bought this: record** only after an actual purchase. Enter the actual complete-stack cost in copper. This is a manual record, not a detected purchase. The **Journal** section reports closed-trade results and open capital; it never derives win rates from disappearing auctions.

To close a whole recorded position, enter the following in the Journal field, or use `/fst close`:

`ID sold|vendored|abandoned grossCopper actualFeesCopper lostDepositsCopper failedAttempts`

Example: `/fst close 1 sold 20000 1000 300 2` records 2g gross revenue, 10s actual fees and 3s forfeited deposits. Do not include refunded deposits. Partial exits are not supported: record separate purchases if you need separate outcomes. Abandoned revenue must be zero. Journal capacity is 2000 records; a full journal refuses further entries rather than deleting positions.

## Commands

- `/fst`, `/stocktrader`: select the native AH tab.
- `/fst journal`: list manual records in chat.
- `/fst close ...`: record a completed position as above.
- `/fst set <setting> <value>`: same numerical controls as Risk / filters; money is copper and percentages are fractions (0.3 = 30%). `/fst set alerts off` disables completion notifications.
- `/fst probability 0.5`: optional **hypothetical** sale-probability scenario, never measured demand. Negative scenario EV rejects the trade. `/fst probability off` disables it. Tooltip shows scenario EV when enabled.
- `/fst replicate`: opt-in experimental replicate scan, with a local 15-minute retry cooldown. Snapshot data without auction IDs stays research-only. Default scanning does **not** use this unverified path.

## Data / architecture

Modules: `Model.lua` (pure arithmetic and risk), `Database.lua` (schema 3, history, journal), `Scanner.lua` (asynchronous state machine), `Core.lua` (WoW adapters, verification, staged analysis), `StockTrader.lua` (native UI). Existing bundled LibStub / LibAHTab and license are retained. Auctionator is optional, not required.

Old `realms` data is preserved intact. New observations are separated by region, client interface, ruleset realm name and player faction. Old samples lacking provenance are not reused as statistical evidence. New history: 30-day retention, maximum 24 changed snapshots per variant and 3000 variants per market; price estimates use seven days with latest reference no older than 24 hours. Duplicate fingerprints do not add evidence. Raw scan rows are session-only. Current browsing is not a simultaneous market snapshot; each row has its own timestamp.

No network traffic, telemetry, bids or buying APIs. [Mathematics and limitations](docs/MODEL.md), [API evidence and live test checklist](docs/VALIDATION.md), [changelog](CHANGELOG.md).

## Automated checks

Run from the repository root:

```sh
python3 -m pip install lupa
python3 tests/run.py
```

The runner explicitly uses **Lua 5.1**. Tests include pure calculations, scanner timing and failure cases, a mocked native UI with the actual bundled LibAHTab, and full Core scan / live-verification paths. Mock success does not establish live client compatibility. See `docs/VALIDATION.md` for results and outstanding checks.

LibAHTab is MIT licensed, copyright plusmouse 2022; see `Lib/LibAHTab-LICENSE.txt`. LibStub is public domain, with original credits retained.
