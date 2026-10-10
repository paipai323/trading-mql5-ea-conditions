# MT5 Price Condition Alerts

An alerts-only MetaTrader 5 Expert Advisor with a user-editable ordered condition list. It does not place orders.

## Files

- `outputs/PriceConditionAlerts.mq5`: MQL5 source.
- `outputs/Setup-guide.md`: installation, rule definitions, operating limits, and testing instructions.
- `outputs/condition-editor.html`: local visual editor with Add/Remove, reorder, rule dropdowns, import and export.
- `outputs/conditions.csv`: illustrative configuration; replace its prices before use.

Choose a rule for each condition and add/remove as many rows as needed. Rules include zone entry/presence, trades above/below, sweeps, closes and crossings. Each row can use live Bid prices or completed candles on its selected timeframe.

Compile the source in MetaEditor to produce the `.ex5` file. Generated binaries, compiler logs, and scratch files are excluded from Git.

The source compiles with zero errors and warnings. Market behaviour and notification delivery still require MT5 demo testing.
