# Custom MT5 condition alerts

PriceConditionAlerts has a condition editor directly on the MT5 chart. It starts with automatic entry OFF and can send market orders if you explicitly enable and apply entry settings. There are no fixed three slots and no preset trading strategy.

## Create and use conditions

1. Copy the updated PriceConditionAlerts.ex5 into desktop MT5's data folder > MQL5 > Experts. Remove the previous instance, refresh Navigator, and attach the updated EA to your exact symbol. You can alternatively compile the source in MetaEditor.
2. The chart panel opens paused. No configuration file is required. Click + Add, select a rule, choose live Bid or completed candles, and enter a level or zone. For candle rules choose a timeframe.
3. Add more conditions. Click a row in the expanded condition list to edit that condition; Move up/down changes its order and Remove deletes it. The selected row is highlighted. Use Hide conditions / Show conditions to collapse or expand the list. Longer lists have a scrollbar and support mouse-wheel scrolling while hovering over the list. The editor shows one condition at a time, without limiting list length. Rule and other dropdowns also support wheel scrolling while open.
4. Click Apply & Restart. All draft conditions are validated and saved automatically, then monitoring starts at condition 1. Invalid drafts leave the running applied list unchanged.
5. You can edit while monitoring continues with the applied list. The draft has no effect until Apply. Click Pause if you want to stop monitoring while editing.
6. Resume & Restart runs the last applied list from condition 1. It does not apply draft edits. Apply and Resume also rearm a completed one-shot alert; no reattachment is needed.
7. Keep MT5 awake, running and connected. Removing/reinitialising the EA clears progress and pauses monitoring. Previously applied settings are restored for the same account, server, symbol and chart ID; click Resume when ready. Draft edits are saved on normal removal/reinitialisation and restored separately from the applied list. Review the restored draft and Apply to use it; Resume uses the last applied conditions.

To reuse an old CSV, click Import CSV. It reads ConditionsFile (default conditions.csv) from MQL5/Files into the draft only. Review and Apply.

Settings are saved automatically under MQL5/Files/PriceConditionAlerts using account, server, symbol and chart ID in the filename. Creating a new chart ID creates a separate setup. There is no manual CSV copying for normal panel editing. See https://www.mql5.com/en/docs/files/fileopen.

The panel can be dragged or minimised; its close button minimises it rather than removing the monitor.

To pick a price directly, click the Price level, Zone low or Zone high label above its input, then click an empty area of the main price chart at the desired height. Only fields used by the selected rule can start picking. Clicking another applicable label switches the target. Input boxes remain available for typing. The corresponding draft input is filled and picking ends. The price is rounded to the symbol's tick size and decimal precision. Pick zone boundaries separately. Press Esc to cancel. Other panel clicks are ignored; indicator subwindows cannot supply a price. Changing the selected condition/rule, adding/removing/reordering, importing, applying or pausing cancels an armed pick. Picked values do not change the running list until Apply & Restart.

Phone alerts: find your MetaQuotes ID in MT5 mobile; enter it in desktop Tools > Options > Notifications, enable notifications and Test. Set PhoneNotifications=true in the EA. Messages go to MT5 mobile, not the Exness app.

Zone visualization: with ShowZonePreviews=true (default), every draft zone with valid positive low/high bounds appears as an outline rectangle on the main chart. The condition selected for editing is orange; other draft zones are blue. Rectangles update after editing a bound, picking prices, switching conditions, importing, reordering or removing rows. Invalid/empty zones have no preview. They span the visible chart history and extend 20 chart bars beyond the latest bar, refreshing when the chart view changes or a new bar starts; those time boundaries are visual only. The previews show draft settings, including unapplied edits, not monitoring progress. Apply & Restart is still required to change the running conditions. Select a zone condition in the list to reveal its two orange dashed boundary lines. Double-click a low/high line to select it, then drag it vertically. On release the EA rounds the price to the symbol tick size, updates that draft input and redraws the rectangle. Low must remain positive and below high; invalid moves are rejected. The rectangle itself remains fixed in time. Apply & Restart is still required to use dragged bounds for monitoring. The EA removes only its own previews when detached. Set ShowZonePreviews=false to hide them.

## Rules

Use Hide zones / Show zones and Hide levels / Show levels at the top of the panel to toggle chart previews immediately. Zones includes rectangles and their low/high handles; levels includes condition price-level lines. These switches do not change draft prices, applied conditions, monitoring or orders. Use Hide entry/SL/TP / Show entry/SL/TP to toggle all three entry-related lines together. Lot-size and profit/loss estimates keep updating while lines are hidden. This toggle only affects the EA previews; broker order/position lines follow MT5 chart settings. Visibility choices restore with the draft snapshot after normal timeframe changes/reinitialization; older snapshots use the ShowZonePreviews and ShowPriceLevelPreviews inputs as defaults.

Price-level visualization: ShowPriceLevelPreviews=true (default) draws a horizontal line for each valid positive draft level used by trades-above/below, sweep, candle-close or crossing rules. The selected condition's line is orange; other level lines are blue. Double-click the selected line, then drag it vertically to update Price level on release. The price is rounded to the symbol tick size; nonpositive prices are rejected. Lines update when draft values/rules change and are removed when their condition is removed or changed to a zone rule. They appear behind the editor panel. Apply & Restart is required to change monitoring. Set ShowPriceLevelPreviews=false to hide level lines independently of zone previews.

## Automatic market and pending entry

Lot sizing: choose Auto (2% risk) or Manual lots. Auto calculates a broker-valid size whose modeled stop-loss loss stays within 2% of current equity. Manual uses the exact entered lot size; values outside broker min/max or not matching its lot step are rejected rather than silently rounded. Both modes display lot size, SL loss, TP profit, reward/risk and the estimated equity risk percentage. Manual risk above 2% turns the risk text red and shows WARNING; this is informational and does not block applying or sending the order. The execution log also warns if manual risk exceeds the current 2% budget. Trading permissions, margin, price validity, exposure and other broker checks still apply. Editing sizing mode or lots requires Apply & Restart to change the applied entry settings. Restarting the EA restores the draft lot mode and prices but resets automatic entry OFF. Sizing works for market and pending orders.

The entry section shows a red horizontal stop-loss line and a green take-profit line as soon as their draft prices are valid positive numbers. Double-click either line and drag it vertically to update its input on release. Lines sit behind the panel and are removed when you clear the respective price or detach the EA. They show draft settings, not the SL/TP of an existing position.

Below the entry fields, the panel estimates lots, loss at SL, profit at TP and reward/risk using the draft Buy/Sell direction, current Bid/Ask, equity and symbol specifications. Estimates work with automatic entry OFF. They refresh when edited and on incoming ticks, at most once per second. Values use the displayed account currency (for example, a cent account may show USC rather than USD). The 2% budget uses current equity. SL loss includes the configured adverse entry allowance; TP gain uses the current entry quote, so the shown reward/risk is conservative relative to the quoted entry. Fees/swaps/gaps are excluded. Missing/invalid prices or an unaffordable minimum lot produce an explanation instead of a tradable lot estimate. An estimate does not check margin, permissions, exposure or the optional spread limit; execution performs those checks separately. Entry uses the same estimator with the latest quote and applied settings, so actual lot size may change before the sequence completes. Apply & Restart remains required after editing or dragging.

1. Choose Order type (Buy market, Sell market, Buy Limit, Sell Limit, Buy Stop or Sell Stop), then type Stop-loss price and Take-profit price, or click either label and click the chart to pick that price. Esc cancels picking. Picked SL/TP values remain draft settings until Apply & Restart. These settings belong to the whole sequence, not an individual condition. SL and TP are required and rounded to the symbol's tick size. Buy SL must be below Bid and TP above Ask; Sell SL above Ask and TP below Bid. Broker minimum stop distances also apply.
2. Click Auto entry OFF to switch the draft to ON, then Apply & Restart. The status prefix changes to AUTO 2%. This permits actual orders on the current real or demo account; MT5 Algo Trading and the EA's Allow Algo Trading permission must also be enabled. Turning the panel switch OFF disables automatic entry immediately. Editing direction/SL/TP does not affect applied entry settings until Apply.
3. When every condition completes in order, the EA attempts one market entry with SL and TP attached. It sizes from 2% of current account equity using OrderCalcProfit in the account currency, so cent accounts do not need a USD conversion. Sizing includes an adverse price allowance of EntryDeviationPoints (default 20 points) and rounds lots down. If the broker minimum lot exceeds the budget, the trade is skipped; the EA never rounds up to the minimum.
4. The EA checks connection/trading permissions, current SL/TP validity, volume limits, supported filling policy, and OrderCheck for margin/broker restrictions. Any existing position or pending order on this symbol, including manual orders, blocks entry. EntryMaxSpreadPoints=0 disables the optional spread filter; set a positive value to reject wider spreads.
5. Automatic entry always stops the sequence after one attempt, including a skipped, rejected or uncertain request, regardless of OneShot. There are no automatic retries. Resume & Restart explicitly rearms the last applied settings; Apply rearms the new draft. Instances in the same MT5 terminal share a 60-second entry-attempt lock per account/server/symbol. Separate terminals do not share that lock. Check the Trade tab and Experts log after an uncertain response before rearming.

Draft order type, pending entry price, SL/TP and lot mode/size are saved in a separate .csv.draft snapshot beside the applied conditions CSV. Removing the EA, changing chart timeframe or restarting it restores these draft fields and resets automatic entry OFF. Previously applied conditions still restore paused. Existing trades are not closed or modified when you pause, turn entry OFF or detach the EA; the broker-held SL/TP remain responsible for their exits. EntryMagic identifies orders; the EA does not trail stops or manage open positions.

The 2% calculation is an estimate of loss at the stop, excluding commissions/swaps. Gaps and execution beyond the modeled allowance can produce larger losses; EntryDeviationPoints is not a guaranteed slippage cap under market execution. Initial order price checks and modeled risk do not guarantee execution at that price. The EA checks the server response and distinguishes execution from an accepted request awaiting execution.

| Rule | Live Bid | Completed candle |
| --- | --- | --- |
| Enters zone | Previous observed Bid outside, current Bid inside | Previous candle range outside; latest range overlaps |
| Is in / touches zone | Bid inside | Candle range overlaps |
| Trades above / below | Bid strictly above / below | High above / low below |
| Sweeps above, returns below | Observe above then below while this step is active | High above and close below in one candle |
| Sweeps below, returns above | Observe below then above while active | Low below and close above in one candle |
| Candle closes above / below | Unavailable | Close strictly beyond level |
| First candle close above / below | Unavailable | Previous close other side or equal, latest beyond |
| Candle closes inside zone | Unavailable | Close inside inclusive zone |

Live rules use Bid, not Ask or Last. Zone boundaries are inclusive; level comparisons are strict. Jumping over the entire zone does not count as entering. Starting inside does not count as entering—choose "is in" if presence should qualify (checked after the baseline tick).

## Behaviour and limits

- Conditions are evaluated in list order; only the active step is monitored. Passed steps remain satisfied. Each step requires a separate tick/evaluation. Prior sweeps do not count for a newly activated step.
- Rows can mix live and candle rules or different candle timeframes. Candle steps wait for a newly closed candle after activation; old closed candles are not evaluated.
- No hardcoded list length; available memory is the practical limit. At least one row is required.
- Only full completion alerts. Intermediate results go to Experts; the panel shows the current step.
- OneShot=true stops after one final alert. Resume & Restart rearms the applied list; Apply rearms using the draft. False restarts immediately. For a single "is in" condition, False can repeatedly alert on every tick; keep True initially.
- SequenceTimeoutMinutes=0 disables expiry. A positive value sets a total deadline from the first passed condition. Expiry resets the list.
- ResetAfterTickGapSeconds=300 resets progress after five minutes without received ticks. It cannot distinguish quiet markets from disconnection. Set 0 to disable; unobserved prices cannot be reconstructed.
- Apply, Resume and restart/reinitialisation clear progress. Resume does not pretend to recover events missed while paused. No missed-candle replay is performed. Broker candle times determine closes.
- No trend filter or zone invalidation is imposed. Position sizing and market entry are optional through the explicit entry switch.
- Push attempts are limited to one per six seconds per instance. Suppressed/failed sends are logged, not queued/retried. Use one instance initially: MT5 limits apply across the terminal. Strategy Tester does not deliver phone alerts.

Pending orders: select Buy Limit / Sell Limit / Buy Stop / Sell Stop and enter Pending entry price. Click its label, then the chart to pick it, or double-click and drag the blue entry line. The field and line are disabled/hidden for market orders. A Buy Limit must be below Ask, Buy Stop above Ask, Sell Limit above Bid and Sell Stop below Bid; broker minimum distances apply. SL and TP must be on the correct sides of the planned entry and satisfy broker stop distances. Estimates use the planned entry price, not the current quote; SL loss still includes the configured adverse entry allowance. Lot sizing happens when the sequence completes, using current equity and applied prices.

The pending order is placed only after the full condition sequence completes. It uses GTC (good till cancelled); symbols that do not support GTC are skipped. OrderCheck verifies broker requirements before submission. Pending orders use the broker's required RETURN filling policy. A successful pending placement is reported separately from a market execution; placement is not a fill. Pending orders stay in the Trade tab until filled, manually cancelled or removed by the broker. Pausing, turning auto entry OFF, detaching or restarting the EA does not cancel existing pending orders. A filled pending order is not automatically managed by this EA. The broker-held SL/TP handle exits. Gaps can change the eventual fill and actual P/L.

All four pending types passed calculation-harness checks for entry side, SL/TP sides, planned-price profit/loss, broker minimum distances, minimum-lot risk rejection and cent-denominated equity; the 320,000 volume checks also passed. These use stubbed trading calculations, not actual broker placement or fills. No orders were sent during development.

## Configuration format

Manual/auto sizing checks passed in the calculation harness: exact manual volume, over-budget loss/profit estimates, continued automatic 2% cap, broker lot-step/min/max validation and pending-order P/L. These are stubbed calculation checks, not broker execution tests.

UTF-8, six comma-separated fields per condition. Unused numeric fields are zero:

```csv
rule,mode,timeframe,level,zone_low,zone_high
ZONE_ENTER,LIVE,H1,0,1.08,1.081
SWEEP_ABOVE_REJECT,LIVE,H1,1.082,0,0
ZONE_TOUCH,LIVE,H1,0,1.08,1.081
```

Select TRADED_ABOVE for the second row if no return below is required. Supported timeframes: M1, M5, M15, M30, H1, H4, D1 (ignored for LIVE). Blank/comment lines beginning with # are ignored. No quoted fields or thousands separators. Invalid rules, modes, numbers, zone bounds, live candle-close rules or empty lists prevent startup.

## Verification

MetaEditor compilation passed with 0 errors and 0 warnings. The on-chart panel has not been exercised interactively against a running MT5 chart in this workspace, and the monitor has not been run against market data. Verify native control interactions, persistence and notification delivery on a demo chart.

Entry arithmetic verification used the extracted RiskVolume and ValidEntryPrices functions in a C# harness with MQL math/quote stubs: 320,000 volume cases plus Buy/Sell, wrong-side SL/TP, stop-distance, minimum-lot and invalid-number checks passed. This verifies arithmetic, not broker integration. No orders were sent during development. Broker execution, cent-account symbol specifications, permissions and panel interactions still need demo validation. Verify OFF stays alert-only; ON without valid SL/TP cannot apply; ON executes once at completion with the chosen direction/SL/TP; minimum-lot risk overflow and existing exposure skip; rejection stops without retry; reinitialization restores draft settings with entry OFF; turning OFF immediately prevents future entries.

The shared EstimateEntry function was also checked with stubbed profit calculations for Buy/Sell, Bid/Ask spread, adverse entry allowance, TP profit, cent-denominated equity, invalid TP and minimum-lot rejection. Check live MT5 display and SL/TP dragging on a demo chart; no live broker execution was performed.

Test on a demo chart: start with no CSV; add a rule; change rules and mode; switch between conditions; preserve entered values; reorder/remove; reject an invalid Apply without changing the running list; apply; pause; resume; rearm a completed signal; reinitialise and restore saved settings. Nonvisual Strategy Tester cannot operate the chart editor; use a demo chart for UI verification. For live sequences, real-tick data is needed to establish intrabar event order. Check boundaries, sweeps, mixed timeframes, timeout and tick gaps. Compiler checks do not establish profitability or verify broker behaviour.
