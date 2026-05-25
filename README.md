# XAU Range Scalper Pro (MT5 Expert Advisor)

A professional MetaTrader 5 Expert Advisor for **XAUUSD (Gold)** on the **M5** timeframe, built around a **range / sideways-market** reversal strategy.

> Built for low-drawdown, consistent scalping in ranging gold markets. Pauses entries automatically on strong breakouts and resumes when a fresh range forms.

---

## Strategy Summary

1. **Range detection** over the last `RangeLookback` (default 50) M5 candles.
   - Resistance = highest high, Support = lowest low.
   - Requires at least `MinTouchesPerSide` (default 2) rejections from both support and resistance.
   - Confirmed by **ATR / RangeWidth** ratio (low volatility filter).
2. **Buy** at support when:
   - Bullish engulfing OR bullish pin bar
   - RSI <= `RsiBuyMax` (default 35)
   - Optional: candle low at/below lower Bollinger band
3. **Sell** at resistance when:
   - Bearish engulfing OR shooting star
   - RSI >= `RsiSellMin` (default 65)
   - Optional: candle high at/above upper Bollinger band
4. **Stop loss** = beyond range boundary by `SlAtrMultiplier * ATR`.
5. **Take profit** = `TpRRMultiplier * SL distance`, optionally capped at the opposite side of the range.
6. **Breakout guard**: a strong candle (body > 1.2 * ATR) closing outside the range freezes new entries for `BreakoutCooldownBars` bars.

All decisions are made on **closed candles only** (`shift >= 1`) — **no repainting**.

---

## Features

- Modular MQL5 code (one class per concern)
- Risk-% based lot sizing
- Daily loss limit (auto-flat all positions)
- Max simultaneous trades = 1 (configurable)
- Break-even + Trailing Stop
- Session filter + London/NY open volatility avoidance
- Spread filter
- On-chart dashboard: range, touches, ATR, daily PnL, win rate, spread, filter status
- Entry arrows + SL / TP horizontal lines drawn on chart
- Push notifications + alerts on every trade event
- Trade log file (`MQL5/Files/XAU_RSP_log.txt`)
- Magic Number protection (does not touch other EA's trades)
- Backtest-ready, optimization-ready inputs

---

## Project Structure

```
Antu_ai/
├── Experts/
│   └── XAU_Range_Scalper_Pro.mq5      # Main EA file
└── Include/
    └── XAURangeScalperPro/
        ├── RangeDetector.mqh           # Range + S/R + ATR vol filter
        ├── SignalEngine.mqh            # Candlestick + RSI + BB signals
        ├── RiskManager.mqh             # Lot sizing + daily loss guard
        ├── TradeManager.mqh            # Open/modify/close + BE + trail + log + arrows
        ├── Filters.mqh                 # Spread + session + London/NY open
        └── Dashboard.mqh               # On-chart info panel
```

---

## Installation

1. Open MetaTrader 5 → **File → Open Data Folder**.
2. Copy `Experts/XAU_Range_Scalper_Pro.mq5` into `MQL5/Experts/`.
3. Copy the entire `Include/XAURangeScalperPro/` folder into `MQL5/Include/`.
4. In MetaEditor, open `XAU_Range_Scalper_Pro.mq5` and press **F7** (Compile).
   - Should compile with **0 errors, 0 warnings**.
5. In MT5, open a **XAUUSD M5** chart, drag the EA onto it, enable **AutoTrading**.

> Make sure your broker symbol is named `XAUUSD` (or contains "XAU"). If your broker uses a different name (e.g. `GOLD`, `XAUUSD.r`), set `InpAllowTradingOnlyXAU = false` and accept the warning.

---

## Recommended Default Inputs (XAUUSD M5)

| Group | Input | Default | Notes |
|---|---|---|---|
| Risk | `RiskPercent` | 1.0 | % of balance per trade |
| Risk | `MaxDailyLossPercent` | 3.0 | 0 disables |
| Range | `RangeLookback` | 50 | M5 candles |
| Range | `MinTouchesPerSide` | 2 | |
| Range | `TouchTolerancePoints` | 200 | 2.00 USD on gold (5-digit) |
| Range | `AtrMaxRatio` | 0.35 | lower = stricter range |
| Indic | `AtrPeriod` | 14 | |
| Indic | `RsiPeriod` | 14 | |
| Indic | `RsiBuyMax` | 35 | |
| Indic | `RsiSellMin` | 65 | |
| SL/TP | `SlAtrMultiplier` | 1.5 | |
| SL/TP | `TpRRMultiplier` | 1.8 | |
| Mgmt | `BreakEvenTriggerPts` | 800 | 8.00 USD |
| Mgmt | `BreakEvenLockPts` | 50 | 0.50 USD |
| Mgmt | `TrailStartPoints` | 1200 | 12.00 USD |
| Mgmt | `TrailStepPoints` | 600 | 6.00 USD |
| Filt | `SpreadLimitPoints` | 50 | 0.50 USD |
| Filt | `SessionStart/End` | 7 / 20 | server time |
| Filt | `AvoidLondon/NYOpen` | true / true | +/- 15 min |

> **Note on points**: XAUUSD is 2-digit on most brokers (1 point = 0.01 USD). On 3-digit gold brokers, 1 point = 0.001. Adjust the point-based inputs accordingly.

---

## Backtest & Optimization Guide

### Backtest setup
- Symbol: `XAUUSD`
- Timeframe: `M5`
- Model: **Every tick based on real ticks** (preferred) or **1 minute OHLC**
- Period: at least **6 months** of data, ideally 1-2 years
- Initial deposit: 1000+ USD
- Spread: realistic (use "Current" or set ~30-50 points)

### Suggested optimization parameters

| Parameter | Start | Step | Stop |
|---|---|---|---|
| `RangeLookback` | 30 | 10 | 80 |
| `MinTouchesPerSide` | 2 | 1 | 4 |
| `AtrMaxRatio` | 0.20 | 0.05 | 0.50 |
| `RsiBuyMax` | 25 | 5 | 40 |
| `RsiSellMin` | 60 | 5 | 75 |
| `SlAtrMultiplier` | 1.0 | 0.25 | 2.5 |
| `TpRRMultiplier` | 1.2 | 0.2 | 2.5 |
| `SpreadLimitPoints` | 30 | 10 | 80 |

**Optimize for**: Custom criterion → maximize **(Profit Factor × Recovery Factor) / max DD%**
or use **Complex Criterion (Max)** with focus on **low drawdown + smooth equity curve**.

### Walk-forward
After picking a robust set on **In-sample** (e.g., 70% of period), validate on **Out-of-sample** (last 30%) before going live.

---

## Trade Logging

All trade events are written to:

```
<MT5 Data Folder>/MQL5/Files/XAU_RSP_log.txt
```

Sample line:
```
2026.05.25 14:32:01 | OPEN BUY lots=0.10 price=2335.42 SL=2330.10 TP=2344.86 (XAU_RSP_B_RSI31.4)
```

---

## Risk Disclaimer

This EA is provided for **educational and research purposes only**. Trading XAUUSD with leverage carries substantial risk of loss. **Always test thoroughly on a demo account** and on historical data before any live deployment. No strategy is guaranteed to be profitable. Past performance does not guarantee future results.

---

## License

MIT — see `LICENSE` if present, otherwise free for personal use.
