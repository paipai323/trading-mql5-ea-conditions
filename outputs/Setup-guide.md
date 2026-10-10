# Custom MT5 condition alerts

PriceConditionAlerts now reads your own ordered condition list. It never places orders. There are no fixed three slots and no preset trading strategy.

## Create and use conditions

1. Open condition-editor.html in a browser. Add/remove rows, choose a rule for each, set prices and reorder with Move up/down. Each row supports live Bid or completed candles, with its own candle timeframe.
2. Replace the illustrative example prices. Export conditions.csv. Import restores an exported list. Drafts are saved in browser storage where available.
3. In desktop MT5 select File > Open Data Folder. Copy the CSV into MQL5/Files; ensure its filename is conditions.csv (repeated downloads can append a number).
4. Copy PriceConditionAlerts.ex5 into MQL5/Experts. Refresh Navigator and attach the EA to your exact symbol. Source can alternatively be compiled with MetaEditor.
5. Keep ConditionsFile=conditions.csv and OneShot=true initially. Keep desktop MT5 connected and running; the editor can close.
6. After changing the CSV, replace it and reattach the EA. Reloading restarts at condition 1; it is not automatic.

The HTML is a local configuration editor, not an account connection. Copying the CSV is necessary because MT5 reads its file sandbox. See https://www.mql5.com/en/docs/files/fileopen.

Phone alerts: find your MetaQuotes ID in MT5 mobile; enter it in desktop Tools > Options > Notifications, enable notifications and Test. Set PhoneNotifications=true in the EA. Messages go to MT5 mobile, not the Exness app.

## Rules

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
- Only full completion alerts. Intermediate results go to Experts; chart text shows the current step.
- OneShot=true stops after one final alert. Reattach to rearm. False restarts immediately. For a single "is in" condition, False can repeatedly alert on every tick; keep True initially.
- SequenceTimeoutMinutes=0 disables expiry. A positive value sets a total deadline from the first passed condition. Expiry resets the list.
- ResetAfterTickGapSeconds=300 resets progress after five minutes without received ticks. It cannot distinguish quiet markets from disconnection. Set 0 to disable; unobserved prices cannot be reconstructed.
- Restart/reinitialisation clears progress. No missed-candle replay is performed. Broker candle times determine closes.
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

MetaEditor compilation passed with 0 errors and 0 warnings. Browser checks passed for adding/removing/reordering rows, rule selection, validation, export data generation, import, draft persistence and mobile layout. Browser file downloads were blocked in the test environment, so export contents were checked before download; actual save delivery was not verified. The EA has not been run in MT5 Strategy Tester or against market data.

Compile in MetaEditor and test on demo before relying on alerts. For live sequences, use real-tick modelling in Strategy Tester; candle-only data cannot establish intrabar event order. Check reversed-order events, starting inside, boundaries, sweep memory, mixed timeframes, timeout, tick gaps, one-shot and reload. Test phone delivery separately. Compiler/editor checks do not establish profitability or verify broker behaviour.
