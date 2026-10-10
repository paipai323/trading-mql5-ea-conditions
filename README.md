# MT5 Price Condition Alerts

An alerts-only MetaTrader 5 Expert Advisor for manually configured candle and price-level conditions. It does not place orders.

## Files

- `outputs/PriceConditionAlerts.mq5`: MQL5 source.
- `outputs/Setup-guide.md`: installation, rule definitions, operating limits, and testing instructions.

Supported conditions include candle closes, crossings, sweeps, and zone contact.

Compile the source in MetaEditor to produce the `.ex5` file. Generated binaries, compiler logs, and scratch files are excluded from Git.

The source compiles with zero errors and warnings. Market behaviour and notification delivery still require MT5 demo testing.
