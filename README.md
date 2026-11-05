# FORGE StockTrader — Private Edition

## v0.2.0 — integrated Auction House tab
StockTrader now appears as a bottom tab beside Auctionator. Vendor Sell and AH Koopjes are **inside** this tab. The standalone popup is gone. Press SCAN AUCTION HOUSE to start a full replicated scan; the prominent banner turns **amber while reading**, **green and says SCAN COMPLETE!** after success (with a chat message and deal counts), or **red** on an error/timeout. The current scan must finish before results are final.


A standalone Auction House addon for **World of Warcraft: Forever**, built by **Novyx Forge**. This repository is presently public on GitHub; change it to private under **Settings → General → Danger Zone → Change visibility** if you want the source private.

## Two tabs

- **Vendor Sell** — Displays current AH *buyout* auctions whose total buyout costs less than their entire stack's NPC-vendor resale value. This is a deterministic **positive gross margin** if that exact auction is still available and the item is vendor-sellable. "100% winst" means certainty of the arithmetic margin, **not** a 100% return on investment.
- **AH Koopjes** — Displays **speculative** resale opportunities. A candidate requires at least **three previous distinct full scans**, three current listings of the identical item link, and a price 25% below the median of the prior observed asking-price snapshots. Projection deducts a **5% auction fee**, but does **not** include unsold/relisted deposits. Listed prices are not proven sales; selling for the estimate is never guaranteed.

## How to install

1. Copy the `FORGE_StockTrader` directory into `World of Warcraft\\_forever_\\Interface\\AddOns\\`.
2. Fully restart WoW after installing a new addon.
3. Open the Auction House and click the **StockTrader** tab next to Auctionator. `/fst` (or `/stocktrader`) selects that same AH tab while the AH is open.
4. Click **SCAN AUCTION HOUSE**. The full replicated scan is account-throttled for approximately **15 minutes**. If another addon or character recently scanned, the server may not respond.
5. Check the two tabs. Enter a minimum profit in **silver** and press **Enter** to apply.
6. Clicking a deal attempts a new item search. **Always verify the item variant, complete stack, and current buyout yourself before purchasing.** The addon will never place bids or buy items.

## Privacy and data

- No Auctioneer dependency, no networking, no uploading, and no automatic purchase.
- SavedVariables stores local rolling ask-price samples by realm/faction and full item hyperlink identity; at most 12 observations per item, 30 days retained, and 3000 tracked item keys.
- Fresh installs have **no historical speculations** until you complete several independent scans; this is intentional.
- The current scan's findings are kept in memory until reload or the next successful scan.

## Commands

- `/fst` — select the embedded StockTrader tab (the Auction House must be open).
- `/stocktrader` — same action.

## Status

**v0.2.0 — embedded AH tab test build.** Written against the documented Forever 1.60.1 / interface 16001 auction APIs. In-game testing still required for real server throttles, full-scan behaviour, UI rendering and item-data cache timing. Report errors using `/console scriptErrors 1`.

## Bundled third-party library
LibAHTab (MIT License, copyright plusmouse 2022) is bundled for safe AH tab integration, with its full copyright/license notice in `Lib/LibAHTab-LICENSE.txt` (upstream: https://github.com/TheMouseNest/LibAHTab). LibStub is public domain; credits are preserved in its file.
