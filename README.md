# FORGE StockTrader — Quantum 0.4.5

**Buy Low. Sell High. Protect Your Gold.** A private-use WoW Forever addon by [Novyx Forge](https://novyxforge.com), interface 16001. Native Auction House integration, exactly **Vendor Sell** and **AH Koopjes**. No CurseForge publication or purchase automation.

## Install

1. Close WoW and back up `WTF/Account/<account>/SavedVariables/FORGEStockTraderDB.lua`.
2. Extract the install ZIP, or copy the repository's `FORGE_StockTrader` folder, into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the previous addon folder. Include **all modules and Lib files**.
3. Restart WoW. Open AH → **StockTrader**, or use `/fst`.
4. With StockTrader enabled, run Auctionator’s standard full browse scan. After it finishes, open StockTrader within 15 minutes in the same game session. Forge reuses the completed unfiltered market index and automatically checks selected listings. No second market browse is sent. Quick scan and Full scan remain available for standalone use. Old saved files and replicate-mode scans are outside this integration.

**Live Forever verification is still required.** Automated tests and rendered frame mocks cannot establish real server behaviour or actual WoW font/template rendering. The development steps are implemented; the player-run acceptance steps in [Validation](docs/VALIDATION.md) remain open.

## Scan modes and honest coverage

- **Quick scan:** load the complete browse index; prioritize apparent vendor spreads and recent historical discounts; check up to **60 item keys** by default. Up to five other keys rotate per scan to build history. Browse minima prioritize searches only, never establish buyable deals. Change the 10–300-key limit in Settings.
- **Full scan:** check every supported browse key, in priority order. It takes longer and can time out in very large markets.
- Complete item searches appear **immediately** in results. The banner distinguishes **market index loaded**, **selected keys checked**, **partial**, **paused**, **failed**, and **quick/full scope complete**. A completed 60-key quick scan never claims all 1240 market keys were checked.
- **Pause** finishes the current item key safely; then inspect or verify a deal. **Resume** continues the remaining selection. Native searches or other addons cancel an active scan; paused work can be resumed later.
- **Stop**, closing AH, throttling and missing item data cannot turn an unfinished scan green. Previously completed individual item checks remain valid observations; the interrupted item's partial rows do not enter history or results. Last-success time advances only after the selected scope finishes.

Requests share the AH throttle, are at least 0.8 seconds apart and slow down on throttle feedback, and never intentionally overlap. The UI refresh is limited to once per second except meaningful state/data changes. Each result keeps its own age; listings older than 120 seconds are marked stale. **Reverify immediately before any manual purchase.**

## Vendor Sell

Forever may group many units at one displayed item-search price. Only single-unit item-search rows enter pricing, history and recommendations. A multi-unit commodity requires a quantity-matched native total quote. Ambiguous multi-unit item listings are skipped, including potentially genuine stacks.

Positive integer-copper margin = vendor unit value × full quantity − complete buyout − known extra acquisition costs. Default minimum: 1 silver. Item detail shows buyout, profit, total vendor value, ROI, source and age. Sorting supports item, quantity, buyout, profit, ROI and score/status.

**Buy item...** rechecks an individual deal and opens Blizzard’s buyout confirmation. You confirm the final purchase there. Commodity deals open the native quantity and quote flow.

**Verify live listing** finds the same auction ID, exact item variant and complete quantity. It recalculates with the current buyout and settings. Disappeared listing: **STALE OPPORTUNITY**. Failed economics: **DO NOT BUY**. **Open native AH** takes you to Blizzard's item view; only the player performs purchases.

## Commodities / raw materials

Within AH Koopjes, **Commodities** lists supply observations, explicitly not verified buy advice. Select one → **Open native AH** → choose quantity and request the native purchase quote yourself. StockTrader passively observes that request and its matching server-price event, uses the **server total for the requested quantity**, and displays the resulting margin beside the native confirmation dialog. A quote can cover multiple price levels; lowest unit price × quantity is not substituted for the total.

A positive quoted vendor margin may enter Vendor Sell. Cancellation, a different quote, purchase result, AH closure or a conservative five-second freshness limit invalidates it. Unknown/unrelated/late quote events are ignored. StockTrader never calls `StartCommoditiesPurchase`, `ConfirmCommoditiesPurchase` or `PlaceBid`. If live quote observation does not work on your client, commodity supply stays research-only.

## AH Koopjes and costs

AH resale remains speculative. The engine requires sufficient changed prior observations, a conservative lower-price scenario, recent executable data, positive profit after assumed failed postings, acceptable liquidation loss and capital limits. **NO TRADE RECOMMENDED** is expected when evidence is insufficient.

**Settings** uses readable gold and percentage inputs. Configure market commission **once**. No undocumented fee rate is invented. Select the same Short/Medium/Long listing-duration option you intend to use in native AH.

Deposit handling:

1. Commodity: query the client's deposit API for the exact item, quantity and duration.
2. Individual item: query the item-deposit API if an **exact matching variant is in your bags**.
3. Otherwise enter an explicit whole-quantity deposit assumption in item details. It only applies to that variant, quantity and duration.

API-derived deposit values are identified separately from assumptions. Commission remains user-entered because no verified automatic rate source was found. Session/bag/duration changes invalidate deposit caches. Saving costs or limits reassesses validated results without requiring another full market scan. Initial-scan observations cannot supply their own historical reference.

Default risk controls: 10% of current liquid gold per item variant; 25% total recorded speculative exposure; 30% minimum conservative ROI and discount; maximum vendor-liquidation loss of 2% of liquid gold and 50% of purchase cost; two failed listings. These are adjustable policy choices, not calibrated guarantees. Unrecorded positions are unknown.

**Explain** and item tooltips show scenario declines, break-even, fee provenance, supporting history, confidence, score limitations, vendor downside and the model-based maximum buy price. “MAX BUY” is not a guarantee against loss. Unknown sale probability stays unknown.

## Journal / actual results

On item details, enter actual **Paid copper** and click **Record** only after a purchase you made. Repeat clicks on the same selection are blocked. The Journal has labelled fields for trade ID, outcome (sold/vendored/abandoned), gross copper, actual fees, lost deposits and failed attempts. Click a trade to select its ID. Refundable deposits are not losses. Outcomes close the entire position; partial exits are not implemented.

The journal shows realized net, open capital, recorded win rate and **actual profit minus the recorded forecast**. Item explanations distinguish your sold, closed and still-held records. These are descriptive personal outcomes, never an automatically inferred resale probability. Missing outcomes do not become successes; a listing disappearing does not record a sale.

## Commands and diagnostics

- `/fst`, `/stocktrader`: select native StockTrader tab.
- `/fst journal`: list records in chat.
- `/fst close ID sold|vendored|abandoned gross fees lostDeposits attempts`: close a whole trade; all money is integer copper.
- `/fst probability 0.5` or `/fst probability off`: optional hypothetical EV scenario, clearly unmeasured.
- `/fst set alerts off`: disable chat completion notifications.
- `/fst set <setting> <value>`: advanced settings; money is copper and percentages are fractions, unlike the UI's gold/% fields.
- `/fst diag`: recent scanner events in chat. **Diagnostics** offers selectable text for reporting failures; no data is transmitted automatically.
- `/fst replicate`: experimental alternate scan, still research-only where executable identity is missing. Local retry cooldown: 15 minutes.

## Validation and development

```sh
python3 -m pip install lupa Pillow
python3 tests/run.py
python3 tests/render_ui.py /tmp/stocktrader-ui
python3 tools/package.py /tmp/FORGE_StockTrader_0.4.5.zip
```

The tests explicitly run **Lua 5.1**. The renderer loads the actual Lua UI through frame mocks, uses synthetic fixtures, checks visible control bounds/overlap, and renders results/details/settings/journal. It is a layout check, **not an in-game screenshot**.

[Model formulas](docs/MODEL.md) · [API evidence and live acceptance checklist](docs/VALIDATION.md) · [Changelog](CHANGELOG.md)

Existing schema 3 data and legacy `realms` remain intact. History is bounded by market, region/interface/ruleset/faction, exact item variant, time and sample count. Deposit settings remain variant/quantity/duration-specific. Quick-scan priority references are separately bounded and are not pricing evidence. LibAHTab and LibStub are bundled; Auctionator is optional. No telemetry or external integrations were added; repository visibility is unchanged. LibAHTab's original MIT license and LibStub credits are preserved.
