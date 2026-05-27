# ANTU PROFIT ENGINE v01

**Sideways/Range Market XAUUSD Scalper**

Designed for: **Vantage Broker** | **$300 account** | **$15-$20 daily target**

---

## Strategy in Simple Words (Hindi)

Yeh EA Asian session (00:00 - 07:00 server time) ke high/low ko yaad rakhta hai. Jab market range me hota hai (ADX kam, ATR kam = sideways), toh:

- Range ke **upper boundary** par price aaye + RSI > 70 + bearish candle → **SELL**
- Range ke **lower boundary** par price aaye + RSI < 30 + bullish candle → **BUY**

Mean reversion strategy - high win-rate, small TP. Daily $20 ka target hit hote hi EA bandh ho jata hai (lock).

---

## File Structure

```
Antu_ai/
├── Experts/
│   └── ANTU_PROFITENGINE_v01.mq5         <- Main EA (chart par drag karo)
└── Include/
    └── ANTU_PROFITENGINE_v01/
        ├── PE_RangeDetector.mqh           <- Range high/low detect
        ├── PE_SignalEngine.mqh            <- Buy/Sell signal logic
        ├── PE_Filters.mqh                 <- ADX/ATR/Spread/Session
        ├── PE_RiskManager.mqh             <- Lot calc + emergency lock
        ├── PE_TradeManager.mqh            <- Order open/close
        └── PE_Dashboard.mqh               <- Visual chart panel
```

---

## Installation Steps

1. MT5 me **File > Open Data Folder** karo
2. `MQL5/Experts/` me `ANTU_PROFITENGINE_v01.mq5` copy karo
3. `MQL5/Include/` me `ANTU_PROFITENGINE_v01/` poora folder copy karo (saari `.mqh` files ke saath)
4. MT5 me **MetaEditor** open karo (F4)
5. `ANTU_PROFITENGINE_v01.mq5` open karo aur **Compile** (F7) - 0 errors hone chahiye
6. MT5 me XAUUSD ka chart (M5 timeframe) open karo
7. Navigator panel se EA drag karo chart pe
8. **AutoTrading** button ON karo (toolbar)

---

## Default Settings ($300 account ke liye tuned)

| Parameter | Value | Kya hai |
|---|---|---|
| `InpMagicNumber` | 20260101 | Unique ID |
| `InpAsianStart` / `InpAsianEnd` | 0 / 7 | Asian session window |
| `InpMinRangePips` / `InpMaxRangePips` | 30 / 80 | Range size validation |
| `InpRSIOversold` / `InpRSIOverbought` | 30 / 70 | RSI confirmation levels |
| `InpMaxADX` | 22 | Trend filter (above = no trade) |
| `InpMaxATR` | 3.5 | Volatility filter (gold tuned) |
| `InpMaxSpread` | 30 points | Vantage typical: 15-25 |
| `InpStopLossPips` | 18 | Tight SL outside range |
| `InpTakeProfitPips` | 10 | Conservative TP toward middle |
| `InpRiskPercent` | 1.0% | Per trade risk |
| `InpDailyProfitTarget` | $20 | Hit hote hi day lock |
| `InpDailyLossLimit` | $10 | Hit hote hi day lock (safety) |
| `InpMaxTradesPerDay` | 4 | Over-trading roko |
| `InpMaxConsecLosses` | 3 | 3 losses = 2hr pause |
| `InpMaxDrawdownPct` | 5% | Account DD lock |

---

## Emergency Lock System

EA automatically trading band kar deta hai jab:

| Condition | Action |
|---|---|
| Daily profit $20 hit | LOCK - aaj ke liye band |
| Daily loss -$10 hit | LOCK - aaj ke liye band |
| 3 consecutive losses | PAUSE 2 hours |
| Account DD > 5% | LOCK - immediate stop |
| Max 4 trades done | LOCK - over-trading roka |
| ADX > 22 (trending) | No new entries |
| Spread > 30 pts | Skip trade |
| Weekend / Friday eve | No trades |

---

## Dashboard (Chart pe live dikhta hai)

```
┌────────────────────────────────┐
│  ANTU PROFITENGINE v01         │
├────────────────────────────────┤
│  STATUS:  [ACTIVE]             │
│  Market:  [RANGE - OK]         │
├────────────────────────────────┤
│  ----- RANGE -----             │
│  High:    2658.50              │
│  Low:     2654.20              │
│  Size:    43.0 pips            │
│  Price:   2656.35              │
├────────────────────────────────┤
│  ----- FILTERS -----           │
│  ADX:     18.2  [OK]           │
│  ATR:     2.10  [OK]           │
│  RSI:     45.3                 │
│  Spread:  18 pts [OK]          │
│  Session: [OPEN]               │
├────────────────────────────────┤
│  ----- TODAY -----             │
│  P&L:     $12.50  (62%)        │
│  Target:  $20 | Loss: -$10     │
│  Trades:  2 / 4                │
│  Open:    1 | Float: $3.20     │
│  Consec L: 0                   │
├────────────────────────────────┤
│  EMERGENCY: [OFF]              │
└────────────────────────────────┘
```

---

## Expected Performance (Realistic)

- **Win Rate:** ~70% (mean reversion characteristic)
- **R:R:** 1 : 0.55 (SL 18, TP 10)
- **Trades per day:** 1-3 average (filters strict hai)
- **Daily profit target:** $15-$20 → **$300-$500/month**
- **Drawdown:** Max 5% (controlled by emergency lock)

> Note: Past performance future ka guarantee nahi hai. Pehle **demo account pe 2-4 weeks** test karo, phir live $300 pe lagao.

---

## Optimization Tips for Vantage Broker

1. **Server time check karo** - Vantage GMT+2 (winter) / GMT+3 (summer) pe hota hai. Asian session timing adjust karna pad sakta hai.
2. **Spread typically:** XAUUSD pe 15-25 points (Raw account 0-5 + commission). `InpMaxSpread=30` safe hai.
3. **Symbol name:** "XAUUSD" ya "XAUUSD.r" - chart pe jo symbol hai wahi use karo.
4. **VPS recommended** - 24/5 EA chalane ke liye low-latency VPS Sydney/London me leave.

---

## Testing Checklist

- [ ] Demo account pe 2 weeks chalao
- [ ] Daily P&L track karo (target consistency hai)
- [ ] Drawdown 5% se neeche stay kare
- [ ] Win rate 65%+ aaye
- [ ] Live $300 pe shift, lot size 0.01 se start

---

## Troubleshooting

**Q: EA chart pe lagaya but trade nahi le raha?**
- AutoTrading button ON hai? (top toolbar)
- Filters check karo dashboard me - shayad ADX high hai (trending market)
- Session window me ho? (0-14 server time)

**Q: Range "INVALID" dikhai de raha?**
- Asian session khatam hua hai? Pehli bar 7 AM ke baad valid hota hai
- Range size 30-80 pips ke beech nahi hai (market bahut tight ya bahut wide)

**Q: Lot size galat aa raha?**
- `InpUseAutoLot = false` karo, manual `InpManualLot = 0.01` set karo

---

**Bana ke diya: ANTU PROFIT ENGINE v01 | Branch: feature/antu-profitengine-v01**
