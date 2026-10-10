# MT5 Price Condition Alerts

An alerts-only MetaTrader 5 Expert Advisor with an on-chart condition editor. Add, remove, reorder and configure conditions inside MT5, then Apply & Restart. It does not place orders.

## Files

- `outputs/PriceConditionAlerts.mq5`: MQL5 source.
- `outputs/Setup-guide.md`: installation, rule definitions, operating limits, and testing instructions.
- `outputs/conditions.csv`: optional illustrative import; replace its prices before use.

Choose a rule for each condition and add/remove as many rows as needed. Rules include zone entry/presence, trades above/below, sweeps, closes and crossings. Each row can use live Bid prices or completed candles on its selected timeframe.

The panel starts paused and automatically saves applied settings. Draft edits do not affect the running monitor until applied. Selected horizontal lines and rectangles can supply prices. Pause stops monitoring; Resume restarts the applied list at condition 1. No CSV file is required for normal use.

Compile the source in MetaEditor to produce the `.ex5` file. Generated binaries, compiler logs, and scratch files are excluded from Git.

The source compiles with zero errors and warnings. Native panel interaction, market behaviour and notification delivery still require MT5 demo testing.
