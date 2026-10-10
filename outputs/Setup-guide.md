# MT5 price-condition alerts

This Expert Advisor monitors the chart symbol. It never submits, modifies, or closes orders. It does not identify trends, zones or profitable setups: you supply the levels.

## Installation

1. In desktop MT5, choose File > Open Data Folder.
2. Copy PriceConditionAlerts.mq5 into MQL5/Experts.
3. Open it in MetaEditor and press F7 to compile. Resolve any compiler errors before use.
4. Refresh Expert Advisors in Navigator and attach it to your chosen symbol (for example EURUSDc on Standard Cent). The chart timeframe does not control the rule timeframe.
5. Enter valid levels in Inputs. The default PriceLevel is zero so it intentionally will not start until configured.
6. Keep the terminal connected and running. The mobile app cannot host this EA.

For phone alerts, install the MT5 mobile app, find its MetaQuotes ID, then enter it in desktop Tools > Options > Notifications. Enable notifications and use the built-in Test button. Set PhoneNotifications=true in the EA. Push messages go to MT5 mobile, not the Exness app. Signals and delivery failures are also printed in the Experts log.

## Individual rules

- CLOSE_BELOW / CLOSE_ABOVE: completed candle closes strictly beyond PriceLevel.
- CROSS_BELOW / CROSS_ABOVE: previous close is on the other side or equal; latest close is strictly beyond the level.
- SWEEP_BELOW_RECLAIM: same candle has low < level and close > level.
- SWEEP_ABOVE_REJECT: same candle has high > level and close < level.
- ZONE_TOUCH: completed candle overlaps the inclusive ZoneLow–ZoneHigh interval. This reports at candle close, not at the moment of contact.

RuleTimeframe defaults to H4 and applies to individual rules. Price equality does not qualify as a close beyond or a sweep.

## Zone → sweep → shift

Select ZONE_SWEEP_SHIFT. Supply ZoneLow, ZoneHigh, LiquidityLevel and ShiftLevel; select bullish or bearish. RuleTimeframe is ignored in this mode.

1. A completed H1 candle overlaps your manually marked H4 zone.
2. A later H1 candle sweeps and reclaims LiquidityLevel (bullish), or sweeps and rejects it (bearish).
3. A still later H1 candle first closes above ShiftLevel (bullish), or below it (bearish), compared with the preceding close.

Steps require separate candles. The sequence expires after SequenceExpiryBars H1 evaluations following the touch; completion on the final allowed bar is permitted. A completed H4 close below ZoneLow invalidates bullish sequences; a close above ZoneHigh invalidates bearish sequences. Cancellation takes precedence at simultaneous closes. Rearming requires a valid latest H4 close and a fresh qualifying H1 touch. An expired sequence can rearm on the expiry evaluation if that candle touches the zone.

Levels are fixed inputs; the EA does not move swing levels or determine which historical range is premium/discount. Changing inputs resets the state.

## Operating limits

- OneShot=true produces one signal per attachment. Remove and reattach to rearm. False permits one signal per qualifying closed candle, or per completed sequence.
- First available closed candles are used only to initialise tracking; no historical signal is sent on startup.
- State is held in memory. Restarting, changing inputs or changing chart settings resets it. It does not replay missed bars after disconnection, so sequences spanning downtime are unreliable; reattach and start fresh.
- Evaluation occurs on incoming ticks after candle close. Bar timestamps in messages are broker candle opening times, not Thailand time or notification time.
- No time-of-day restriction: monitoring runs all day, consistent with alerts-only use. A signal does not mean you should enter late after work.
- Push delivery is best effort; failed sends are logged without retry. Use only one active instance initially to avoid platform notification-rate limits. Popup/push delivery cannot be assessed by the Strategy Tester; inspect journal signals there.
- No lot sizing, stop/target recommendation or trading is included.

## Verification before use

The source was compiled with the installed MetaEditor: 0 errors and 0 warnings. The compiled PriceConditionAlerts.ex5 is included. It has not been run against live market data or verified in Strategy Tester. Test on a demo connection before relying on signals.

Use Strategy Tester visual mode with historical data and Journal output. Pick levels from an earlier chart segment, then check: first crossing vs repeated closes; wick-only sweeps; exact equality; zone boundary touches; separate-candle sequence; expiry; H4 cancellation; and no duplicate signal on additional ticks. Run different rules separately. Finally test phone delivery with a running demo terminal. These checks verify behaviour, not profitability.

References:
- https://www.mql5.com/en/docs/network/sendnotification
- https://www.mql5.com/en/docs/series/copyrates
- https://get.exness.help/hc/en-us/articles/360019530859-Using-Expert-Advisors-EA
