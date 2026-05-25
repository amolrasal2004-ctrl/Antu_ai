# XAU Sideways Scalper Pro (MT5 Expert Advisor)

Professional MetaTrader 5 Expert Advisor specifically designed for **XAUUSD (Gold)** scalping in **sideways / range-bound markets** on the **M5 timeframe**.

> Built to extract small, consistent profits every day, with strict drawdown protection. EA pauses automatically once the daily profit target is hit, and goes flat if a daily loss limit or consecutive-loss circuit breaker triggers.

---

## Versions in this Repo

| File | Version | Purpose |
|---|---|---|
| **`Experts/XAU_Sideways_Scalper_Pro_v3.mq5`** | **v3.0 (RECOMMENDED)** | Production. Mean-reversion scalper with daily profit target, partial close, circuit breakers, M15 HTF confirmation. |
| `Experts/XAU_Range_Scalper_Pro_Final.mq5` | v2.0 | Earlier balanced range scalper (single file). |
| `Experts/XAU_Range_Scalper_Pro_AllInOne.mq5` | v1.1 | First all-in-one version. |
| `Experts/XAU_Range_Scalper_Pro.mq5` + `Include/XAURangeScalperPro/*.mqh` | v1.0 | Original modular version. |

> **For new users: use only `XAU_Sideways_Scalper_Pro_v3.mq5`.** The older files are kept for reference and comparison.

---

## v3 Strategy in Plain Language (Hindi + English)

**Goal**: Sideways gold market me chote-chote scalps karke daily target hit karna, aur uske baad ruk jaana. Trending market me ek bhi trade nahi.

### Step 1: Sideways confirmation (entry kab nahi karna)
EA tabhi trade karega jab **saari** conditions match ho:
- Last 50 M5 candles me clear support + resistance (kam se kam 2-2 touches dono side)
- **ADX <= 25** (M5 + M15 dono pe) → strong trend nahi hai
- **ATR / RangeWidth <= 0.35** → range chhota nahi hai aur volatility shaant hai
- **M15 HTF** par bhi range stable hai

Agar koi bhi condition fail → EA `Range INVALID` show karega aur trade nahi karega.

### Step 2: Entry signal (5 confirmations chahiye)
EA candle band hone par hi check karta hai (no repaint). Buy ke liye support pe:
1. Candle ka low support ko touch kare (range edge pe pohcha)
2. **Bullish engulfing** ya **bullish pin bar** pattern bane
3. **RSI <= 35** AND turning up
4. **Stochastic K <= 25** AND turning up
5. Candle low **lower Bollinger band** ko tag kare

Sell ke liye resistance pe — exact mirror image.

### Step 3: SL & TP (chota aur tez)
- **SL** = range edge ke 1.2 × ATR baahar (tight)
- **TP** = entry se 1.5R, lekin **range midpoint pe cap** (mean reversion = quick scalp)
- Risk per trade = balance ka **0.5%** (default)

### Step 4: Trade management
- **+1R** pe **50% position close** (chhota profit lock)
- Baaki 50% pe **SL = breakeven + 0.30 USD** (ab loss impossible)
- Phir **ATR-based trailing stop** (1.0 × ATR)
- 24 M5 bars (~2 hours) ke baad jabardasti close (no stuck trades)

### Step 5: Daily controls (bahut zaroori)
- **Daily Profit Target +1.5%** hit → trading **pura din ke liye band**
- **Daily Loss -2%** hit → flat + band
- **3 consecutive losses** → circuit breaker, day end
- **Max 8 trades / day** hard cap
- Friday 18:00 ke baad no trade (weekend gap risk)
- London open (10:00) aur NY open (15:00) ke around ±20 min blackout

Ye sab milke ensure karte hai EA **har din, har mahina, har saal** chal sakta hai bina blow-up ke.

---

## Installation

1. MT5 me **File → Open Data Folder**
2. `Experts/XAU_Sideways_Scalper_Pro_v3.mq5` ko `MQL5/Experts/` me copy karo
3. MetaEditor me file open karke **F7** se compile karo (0 errors expected)
4. MT5 me **XAUUSD M5** chart kholo, EA drag-drop karo, **AutoTrading ON** karo

> Broker ka symbol agar `XAUUSD` na ho (jaise `GOLD`, `XAUUSD.r`, `XAUUSDm`) toh EA automatically detect kar lega kyunki check `XAU` ya `GOLD` substring pe hai. Agar fir bhi issue ho toh `InpAllowOnlyXAU = false` set kar do.

---

## Recommended Default Inputs (XAUUSD M5)

### Risk & Daily Limits
| Input | Default | Notes |
|---|---|---|
| `InpRiskPercent` | 0.5 | % balance per trade — scalper ke liye chhota |
| `InpDailyProfitTargetPct` | 1.5 | +1.5% hit = day done |
| `InpMaxDailyLossPercent` | 2.0 | -2% hit = flat & stop |
| `InpMaxConsecutiveLosses` | 3 | Circuit breaker |
| `InpMaxOpenTrades` | 1 | One trade at a time |
| `InpMaxTradesPerDay` | 8 | Anti-overtrade cap |

### Range Detection
| Input | Default | Notes |
|---|---|---|
| `InpRangeLookback` | 50 | M5 candles |
| `InpMinTouchesPerSide` | 2 | Per side |
| `InpTouchTolerancePoints` | 250 | 2.50 USD on 2-digit gold |
| `InpAtrMaxRatio` | 0.35 | Strict (<= 0.35 = quiet) |
| `InpBreakoutCooldownBars` | 20 | Pause bars after breakout |
| `InpUseHtfFilter` | true | M15 must also be calm |

### Indicators
| Input | Default |
|---|---|
| `InpAtrPeriod` / `InpAdxPeriod` / `InpRsiPeriod` | 14 |
| `InpAdxMax` | 25.0 |
| `InpRsiBuyMax` / `InpRsiSellMin` | 35 / 65 |
| `InpStochOversold` / `InpStochOverbought` | 25 / 75 |
| `InpBbPeriod` / `InpBbDeviation` | 20 / 2.0 |
| `InpRequireBbTag` | true |

### SL / TP / Exits
| Input | Default | Notes |
|---|---|---|
| `InpSlAtrMultiplier` | 1.2 | Tight SL beyond edge |
| `InpTpRRMultiplier` | 1.5 | Base RR |
| `InpTpAtRangeMid` | true | Cap TP at range midpoint |
| `InpUsePartialClose` | true | |
| `InpPartialClosePct` | 50 | Close half at +1R |
| `InpBreakEvenLockPts` | 30 | 0.30 USD lock |
| `InpTrailAtrMultiplier` | 1.0 | ATR trail step |
| `InpMaxBarsInTrade` | 24 | ~2h max hold |

### Filters
| Input | Default |
|---|---|
| `InpSpreadLimitPoints` | 50 (0.50 USD) |
| `InpUseSessionFilter` | true |
| `InpSessionStartHour` / `InpSessionEndHour` | 7 / 19 (broker time) |
| `InpAvoidLondonOpen` / `InpLondonOpenHour` | true / 10 |
| `InpAvoidNYOpen` / `InpNyOpenHour` | true / 15 |
| `InpAvoidMinutesAround` | 20 |
| `InpAvoidFridayLate` / `InpFridayCutoffHour` | true / 18 |

> **Point note**: XAUUSD usually 2-digit (1 point = 0.01 USD). 3-digit brokers pe inputs **10x** karna padega.

---

## Backtest & Optimization

### Backtest Settings
- Symbol: `XAUUSD` (ya broker ka equivalent)
- Timeframe: `M5`
- Model: **Every tick based on real ticks** (best) ya **1 minute OHLC**
- Period: minimum **1 year**, ideal **2-3 years**
- Initial deposit: 1000+ USD
- Spread: realistic (use Current ya 30-50 points)
- Leverage: 1:100 ya jo aapka real account hai

### Suggested Optimization Ranges
| Parameter | Start | Step | Stop |
|---|---|---|---|
| `InpAdxMax` | 18 | 2 | 30 |
| `InpAtrMaxRatio` | 0.20 | 0.05 | 0.45 |
| `InpRsiBuyMax` | 25 | 5 | 40 |
| `InpRsiSellMin` | 60 | 5 | 75 |
| `InpSlAtrMultiplier` | 0.8 | 0.2 | 2.0 |
| `InpTpRRMultiplier` | 1.0 | 0.25 | 2.5 |
| `InpDailyProfitTargetPct` | 0.5 | 0.5 | 3.0 |
| `InpRangeLookback` | 30 | 10 | 70 |

**Optimize for**: `Custom Criterion` → `(Profit Factor × Recovery Factor) / max DD%` ya simply maximize **Recovery Factor**.

### Walk-Forward Validation
1. In-sample optimize on 70% of data (e.g. 2023-2024).
2. Validate **as-is** on out-of-sample 30% (e.g. 2025).
3. Live deploy only if OOS profit factor >= 1.3 and DD <= in-sample DD × 1.5.

---

## On-Chart Dashboard

EA chart pe live status show karta hai:
```
XAU SSP3   : v3.0  XAUUSD  PERIOD_M5
Range      : S=2330.20  R=2348.50  Mid=2339.35  W=18.30
Indic      : Touch S=3 R=2  ATR=2.40  ADX=18.5  BBw=4.10
Trades30d  : 47 (W:34 L:13) 72.3%
Today      : PnL=+15.20 (+1.52%)  trades=4  consecL=0
Limits     : Tgt=+1.5%  MaxLoss=-2.0%  MaxL=3  MaxTr=8
Spread     : 28 pts
Status     : DAY DONE: target +1.52% hit
```

---

## Trade Log

`<MT5 Data Folder>/MQL5/Files/XAU_SSP3_log.txt`

Sample:
```
2026.05.25 09:14:01 | --- New day. StartEquity=1000.00 ---
2026.05.25 09:32:17 | OPEN BUY lots=0.05 price=2335.42 SL=2330.10 TP=2339.35
2026.05.25 09:51:08 | PARTIAL CLOSE 0.02 lots ticket=12345 @ +1R
2026.05.25 09:51:08 | BE SL set ticket=12345 SL=2335.72
2026.05.25 10:08:55 | TRAIL ticket=12345 SL=2337.10
2026.05.25 10:14:22 | DAY DONE: target +1.52% hit
```

---

## Why This EA Can Run "Every Day, Every Year"

| Risk | Mitigation in v3 |
|---|---|
| Trending market chop | Strict ADX + ATR/Width + M15 HTF gating |
| News spike | London/NY open blackout, spread filter, Friday late skip |
| Overtrading | Max 8/day + 1 open at a time |
| Revenge trading | 3-loss circuit breaker freezes the day |
| Big DD | Daily loss limit -2%, position size = 0.5% risk |
| Greed | Daily profit target +1.5% auto-stop |
| Stuck trades | 24-bar time exit |
| Breakout fakeout | 20-bar cooldown after strong breakout candle |
| Fat-finger / repaint | All decisions on closed candles only |

---

## Risk Disclaimer

This EA is provided **for educational and research purposes only**. Trading XAUUSD with leverage carries substantial risk of loss. **Always test on a demo account for at least 4 weeks** and on multi-year historical data before any live deployment. No strategy is guaranteed to be profitable in every market condition. Past performance does not guarantee future results. The author and contributors are not responsible for any financial loss.

---

## License

MIT — free for personal use.
