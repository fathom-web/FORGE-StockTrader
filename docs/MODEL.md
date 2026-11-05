# Model specification — 0.3.0

## Units and observations

Monetary input and executable stack amounts are integer copper. Per-unit historical prices may be fractional copper; projected complete-stack proceeds round down. No comparison mixes a stack buyout with one item's vendor value. Numeric acceptance rejects NaN, infinity, fractional stack counts and unsafe integer monetary values.

Exact item hyperlinks retain the complete item string, deliberately avoiding unsafe merging of suffixes, enchants, modifiers or levels. This can fragment otherwise equivalent items and reduce coverage; it is safer than false equivalence. Commodities use a distinct research-only identity. Browse item keys are never treated as complete variant identities. Item-search rows retain auction IDs.

Each complete variant group needs at least three listings before a history observation is saved. Its reference is a **weighted median**, with each listing's quantity capped at 20 as its weight to limit one large stack's influence. Store lower and upper quartiles, minimum unit ask, listing count, total quantity, stack range, source and timestamp. A sorted auction-ID/price/quantity multiset produces two bounded modular hashes; identical fingerprints do not add samples. Minimum spacing is 30 minutes. Hashing detects unchanged snapshots, not statistically independent sellers or proven transactions.

## Price estimates

Use at least three changed observations across >=6 hours within seven days. Latest observation must be <=24 hours old. Future timestamps are excluded.

1. Median of observation references; MAD = median absolute deviation from it.
2. Discard high prices above median + max(3 × MAD, 50% × median). Keep low observations as downside evidence.
3. Reject if fewer than three references remain or IQR / original median >50%.
4. Reject a three-observation consecutive decline exceeding 20% in the most recent day.
5. Base = median of retained references. Optimistic = upper quartile. Conservative = min(lower quartile, latest ask) × (1 − haircut), rounded down.
6. Haircut = 10% + min(15%, volatility × 25%) + 10% if fewer than six retained references.

These are supply-side asking-price scenarios, not proven attainable resale prices. Confidence is Low below six samples, otherwise Medium. Supply-only data never earns a High demand confidence label. A seller concentration/demand model is not implemented.

## Economics and rejection

Vendor profit = vendor unit value × quantity − buyout − known extra acquisition costs. ROI = profit / total cost. Missing identity, execution information, sell value or restricted sale flags exclude vendor opportunities.

Let C = acquisition cost, G = conservative full-stack gross resale, b = user fee in basis points, d = user deposit for this quantity, f = configured failed attempts.

- Net(G) = G − ceil(G × b / 10000). Upward fee rounding is a conservative bound, not a claim about live Forever rounding.
- Success without preceding failed postings: Net(G) − C. Refunded deposit is not deducted.
- Conservative planning profit: Net(G) − C − f × d.
- Vendor liquidation outcome: vendor unit value × quantity − C − f × d.
- Downside exposure: max(0, −liquidation outcome).
- Break-even: smallest integer G such that Net(G) >= C + f × d.
- Decline scenarios: gross prices reduced by 0%, 10%, 15%, 20%, 30%, then the same fee and configured failed-deposit assumptions.
- One-failure scenario: sale at 85% of conservative gross, less fee, acquisition and one forfeited deposit.
- Optional scenario EV: p × planning profit + (1−p) × vendor liquidation outcome. p is solely a user assumption; it is never estimated from scans. Negative scenario EV rejects the candidate.

Unknown fees or deposit quantities, stale prices/listings, low depth (<3 exact-variant listings), insufficient discount, weak profit/ROI, excessive investment or excessive liquidation loss reject recommendations. Individual current listings are stale for recommendations after 120 seconds. Live verification recomputes against the old history and current gold/positions.

Available budget is the minimum of current liquid gold, 10% of that gold less recorded open purchases of this variant, and 25% less all recorded open purchases. Current posting deposit must also fit. Thresholds are configurable. These caps are deliberately based on liquid gold, not initial wealth or marked-up inventory. Unknown trades and deposits on open positions are not inferred; keep records current.

Maximum buyout is the floor of the minimum of:

- Net conservative proceeds less planned lost deposits and minimum absolute profit;
- the ROI-constrained purchase cost;
- cash budget less the current posting deposit;
- the loss limit expressed as a fraction of liquid gold;
- the loss limit expressed as a fraction of acquisition cost;
- the configured discount threshold versus base price.

Known extra acquisition costs are removed from the allowed buyout. The label **MAX SAFE BUY PRICE** is a model threshold, **not protection against all losses**. Executable recommendations cover only the one complete identified stack. `maxQuantity` is that stack's quantity; the model does not invent additional purchasable stacks or split indivisible stacks. No blanket portfolio basket is recommended.

## Opportunity score

Heuristic score, floor to 0–100:

- 25% × min(1, conservative planning ROI);
- 25% × (1 − min(1, vendor downside / acquisition cost));
- 20% × (0.5 × min(1, retained sample count / 12));
- 10% × (1 − min(1, price volatility));
- 10% × min(1, exact-variant listing count / 10);
- 10% × (1 − min(1, acquisition cost / liquid gold)).

Costs already enter planning ROI and downside. These weights are policy choices with **no calibration evidence**. The score is not profit probability and cannot establish demand. Only candidates passing every hard gate are scored. Rejection reasons remain visible in a separate research view within AH Koopjes.

## Journal and limitations

Only manually confirmed outcomes produce realized performance. Positive and negative totals, net profit, win rate, median return, average win/loss, largest loss, holding duration and open capital are computed by `Database.performance`; the UI shows a compact subset. Whole-position exits only. A scan disappearing does not close a journal position. No ground-truth calibration, automatic mail matching, strategy backtesting, or prediction-accuracy claim is implemented.

## 0.4.0 amendments

The arithmetic and score above remain unchanged. Quick-scan ranking is **discovery scheduling**, never a trading score: apparent vendor spread first, recent known price discount second, rotating remaining keys third. A default 60-key scope is disclosed alongside full market-index size; full mode has no quick limit. Individual complete-key observations are committed incrementally. Failed/incomplete keys do not enter history. The model's `referenceBefore` boundary prevents the active scan's observations from legitimizing their own opportunities, including later settings reassessment.

Commission is now a single configured market value, with legacy per-item values available as fallback. Deposits prefer live client calculations for exact commodity quantity/duration or an exact owned item variant. Missing values still require an explicit matching assumption. Duration/quantity changes cannot reuse a mismatched deposit. API-derived deposits do not establish that the user-entered commission is correct.

Commodity supply is still not executable evidence. A **player-initiated native quote** adds an explicitly temporary executable price for that precise quantity, using the server's total, not the minimum of its levels. The quote becomes invalid on cancellation, replacement, AH close, purchase outcome or after five seconds. This is a local freshness cap, not a guaranteed server reservation duration. No purchase APIs are called by StockTrader. Both vendor and speculative margins are recalculated on the quoted quantity. The quote's source and freshness remain visible.

Manual purchases also retain the model's planned profit when available. `Database.calibration` reports closed/sold/held counts and mean(actual profit − planned profit) for records with both fields. Open or incomplete outcomes never enter that comparison. This is retrospective descriptive evidence; no probability estimator or automated trading strategy is calibrated from it.
