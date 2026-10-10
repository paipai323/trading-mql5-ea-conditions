# MT5 Price Condition Alerts

A MetaTrader 5 Expert Advisor with an on-chart condition editor and optional market or pending entry. Add, remove, reorder and configure conditions inside MT5, then Apply & Restart. Automatic entry defaults OFF; enabling it and applying a order type, pending entry price (when applicable), stop-loss and take-profit allows orders on demo or real accounts when the full sequence completes.

## Files

- `outputs/PriceConditionAlerts.mq5`: MQL5 source.
- `outputs/Setup-guide.md`: installation, rule definitions, operating limits, and testing instructions.
- `outputs/conditions.csv`: optional illustrative import; replace its prices before use.

Choose a rule for each condition and add/remove as many rows as needed. Rules include zone entry/presence, trades above/below, sweeps, closes and crossings. Each row can use live Bid prices or completed candles on its selected timeframe.

The panel starts paused and automatically saves applied settings. Draft edits do not affect the running monitor until applied. Click a price field label, then the chart to fill that input; selected condition levels and zone boundaries can also be dragged. Pause stops monitoring; Resume restarts the applied list at condition 1. No CSV file is required for normal use.

Compile the source in MetaEditor to produce the `.ex5` file. Generated binaries, compiler logs, and scratch files are excluded from Git.

Buy/Sell market, Buy/Sell Limit and Buy/Sell Stop orders are supported. Pending-order estimates use the planned entry price; orders are placed after full sequence completion. Automatic lot sizes use 2% of current equity and the modeled loss to your stop, rounded down to broker volume steps. Auto sizes below the broker minimum are skipped. Manual lot sizing is also available; risk above 2% shows a red warning but is permitted. Automatic entry makes one attempt per arm, checks existing symbol exposure and broker permissions/margin/stops, and does not retry. Entry settings reset on reinitialization. Fees, slippage beyond the configured allowance and gaps can cause actual losses to exceed the modeled risk.

The source compiles with zero errors and warnings. Native panel interaction, market behaviour and notification delivery still require MT5 demo testing.
