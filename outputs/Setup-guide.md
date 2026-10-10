# Custom MT5 condition alerts

PriceConditionAlerts has a condition editor directly on the MT5 chart. It never places orders. There are no fixed three slots and no preset trading strategy.

## Create and use conditions

1. Copy the updated PriceConditionAlerts.ex5 into desktop MT5's data folder > MQL5 > Experts. Remove the previous instance, refresh Navigator, and attach the updated EA to your exact symbol. You can alternatively compile the source in MetaEditor.
2. The chart panel opens paused. No configuration file is required. Click + Add, select a rule, choose live Bid or completed candles, and enter a level or zone. For candle rules choose a timeframe.
3. Add more conditions. Click a row in the expanded condition list to edit that condition; Move up/down changes its order and Remove deletes it. The selected row is highlighted. Use Hide conditions / Show conditions to collapse or expand the list. Longer lists have a scrollbar and support mouse-wheel scrolling while hovering over the list. The editor shows one condition at a time, without limiting list length. Rule and other dropdowns also support wheel scrolling while open.
4. Click Apply & Restart. All draft conditions are validated and saved automatically, then monitoring starts at condition 1. Invalid drafts leave the running applied list unchanged.
5. You can edit while monitoring continues with the applied list. The draft has no effect until Apply. Click Pause if you want to stop monitoring while editing.
6. Resume & Restart runs the last applied list from condition 1. It does not apply draft edits. Apply and Resume also rearm a completed one-shot alert; no reattachment is needed.
7. Keep MT5 awake, running and connected. Removing/reinitialising the EA clears progress and pauses monitoring. Previously applied settings are restored for the same account, server, symbol and chart ID; click Resume when ready. Unsaved draft edits are discarded on reinitialisation.

To reuse an old CSV, click Import CSV. It reads ConditionsFile (default conditions.csv) from MQL5/Files into the draft only. Review and Apply.

Settings are saved automatically under MQL5/Files/PriceConditionAlerts using account, server, symbol and chart ID in the filename. Creating a new chart ID creates a separate setup. There is no manual CSV copying for normal panel editing. See https://www.mql5.com/en/docs/files/fileopen.

You can also double-click/select a horizontal line for a level rule, or a rectangle for a zone rule, then click Use selected line / rectangle. Select exactly one matching drawing on the main chart. The panel copies its current prices into the draft; moving the drawing later does not automatically update the condition. Click Apply after copying. The panel can be dragged or minimised; its close button minimises it rather than removing the monitor.

To pick a price directly, click the Price level, Zone low or Zone high label above its input, then click an empty area of the main price chart at the desired height. Only fields used by the selected rule can start picking. Clicking another applicable label switches the target. Input boxes remain available for typing. Alternatively, choose the target from the dropdown beside Pick price and click Pick price. The corresponding draft input is filled and picking ends. The price is rounded to the symbol's tick size and decimal precision. Pick zone boundaries separately. Click Cancel pick or press Esc to cancel. Other panel clicks are ignored; indicator subwindows cannot supply a price. Changing the selected condition/rule, adding/removing/reordering, importing, applying, pausing or copying a drawing cancels an armed pick. Picked values do not change the running list until Apply & Restart.

Phone alerts: find your MetaQuotes ID in MT5 mobile; enter it in desktop Tools > Options > Notifications, enable notifications and Test. Set PhoneNotifications=true in the EA. Messages go to MT5 mobile, not the Exness app.

Zone visualization: with ShowZonePreviews=true (default), every draft zone with valid positive low/high bounds appears as an outline rectangle on the main chart. The condition selected for editing is orange; other draft zones are blue. Rectangles update after editing a bound, picking prices, copying a drawing, switching conditions, importing, reordering or removing rows. Invalid/empty zones have no preview. They span the visible chart history and extend 20 chart bars beyond the latest bar, refreshing when the chart view changes or a new bar starts; those time boundaries are visual only. The previews show draft settings, including unapplied edits, not monitoring progress. Apply & Restart is still required to change the running conditions. Select a zone condition in the list to reveal its two orange dashed boundary lines. Double-click a low/high line to select it, then drag it vertically. On release the EA rounds the price to the symbol tick size, updates that draft input and redraws the rectangle. Low must remain positive and below high; invalid moves are rejected. The rectangle itself remains fixed in time. Apply & Restart is still required to use dragged bounds for monitoring. The EA removes only its own previews when detached. Set ShowZonePreviews=false to hide them.

## Rules

Price-level visualization: ShowPriceLevelPreviews=true (default) draws a horizontal line for each valid positive draft level used by trades-above/below, sweep, candle-close or crossing rules. The selected condition's line is orange; other level lines are blue. Double-click the selected line, then drag it vertically to update Price level on release. The price is rounded to the symbol tick size; nonpositive prices are rejected. Lines update when draft values/rules change and are removed when their condition is removed or changed to a zone rule. They appear behind the editor panel. Apply & Restart is required to change monitoring. Set ShowPriceLevelPreviews=false to hide level lines independently of zone previews.

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
- No trend filter, zone invalidation, position sizing or automatic entry is imposed.
- Push attempts are limited to one per six seconds per instance. Suppressed/failed sends are logged, not queued/retried. Use one instance initially: MT5 limits apply across the terminal. Strategy Tester does not deliver phone alerts.

## Configuration format

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

Test on a demo chart: start with no CSV; add a rule; change rules and mode; switch between conditions; preserve entered values; reorder/remove; reject an invalid Apply without changing the running list; use selected drawings; apply; pause; resume; rearm a completed signal; reinitialise and restore saved settings. Nonvisual Strategy Tester cannot operate the chart editor; use a demo chart for UI verification. For live sequences, real-tick data is needed to establish intrabar event order. Check boundaries, sweeps, mixed timeframes, timeout and tick gaps. Compiler checks do not establish profitability or verify broker behaviour.
