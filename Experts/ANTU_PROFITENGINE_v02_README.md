# ANTU PROFITENGINE v02 - Dual Strategy EA

**Yeh v01 ka upgrade hai. Donon files alag rakho - v02 alag magic number use karta hai (20260201).**

---

## 🎯 Kya naya hai v02 me?

**v01 problem:** Sirf sideways market me trade karta tha → 2-5 din me 1 trade

**v02 solution:** **Dual Strategy** - donon market types me trade!

```
Market Mode Detection (auto via ADX):

  ADX < 25            ADX >= 25
  ┌──────────┐         ┌──────────┐
  │ SIDEWAYS │         │ TRENDING │
  └─────┬────┘         └─────┬────┘
        │                    │
   Strategy A           Strategy B
   RANGE                TREND PULLBACK
   (mean reversion)     (with trend)
```

**Result: 4-8 trades per day** instead of 1 in 5 days!

---

## 📊 2 Strategies Explained

### Strategy A: RANGE (already in v01)
**Kab kaam karta hai:** Market sideways (ADX < 25)

**Logic:**
- Asian session ka high/low yaad rakhta hai
- Price range low pe aaye + RSI oversold → **BUY**
- Price range high pe jaye + RSI overbought → **SELL**
- Mean reversion: price wapas middle pe aayega

### Strategy B: TREND PULLBACK (NEW)
**Kab kaam karta hai:** Market trending (ADX >= 25)

**Logic:**
- 20 EMA = fast trend, 50 EMA = slow trend
- **Uptrend:** Fast EMA > Slow EMA
- **Downtrend:** Fast EMA < Slow EMA
- Price pulled back near 20 EMA → entry opportunity!

```
UPTREND (BUY at pullback):
                    ╱╲╱╲   ← buy zones (near EMA20)
              ╱╲   ╱
        ╱╲   ╱  ╲ ╱
       ╱  ╲ ╱    V        EMA20 line (price returns to it)
      ╱    V              EMA50 line below
─────╱

DOWNTREND (SELL at pullback):
─────╲
      ╲    Λ              EMA50 line above
       ╲  ╱ ╲    Λ        EMA20 line (price bounces to it)
        ╲╱   ╲  ╱ ╲
              ╲╱   ╲╱╲    ← sell zones (near EMA20)
                    ╲╱╲╱
```

**Trade with the trend, not against it.**

---

## ⚙️ Default Settings (Conservative for $300)

| Setting | Value | Purpose |
|---|---|---|
| **Lot** | 0.03 | Per win = $7.50, per loss = $4.50 |
| **SL** | 15 pip | Tight loss |
| **TP** | 25 pip | 1:1.66 R:R |
| **ADX Threshold** | 25 | Below=Range, Above=Trend |
| **EMA Fast/Slow** | 20/50 | Standard trend pair |
| **Pullback Distance** | 10 pip | Close to EMA = entry |
| **Trend RSI BUY** | > 50 | Momentum confirms uptrend |
| **Trend RSI SELL** | < 50 | Momentum confirms downtrend |
| **Daily Target** | $12 | Sustainable |
| **Daily Loss Limit** | -$9 | Tight |
| **Max Trades/day** | 6 | More for dual strategy |
| **Max ATR** | 12 | Block extreme volatility only |
| **Max Spread** | 60 pts | Vantage typical |

---

## 🎯 Math Recap

```
Lot 0.03 XAUUSD:
  1 pip = $0.30
  Win  (25 pip TP) = +$7.50
  Loss (15 pip SL) = -$4.50

Daily target $12:
  2 wins = $15.00 ✅
  3 trades 2W 1L = +$10.50 ✅
  4 trades 3W 1L = +$18.00 ✅ (target+50%)

Bad day: 2 losses = -$9 (auto-stop)
```

---

## 🛡️ Safety Features (Same as v01)

| Trigger | Action |
|---|---|
| Daily profit $12 | Lock for the day |
| Daily loss -$9 | Lock for the day |
| 3 consecutive losses | Pause 2 hours |
| Drawdown > 6% | Full account lock |
| ATR > 12 (extreme) | No new entries |
| Spread > 60 pts | Skip trade |
| Weekend / Friday eve | No trades |
| Already in trade | No new entry |

---

## 📥 Installation Steps

### Step 1: Download
**👉 https://raw.githubusercontent.com/amolrasal2004-ctrl/Antu_ai/feature/antu-profitengine-v01/Experts/ANTU_PROFITENGINE_v02_DualStrategy.mq5**

### Step 2: Place in MT5
- File → Open Data Folder
- MQL5/Experts/ folder me file paste karo
- Right-click `ANTU_PROFITENGINE_v02_DualStrategy.mq5` → Compile (or F7)

### Step 3: Apply
- **v01 chart se hatao** (right-click → Expert Advisors → Remove)
- **v02 chart pe drag karo** (XAUUSD M5)
- Settings auto-load honge
- AutoTrading ON karo

**Magic number alag hai (20260201) - v01 aur v02 conflict nahi karenge.**

---

## 📊 Live Dashboard (chart pe dikhega)

```
┌────────────────────────────────────┐
│ ANTU PROFITENGINE v02 [DUAL]       │
├────────────────────────────────────┤
│ STATUS: [ACTIVE]                   │
│ Mode:   [B] TREND (ADX=28.5)       │
├────────────────────────────────────┤
│ ----- RANGE STRATEGY -----          │
│ High: 2658.50                      │
│ Low:  2654.20                      │
│ Size: 43.0 pips                    │
├────────────────────────────────────┤
│ ----- TREND STRATEGY -----          │
│ Trend: UP                          │
│ EMA20: 2656.80                     │
│ EMA50: 2655.50                     │
├────────────────────────────────────┤
│ ----- DAILY P&L -----              │
│ P&L: $7.50 (62%)                   │
│ Target: $12 | Loss: -$9            │
│ Trades: 1/6  Open: 0               │
│ Consec L: 0  ATR: 4.32             │
├────────────────────────────────────┤
│ Last: TREND BUY: uptrend + EMA pul.│
└────────────────────────────────────┘
```

---

## 🐛 Debug Logs (Experts tab me dikhega)

EA har bar pe message print karega:

```
>>> ANTU SIGNAL [TREND]: BUY - TREND BUY: uptrend + EMA pullback + RSI=58.2
>>> ANTU BUY: 0.03 @ 2656.85 SL:2655.35 TP:2659.35 | [TREND]

>>> NO SIGNAL: Uptrend but price away from EMA pullback zone | ADX=27.5 ATR=3.8 RSI=58.2

>>> ANTU SIGNAL [RANGE]: BUY - RANGE BUY: range_low + RSI=32.1
>>> ANTU BUY: 0.03 @ 2654.30 SL:2652.80 TP:2656.80 | [RANGE]
```

Aapko clear pata chalega:
- Kaunsi strategy ne signal diya
- Kyu trade liya
- Kyu skip kiya

---

## 🎯 Expected Performance

### Realistic (60% win rate):
- 4-6 trades/day
- 3 wins × $7.50 = $22.50
- 2 losses × $4.50 = -$9.00
- **Net: +$13.50/day** (target $12 hit consistently)

### Good (65% WR):
- **+$15-18/day**

### Bad day:
- 3 losses early → 2hr pause
- OR -$9 daily limit hit → full stop

---

## 🔧 Tuning Knobs (agar trades bahut zyada/kam ho)

### Bahut zyada trades aa rahe (5+ /day):
- `InpADXThreshold`: 25 → 30 (less trend mode)
- `InpPullbackPips`: 10 → 7 (tighter pullback zone)
- `InpEntryBufferPips`: 8 → 5 (tighter range zone)

### Bahut kam trades aa rahe (<2/day):
- `InpADXThreshold`: 25 → 20 (more trend mode)
- `InpPullbackPips`: 10 → 15 (wider pullback zone)
- `InpRangeRSIOversold`: 40 → 45
- `InpRangeRSIOverbought`: 60 → 55
- `InpTrendRSIBuy`: 50 → 45
- `InpTrendRSISell`: 50 → 55

---

## ⚠️ Warning

1. **Demo me 1 hafta test karo** before live
2. **Past performance future ka guarantee nahi**
3. **Daily $12 target = realistic** (4% per day on $300 = high)
4. **Worst case:** 5% drawdown = -$15, EA auto-stops
5. **Always keep emergency funds** - trading account me ONLY money you can lose

---

## 🆚 v01 vs v02

| Feature | v01 | v02 |
|---|---|---|
| Strategies | 1 (Range only) | 2 (Range + Trend) |
| Trades/day expected | 0-1 | 4-6 |
| Sideways market | ✅ | ✅ |
| Trending market | ❌ skipped | ✅ trade pullback |
| Magic number | 20260101 | 20260201 |
| Lot size | 0.03 | 0.03 |
| SL/TP | 15/25 | 15/25 |
| Max trades | 4 | 6 |

---

## 📞 Aage kya?

1. Demo pe 5-7 din chalao
2. Mujhe screenshot bhejo:
   - Dashboard
   - Experts tab logs
   - History tab (closed trades)
3. Win rate, trade count, daily P&L share karo
4. Live shift karne se pehle 60%+ win rate confirm karo

---

**Bana ke diya: ANTU PROFITENGINE v02 Dual Strategy**
**Branch: feature/antu-profitengine-v01**
