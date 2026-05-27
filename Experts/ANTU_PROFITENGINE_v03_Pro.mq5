//+------------------------------------------------------------------+
//|                              ANTU_PROFITENGINE_v03_Pro.mq5       |
//|                                                                  |
//|  ANTU PROFIT ENGINE v03 - PROFESSIONAL EDITION                   |
//|                                                                  |
//|  Major upgrades from v01/v02:                                    |
//|   1. H1 TREND FILTER - no counter-trend trading                  |
//|   2. BAR CLOSE CONFIRMATION - not first-touch entries            |
//|   3. PROPER RSI 30/70 + reversal pattern                         |
//|   4. ATR-BASED SL/TP - dynamic to volatility                     |
//|   5. TRAILING STOP - lock profits after 50% to TP                |
//|   6. BREAK-EVEN SL - move SL to entry after 1xATR profit         |
//|   7. ADX HYSTERESIS - no flip-flop at 25 boundary                |
//|   8. RE-CHECK SPREAD at execution                                |
//|   9. CANDLE PATTERN confirmation (engulfing/pin)                 |
//|                                                                  |
//|  Symbol:    XAUUSD (Gold)                                        |
//|  Broker:    Vantage                                              |
//|  Account:   $300 starter                                         |
//|  Target:    $8-15 daily (PROFITABLE expectation)                 |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v03 - Pro Edition"
#property link      ""
#property version   "3.00"
#property strict
#property description "XAUUSD Pro EA: H1 trend filter + bar close confirm + ATR SL/TP + trailing"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "===== GENERAL ====="
input ulong   InpMagicNumber       = 20260301;     // Magic Number (unique)
input string  InpComment           = "ANTU_PE_v03";

input group "===== STRATEGY MODE ====="
input bool    InpUseRangeStrategy  = true;         // Strategy A: Range pullback (sideways)
input bool    InpUseTrendStrategy  = true;         // Strategy B: Trend pullback
input double  InpADXTrendMin       = 25.0;         // ADX above = trend mode (was 25)
input double  InpADXRangeMax       = 20.0;         // ADX below = range mode (HYSTERESIS)
                                                   // 20-25 = no-trade gap (avoid flip-flop)

input group "===== HIGHER TIMEFRAME TREND FILTER (NEW v03) ====="
input bool    InpUseHTFFilter      = true;         // Use H1 EMA filter for trade direction
input ENUM_TIMEFRAMES InpHTF       = PERIOD_H1;    // Higher timeframe
input int     InpHTF_EMA           = 50;           // H1 EMA period
input bool    InpAllowCounterRange = false;        // Range: allow trades against H1 trend?

input group "===== RANGE STRATEGY (Strategy A) ====="
input int     InpAsianStart        = 0;            // Asian Start Hour
input int     InpAsianEnd          = 7;            // Asian End Hour
input double  InpMinRangePips      = 25.0;         // Min Range
input double  InpMaxRangePips      = 100.0;        // Max Range
input double  InpEntryBufferPips   = 5.0;          // Entry zone width
input double  InpRangeRSIOversold  = 30.0;         // PROPER oversold (was 40)
input double  InpRangeRSIOverbought= 70.0;         // PROPER overbought (was 60)
input bool    InpRequireRangeReversal = true;      // Require bullish/bearish reversal candle

input group "===== TREND STRATEGY (Strategy B) ====="
input int     InpFastEMA           = 20;           // Fast EMA
input int     InpSlowEMA           = 50;           // Slow EMA
input double  InpPullbackPips      = 8.0;          // Max pullback distance from fast EMA
input bool    InpRequireTrendReversal = true;      // Require continuation candle

input group "===== ATR-BASED SL/TP (NEW v03) ====="
input bool    InpUseATRStops       = true;         // Use ATR multipliers (recommended)
input double  InpATRSLMultiplier   = 2.0;          // SL = ATR * 2 (gives breathing room)
input double  InpATRTPMultiplier   = 3.0;          // TP = ATR * 3 (1:1.5 R:R)
input double  InpFallbackSLPips    = 20.0;         // If ATR fails, use this SL
input double  InpFallbackTPPips    = 30.0;         // If ATR fails, use this TP

input group "===== BREAK-EVEN & TRAILING STOP (NEW v03) ====="
input bool    InpUseBreakEven      = true;         // Move SL to entry after profit
input double  InpBreakEvenATR      = 1.0;          // After this many ATRs profit, SL=entry
input bool    InpUseTrailingStop   = true;         // Trail SL behind price
input double  InpTrailATR          = 1.5;          // Trail SL = price - 1.5*ATR
input double  InpStartTrailATR     = 1.5;          // Start trailing after this many ATRs profit

input group "===== COMMON FILTERS ====="
input ENUM_TIMEFRAMES InpSignalTF  = PERIOD_M5;    // Signal Timeframe
input double  InpMaxATRPips        = 8.0;          // Max ATR (block extreme volatility)
input double  InpMinATRPips        = 1.5;          // Min ATR (block dead market)
input int     InpMaxSpread         = 50;           // Max Spread (points)
input int     InpSessionStart      = 7;            // Trade session (London open)
input int     InpSessionEnd        = 21;           // Trade session end (NY close)
input bool    InpAvoidNewsHours    = true;         // Skip 8:30 + 14:30 (NFP/CPI typical times)

input group "===== TRADE SIZE ====="
input double  InpManualLot         = 0.02;         // SAFER lot for v03 (was 0.03)

input group "===== RISK MANAGEMENT ====="
input double  InpDailyProfitTarget = 10.0;         // REALISTIC target (was 12)
input double  InpDailyLossLimit    = 8.0;          // Tighter
input int     InpMaxTradesPerDay   = 5;
input int     InpMaxConsecLosses   = 2;            // Pause earlier
input double  InpMaxDrawdownPct    = 5.0;

input group "===== DASHBOARD & LOG ====="
input bool    InpShowDashboard     = true;
input int     InpDashUpdateSec     = 1;
input bool    InpDebugLog          = true;

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL  { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = 2 };
enum ENUM_MODE    { MODE_RANGE = 0, MODE_TREND = 1, MODE_NONE = 2, MODE_GAP = 3 };
enum ENUM_LOCK    { LOCK_NONE=0, LOCK_PROFIT=1, LOCK_LOSS=2, LOCK_TRADES=3, LOCK_DD=4 };
enum ENUM_HTFTREND{ HTF_UP=1, HTF_DOWN=-1, HTF_FLAT=0 };

struct SignalResult
{
   ENUM_SIGNAL signal;
   ENUM_MODE   mode;
   string      reason;
};

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS & STATE                                           |
//+------------------------------------------------------------------+
CTrade         g_trade;
CPositionInfo  g_pos;

int      g_handleADX = INVALID_HANDLE;
int      g_handleATR = INVALID_HANDLE;
int      g_handleRSI = INVALID_HANDLE;
int      g_handleFastEMA = INVALID_HANDLE;
int      g_handleSlowEMA = INVALID_HANDLE;
int      g_handleHTFEMA = INVALID_HANDLE;

double   g_pipValue = 0.1;
datetime g_lastBarTime = 0;
datetime g_lastDashUpdate = 0;

double   g_rangeHigh = 0, g_rangeLow = 0, g_rangeSizePips = 0;
bool     g_rangeValid = false;

datetime g_dayStart = 0;
double   g_dayStartBalance = 0;
double   g_dailyPnL = 0;
int      g_tradesToday = 0;
int      g_consecLosses = 0;
datetime g_pauseUntil = 0;
bool     g_locked = false;
ENUM_LOCK g_lockReason = LOCK_NONE;

string   g_lastSignalReason = "Loading...";
ENUM_MODE g_lastMode = MODE_NONE;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("================================================");
   Print(" ANTU PROFITENGINE v03 - PRO EDITION");
   Print(" Symbol: ", _Symbol, " | Account: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print(" HTF Filter: ", InpUseHTFFilter, " (", EnumToString(InpHTF), " EMA", InpHTF_EMA, ")");
   Print(" ATR Stops: ", InpUseATRStops, " (SL=", InpATRSLMultiplier, "x, TP=", InpATRTPMultiplier, "x)");
   Print(" Break-Even: ", InpUseBreakEven, " | Trailing: ", InpUseTrailingStop);
   Print(" Daily Target: $", InpDailyProfitTarget, " | Loss Limit: $", InpDailyLossLimit);
   Print("================================================");

   g_handleADX     = iADX(_Symbol, InpSignalTF, 14);
   g_handleATR     = iATR(_Symbol, InpSignalTF, 14);
   g_handleRSI     = iRSI(_Symbol, InpSignalTF, 14, PRICE_CLOSE);
   g_handleFastEMA = iMA(_Symbol, InpSignalTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleSlowEMA = iMA(_Symbol, InpSignalTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleHTFEMA  = iMA(_Symbol, InpHTF, InpHTF_EMA, 0, MODE_EMA, PRICE_CLOSE);

   if(g_handleADX==INVALID_HANDLE || g_handleATR==INVALID_HANDLE ||
      g_handleRSI==INVALID_HANDLE || g_handleFastEMA==INVALID_HANDLE ||
      g_handleSlowEMA==INVALID_HANDLE || g_handleHTFEMA==INVALID_HANDLE)
   {
      Print(">>> ANTU v03 ERROR: Indicator handle creation failed");
      return INIT_FAILED;
   }

   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      g_pipValue = 0.1;
   else
      g_pipValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(20);

   ResetDay();
   CalculateRange();

   if(InpShowDashboard) DashboardInit();

   Print(">>> ANTU v03 READY - Pip Value: ", g_pipValue);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_handleADX != INVALID_HANDLE)     IndicatorRelease(g_handleADX);
   if(g_handleATR != INVALID_HANDLE)     IndicatorRelease(g_handleATR);
   if(g_handleRSI != INVALID_HANDLE)     IndicatorRelease(g_handleRSI);
   if(g_handleFastEMA != INVALID_HANDLE) IndicatorRelease(g_handleFastEMA);
   if(g_handleSlowEMA != INVALID_HANDLE) IndicatorRelease(g_handleSlowEMA);
   if(g_handleHTFEMA != INVALID_HANDLE)  IndicatorRelease(g_handleHTFEMA);
   ObjectsDeleteAll(0, "ANTU_V3_");
   ChartRedraw(0);
   Print(">>> ANTU v03 STOPPED");
}

//+------------------------------------------------------------------+
//| INDICATOR HELPERS                                                |
//+------------------------------------------------------------------+
double GetIndicator(int handle, int buffer = 0, int shift = 0)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer, shift, 1, arr) <= 0) return -1;
   return arr[0];
}

double GetADX(int shift = 0) { return GetIndicator(g_handleADX, 0, shift); }
double GetATR(int shift = 0) { return GetIndicator(g_handleATR, 0, shift); }
double GetRSI(int shift = 0) { return GetIndicator(g_handleRSI, 0, shift); }
double GetFastEMA(int shift = 0) { return GetIndicator(g_handleFastEMA, 0, shift); }
double GetSlowEMA(int shift = 0) { return GetIndicator(g_handleSlowEMA, 0, shift); }
double GetHTFEMA(int shift = 0) { return GetIndicator(g_handleHTFEMA, 0, shift); }

// ATR converted to pips for XAUUSD
double GetATRPips(int shift = 0)
{
   double atr = GetATR(shift);
   if(atr < 0) return -1;
   return atr / g_pipValue;
}

int GetSpread() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

//+------------------------------------------------------------------+
//| HIGHER TIMEFRAME TREND DETECTION                                 |
//+------------------------------------------------------------------+
ENUM_HTFTREND GetHTFTrend()
{
   double ema = GetHTFEMA(0);
   if(ema < 0) return HTF_FLAT;

   // Use last closed bar's close on HTF for trend determination
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpHTF, 0, 2, rates) < 2) return HTF_FLAT;
   double closeHTF = rates[1].close;  // last closed HTF bar

   // Trend strength: price must be at least 5 pips away from EMA
   double minDist = 5.0 * g_pipValue;

   if(closeHTF > ema + minDist) return HTF_UP;
   if(closeHTF < ema - minDist) return HTF_DOWN;
   return HTF_FLAT;
}

//+------------------------------------------------------------------+
//| SESSION & NEWS FILTER                                            |
//+------------------------------------------------------------------+
bool IsSessionOpen()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(dt.day_of_week == 5 && dt.hour >= 18) return false;

   if(InpSessionStart <= InpSessionEnd)
      return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
   else
      return (dt.hour >= InpSessionStart || dt.hour < InpSessionEnd);
}

bool IsNewsHour()
{
   if(!InpAvoidNewsHours) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // Skip 30 min before and after major news hours (rough proxy)
   // 8:30 GMT (PMI/CPI release window)
   if(dt.hour == 8 && dt.min >= 0 && dt.min <= 60) return true;
   // 14:30 GMT (NFP/FOMC window)
   if(dt.hour == 14 && dt.min >= 0 && dt.min <= 60) return true;
   // 18:00 GMT (FOMC minutes typical)
   if(dt.hour == 18 && dt.min >= 0 && dt.min <= 30) return true;
   return false;
}

//+------------------------------------------------------------------+
//| CANDLE PATTERN DETECTION (NEW v03)                               |
//+------------------------------------------------------------------+
// Get OHLC of bar at shift (1 = last closed)
bool GetBar(int shift, double &op, double &cl, double &hi, double &lo)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpSignalTF, shift, 1, rates) <= 0) return false;
   op = rates[0].open;
   cl = rates[0].close;
   hi = rates[0].high;
   lo = rates[0].low;
   return true;
}

// Bullish reversal: bullish engulfing or hammer at low
bool IsBullishReversal()
{
   double o1, c1, h1, l1; // last closed bar
   double o2, c2, h2, l2; // bar before that
   if(!GetBar(1, o1, c1, h1, l1)) return false;
   if(!GetBar(2, o2, c2, h2, l2)) return false;

   double body1 = MathAbs(c1 - o1);
   double range1 = h1 - l1;
   if(range1 == 0) return false;

   // Bullish engulfing: prev bear, current bull, body engulfs prev body
   bool engulfing = (c2 < o2) && (c1 > o1) && (c1 > o2) && (o1 < c2);

   // Hammer: small body at top, long lower wick (>= 2x body)
   double lowerWick = MathMin(o1, c1) - l1;
   bool hammer = (c1 > o1) &&                    // bullish close
                 (body1 / range1 < 0.4) &&        // small body
                 (lowerWick >= body1 * 2.0);      // long lower wick

   return engulfing || hammer;
}

// Bearish reversal: bearish engulfing or shooting star at high
bool IsBearishReversal()
{
   double o1, c1, h1, l1;
   double o2, c2, h2, l2;
   if(!GetBar(1, o1, c1, h1, l1)) return false;
   if(!GetBar(2, o2, c2, h2, l2)) return false;

   double body1 = MathAbs(c1 - o1);
   double range1 = h1 - l1;
   if(range1 == 0) return false;

   bool engulfing = (c2 > o2) && (c1 < o1) && (c1 < o2) && (o1 > c2);

   double upperWick = h1 - MathMax(o1, c1);
   bool shootingStar = (c1 < o1) &&
                       (body1 / range1 < 0.4) &&
                       (upperWick >= body1 * 2.0);

   return engulfing || shootingStar;
}

// Strong bullish bar (continuation): close > open, body > 50% of range, close in upper third
bool IsStrongBullCandle()
{
   double o, c, h, l;
   if(!GetBar(1, o, c, h, l)) return false;
   double body = MathAbs(c - o);
   double range = h - l;
   if(range == 0) return false;
   bool bullish = (c > o);
   bool bigBody = (body / range >= 0.5);
   bool closeUpper = ((c - l) / range >= 0.66);
   return bullish && bigBody && closeUpper;
}

// Strong bearish bar (continuation)
bool IsStrongBearCandle()
{
   double o, c, h, l;
   if(!GetBar(1, o, c, h, l)) return false;
   double body = MathAbs(c - o);
   double range = h - l;
   if(range == 0) return false;
   bool bearish = (c < o);
   bool bigBody = (body / range >= 0.5);
   bool closeLower = ((h - c) / range >= 0.66);
   return bearish && bigBody && closeLower;
}

//+------------------------------------------------------------------+
//| RANGE CALCULATION                                                |
//+------------------------------------------------------------------+
void CalculateRange()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = InpAsianStart; dt.min = 0; dt.sec = 0;
   datetime asianStart = StructToTime(dt);
   dt.hour = InpAsianEnd;
   datetime asianEnd = StructToTime(dt);

   if(TimeCurrent() < asianEnd)
   {
      asianStart -= 86400;
      asianEnd -= 86400;
   }

   double highArr[], lowArr[];
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);

   if(CopyHigh(_Symbol, PERIOD_M5, asianStart, asianEnd, highArr) > 0 &&
      CopyLow(_Symbol, PERIOD_M5, asianStart, asianEnd, lowArr) > 0)
   {
      g_rangeHigh = highArr[ArrayMaximum(highArr)];
      g_rangeLow  = lowArr[ArrayMinimum(lowArr)];
      g_rangeSizePips = (g_rangeHigh - g_rangeLow) / g_pipValue;
      g_rangeValid = (g_rangeSizePips >= InpMinRangePips &&
                      g_rangeSizePips <= InpMaxRangePips);
   }
   else
   {
      g_rangeValid = false;
   }
}

//+------------------------------------------------------------------+
//| STRATEGY A: RANGE (with H1 trend filter + reversal candle)       |
//+------------------------------------------------------------------+
SignalResult CheckRangeStrategy()
{
   SignalResult res;
   res.signal = SIG_NONE; res.mode = MODE_RANGE; res.reason = "";

   if(!g_rangeValid)
   {
      res.reason = "Range invalid";
      return res;
   }

   // Use last closed bar close for proper signal detection (not tick)
   double o, c, h, l;
   if(!GetBar(1, o, c, h, l))
   {
      res.reason = "Bar data unavailable";
      return res;
   }
   double lastClose = c;
   double rsi = GetRSI(1); // RSI of last closed bar
   double bufferPrice = InpEntryBufferPips * g_pipValue;

   // H1 trend filter
   ENUM_HTFTREND htfTrend = HTF_FLAT;
   if(InpUseHTFFilter)
      htfTrend = GetHTFTrend();

   // Check BUY: last bar low touched range_low zone, RSI oversold, bullish reversal
   if(l <= g_rangeLow + bufferPrice && lastClose > g_rangeLow)
   {
      if(rsi >= InpRangeRSIOversold)
      {
         res.reason = "Range BUY zone but RSI=" + DoubleToString(rsi,1) +
                      " (need <" + DoubleToString(InpRangeRSIOversold,1) + ")";
         return res;
      }
      if(InpRequireRangeReversal && !IsBullishReversal())
      {
         res.reason = "Range BUY zone+RSI ok but no bullish reversal candle";
         return res;
      }
      // H1 trend check
      if(InpUseHTFFilter && !InpAllowCounterRange && htfTrend == HTF_DOWN)
      {
         res.reason = "Range BUY blocked - H1 in downtrend";
         return res;
      }
      res.signal = SIG_BUY;
      res.reason = "RANGE BUY: low+RSI=" + DoubleToString(rsi,1) + "+reversal+HTF=ok";
      return res;
   }

   // Check SELL: last bar high touched range_high zone, RSI overbought, bearish reversal
   if(h >= g_rangeHigh - bufferPrice && lastClose < g_rangeHigh)
   {
      if(rsi <= InpRangeRSIOverbought)
      {
         res.reason = "Range SELL zone but RSI=" + DoubleToString(rsi,1) +
                      " (need >" + DoubleToString(InpRangeRSIOverbought,1) + ")";
         return res;
      }
      if(InpRequireRangeReversal && !IsBearishReversal())
      {
         res.reason = "Range SELL zone+RSI ok but no bearish reversal candle";
         return res;
      }
      if(InpUseHTFFilter && !InpAllowCounterRange && htfTrend == HTF_UP)
      {
         res.reason = "Range SELL blocked - H1 in uptrend";
         return res;
      }
      res.signal = SIG_SELL;
      res.reason = "RANGE SELL: high+RSI=" + DoubleToString(rsi,1) + "+reversal+HTF=ok";
      return res;
   }

   res.reason = "Price not at range boundary";
   return res;
}

//+------------------------------------------------------------------+
//| STRATEGY B: TREND PULLBACK (with H1 trend + continuation candle) |
//+------------------------------------------------------------------+
SignalResult CheckTrendStrategy()
{
   SignalResult res;
   res.signal = SIG_NONE; res.mode = MODE_TREND; res.reason = "";

   double fastEMA = GetFastEMA(0);
   double slowEMA = GetSlowEMA(0);
   double rsi = GetRSI(1);

   if(fastEMA < 0 || slowEMA < 0)
   {
      res.reason = "EMA loading";
      return res;
   }

   // Last closed bar
   double o, c, h, l;
   if(!GetBar(1, o, c, h, l))
   {
      res.reason = "Bar data unavailable";
      return res;
   }

   bool m5_uptrend = (fastEMA > slowEMA);
   bool m5_downtrend = (fastEMA < slowEMA);

   // H1 trend MUST align with M5 trend (no counter-trend trades)
   ENUM_HTFTREND htf = HTF_FLAT;
   if(InpUseHTFFilter) htf = GetHTFTrend();

   double pullbackDist = InpPullbackPips * g_pipValue;

   // UPTREND BUY setup
   if(m5_uptrend)
   {
      if(InpUseHTFFilter && htf != HTF_UP)
      {
         res.reason = "Trend BUY blocked - M5 up but H1 not up";
         return res;
      }
      // Bar must have touched fast EMA from above (pullback)
      // Then closed back above with strong bull candle
      bool touchedEMA = (l <= fastEMA + pullbackDist);
      bool closedAboveEMA = (c > fastEMA);
      bool strongBull = IsStrongBullCandle();

      if(!touchedEMA)
      {
         res.reason = "Uptrend but bar didn't pullback to EMA";
         return res;
      }
      if(!closedAboveEMA)
      {
         res.reason = "Uptrend pullback but didn't close above EMA";
         return res;
      }
      if(InpRequireTrendReversal && !strongBull)
      {
         res.reason = "Uptrend EMA touch but no strong bull continuation";
         return res;
      }
      if(rsi <= 50)
      {
         res.reason = "Uptrend setup but RSI=" + DoubleToString(rsi,1) + " (need >50)";
         return res;
      }
      res.signal = SIG_BUY;
      res.reason = "TREND BUY: M5+H1 up, EMA pullback, strong bull, RSI=" + DoubleToString(rsi,1);
      return res;
   }

   // DOWNTREND SELL setup
   if(m5_downtrend)
   {
      if(InpUseHTFFilter && htf != HTF_DOWN)
      {
         res.reason = "Trend SELL blocked - M5 down but H1 not down";
         return res;
      }
      bool touchedEMA = (h >= fastEMA - pullbackDist);
      bool closedBelowEMA = (c < fastEMA);
      bool strongBear = IsStrongBearCandle();

      if(!touchedEMA)
      {
         res.reason = "Downtrend but bar didn't pullback to EMA";
         return res;
      }
      if(!closedBelowEMA)
      {
         res.reason = "Downtrend pullback but didn't close below EMA";
         return res;
      }
      if(InpRequireTrendReversal && !strongBear)
      {
         res.reason = "Downtrend EMA touch but no strong bear continuation";
         return res;
      }
      if(rsi >= 50)
      {
         res.reason = "Downtrend setup but RSI=" + DoubleToString(rsi,1) + " (need <50)";
         return res;
      }
      res.signal = SIG_SELL;
      res.reason = "TREND SELL: M5+H1 down, EMA pullback, strong bear, RSI=" + DoubleToString(rsi,1);
      return res;
   }

   res.reason = "EMAs flat - no clear trend";
   return res;
}

//+------------------------------------------------------------------+
//| MASTER SIGNAL CHECK with HYSTERESIS                              |
//+------------------------------------------------------------------+
SignalResult GetSignal()
{
   SignalResult res;
   res.signal = SIG_NONE; res.mode = MODE_NONE; res.reason = "";

   if(!IsSessionOpen())          { res.reason = "Session closed"; return res; }
   if(IsNewsHour())              { res.reason = "News hour - blocked"; return res; }
   if(GetSpread() > InpMaxSpread){ res.reason = "Spread high (" + IntegerToString(GetSpread()) + ")"; return res; }

   double atrPips = GetATRPips(0);
   if(atrPips < 0)                { res.reason = "ATR loading"; return res; }
   if(atrPips > InpMaxATRPips)    { res.reason = "ATR " + DoubleToString(atrPips,1) + " too high (max " + DoubleToString(InpMaxATRPips,1) + ")"; return res; }
   if(atrPips < InpMinATRPips)    { res.reason = "ATR " + DoubleToString(atrPips,1) + " too low (dead market)"; return res; }

   double adx = GetADX(0);
   if(adx < 0)                    { res.reason = "ADX loading"; return res; }

   // HYSTERESIS: clear gap between range and trend modes
   bool isRangeMode = (adx <= InpADXRangeMax);    // <=20
   bool isTrendMode = (adx >= InpADXTrendMin);    // >=25
   // 20-25 = no-trade gap

   if(isRangeMode && InpUseRangeStrategy)
   {
      res = CheckRangeStrategy();
      if(res.signal != SIG_NONE) return res;
   }
   else if(isTrendMode && InpUseTrendStrategy)
   {
      res = CheckTrendStrategy();
      if(res.signal != SIG_NONE) return res;
   }
   else
   {
      // ADX in 20-25 gap zone - no trade
      res.reason = "ADX=" + DoubleToString(adx,1) + " in no-trade gap (20-25)";
      res.mode = MODE_GAP;
      return res;
   }

   if(res.reason == "")
      res.reason = isRangeMode ? "Range mode - no setup" : "Trend mode - no setup";
   res.mode = isRangeMode ? MODE_RANGE : MODE_TREND;
   return res;
}

//+------------------------------------------------------------------+
//| ORDER EXECUTION (with re-check spread)                           |
//+------------------------------------------------------------------+
bool OpenBuy(string comment)
{
   // Re-check spread at execution
   if(GetSpread() > InpMaxSpread)
   {
      Print(">>> ANTU BUY ABORTED: Spread spiked to ", GetSpread());
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // ATR-based or fallback SL/TP
   double slPips, tpPips;
   if(InpUseATRStops)
   {
      double atrPips = GetATRPips(0);
      if(atrPips < 0)
      {
         slPips = InpFallbackSLPips;
         tpPips = InpFallbackTPPips;
      }
      else
      {
         slPips = atrPips * InpATRSLMultiplier;
         tpPips = atrPips * InpATRTPMultiplier;
      }
   }
   else
   {
      slPips = InpFallbackSLPips;
      tpPips = InpFallbackTPPips;
   }

   double sl = NormalizeDouble(ask - slPips * g_pipValue, digits);
   double tp = NormalizeDouble(ask + tpPips * g_pipValue, digits);

   if(g_trade.Buy(InpManualLot, _Symbol, ask, sl, tp, InpComment + " " + comment))
   {
      Print(">>> ANTU v03 BUY: ", InpManualLot, " @ ", ask,
            " SL:", sl, " TP:", tp,
            " (SL=", DoubleToString(slPips,1), "p, TP=", DoubleToString(tpPips,1), "p) | ", comment);
      return true;
   }
   Print(">>> ANTU BUY FAILED: ", g_trade.ResultRetcodeDescription());
   return false;
}

bool OpenSell(string comment)
{
   if(GetSpread() > InpMaxSpread)
   {
      Print(">>> ANTU SELL ABORTED: Spread spiked to ", GetSpread());
      return false;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slPips, tpPips;
   if(InpUseATRStops)
   {
      double atrPips = GetATRPips(0);
      if(atrPips < 0)
      {
         slPips = InpFallbackSLPips;
         tpPips = InpFallbackTPPips;
      }
      else
      {
         slPips = atrPips * InpATRSLMultiplier;
         tpPips = atrPips * InpATRTPMultiplier;
      }
   }
   else
   {
      slPips = InpFallbackSLPips;
      tpPips = InpFallbackTPPips;
   }

   double sl = NormalizeDouble(bid + slPips * g_pipValue, digits);
   double tp = NormalizeDouble(bid - tpPips * g_pipValue, digits);

   if(g_trade.Sell(InpManualLot, _Symbol, bid, sl, tp, InpComment + " " + comment))
   {
      Print(">>> ANTU v03 SELL: ", InpManualLot, " @ ", bid,
            " SL:", sl, " TP:", tp,
            " (SL=", DoubleToString(slPips,1), "p, TP=", DoubleToString(tpPips,1), "p) | ", comment);
      return true;
   }
   Print(">>> ANTU SELL FAILED: ", g_trade.ResultRetcodeDescription());
   return false;
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
         count++;
   }
   return count;
}

double GetFloatingPnL()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
         total += g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
   }
   return total;
}

//+------------------------------------------------------------------+
//| BREAK-EVEN & TRAILING STOP MANAGEMENT (NEW v03)                  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!InpUseBreakEven && !InpUseTrailingStop) return;

   double atrPrice = GetATR(0);  // ATR in price units
   if(atrPrice < 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol || g_pos.Magic() != InpMagicNumber) continue;

      double openPrice = g_pos.PriceOpen();
      double currentSL = g_pos.StopLoss();
      double currentTP = g_pos.TakeProfit();
      ulong  ticket = g_pos.Ticket();
      ENUM_POSITION_TYPE posType = g_pos.PositionType();

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      double profitPrice = 0;  // current profit in price units
      double newSL = currentSL;

      if(posType == POSITION_TYPE_BUY)
      {
         profitPrice = bid - openPrice;

         // Break-even: SL to entry+1 pip after 1 ATR profit
         if(InpUseBreakEven && profitPrice >= atrPrice * InpBreakEvenATR)
         {
            double beSL = NormalizeDouble(openPrice + 1 * g_pipValue, digits);
            if(currentSL < beSL)  // only move up
               newSL = beSL;
         }

         // Trailing: trail at price - trail_atr*ATR after start_trail_atr profit
         if(InpUseTrailingStop && profitPrice >= atrPrice * InpStartTrailATR)
         {
            double trailSL = NormalizeDouble(bid - atrPrice * InpTrailATR, digits);
            if(trailSL > newSL)  // only trail up
               newSL = trailSL;
         }

         if(newSL > currentSL && newSL < bid)
         {
            g_trade.PositionModify(ticket, newSL, currentTP);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         profitPrice = openPrice - ask;

         if(InpUseBreakEven && profitPrice >= atrPrice * InpBreakEvenATR)
         {
            double beSL = NormalizeDouble(openPrice - 1 * g_pipValue, digits);
            if(currentSL > beSL || currentSL == 0)
               newSL = beSL;
         }

         if(InpUseTrailingStop && profitPrice >= atrPrice * InpStartTrailATR)
         {
            double trailSL = NormalizeDouble(ask + atrPrice * InpTrailATR, digits);
            if(currentSL == 0 || trailSL < currentSL)
               newSL = trailSL;
         }

         if((currentSL == 0 || newSL < currentSL) && newSL > ask)
         {
            g_trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| RISK MANAGER                                                     |
//+------------------------------------------------------------------+
void ResetDay()
{
   g_dayStart = TimeCurrent();
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyPnL = 0;
   g_tradesToday = 0;
   g_consecLosses = 0;
   g_pauseUntil = 0;
   g_locked = false;
   g_lockReason = LOCK_NONE;
}

void CheckNewDay()
{
   MqlDateTime dtNow, dtStart;
   TimeToStruct(TimeCurrent(), dtNow);
   TimeToStruct(g_dayStart, dtStart);
   if(dtNow.day != dtStart.day || dtNow.mon != dtStart.mon)
   {
      ResetDay();
      Print(">>> ANTU v03: New day - reset");
   }
}

bool CanTrade()
{
   CheckNewDay();
   if(g_locked) return false;

   if(g_dailyPnL >= InpDailyProfitTarget)
   {
      g_locked = true; g_lockReason = LOCK_PROFIT;
      Print(">>> ANTU v03 LOCKED: Profit target $", g_dailyPnL);
      return false;
   }
   if(g_dailyPnL <= -InpDailyLossLimit)
   {
      g_locked = true; g_lockReason = LOCK_LOSS;
      Print(">>> ANTU v03 LOCKED: Loss limit -$", g_dailyPnL);
      return false;
   }
   if(g_tradesToday >= InpMaxTradesPerDay)
   {
      g_locked = true; g_lockReason = LOCK_TRADES;
      return false;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddPct = (g_dayStartBalance - balance) / g_dayStartBalance * 100.0;
   if(ddPct >= InpMaxDrawdownPct)
   {
      g_locked = true; g_lockReason = LOCK_DD;
      return false;
   }

   if(TimeCurrent() < g_pauseUntil) return false;
   return true;
}

void OnTradeClose(double profit)
{
   g_dailyPnL += profit;
   g_tradesToday++;
   if(profit < 0) g_consecLosses++;
   else if(profit > 0) g_consecLosses = 0;

   if(g_consecLosses >= InpMaxConsecLosses)
   {
      g_pauseUntil = TimeCurrent() + 7200;
      Print(">>> ANTU v03 PAUSE 2hr: ", g_consecLosses, " losses");
   }
}

string LockReasonText()
{
   switch(g_lockReason)
   {
      case LOCK_PROFIT: return "Profit Target";
      case LOCK_LOSS:   return "Daily Loss";
      case LOCK_TRADES: return "Max Trades";
      case LOCK_DD:     return "Drawdown";
      default:          return "None";
   }
}

//+------------------------------------------------------------------+
//| MAIN TICK                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckNewDay();

   if(InpShowDashboard && TimeCurrent() - g_lastDashUpdate >= InpDashUpdateSec)
   {
      DashboardUpdate();
      g_lastDashUpdate = TimeCurrent();
   }

   // Manage open positions every tick (trailing/break-even)
   ManageOpenPositions();

   // Process new signals only on new bar
   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, InpSignalTF, SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime) return;
   g_lastBarTime = curBarTime;

   CalculateRange();

   if(!CanTrade())
   {
      if(InpDebugLog) Print(">>> SKIP: ", LockReasonText());
      return;
   }
   if(CountOpenPositions() > 0) return;

   SignalResult sig = GetSignal();
   g_lastSignalReason = sig.reason;
   g_lastMode = sig.mode;

   if(sig.signal == SIG_NONE)
   {
      if(InpDebugLog && sig.reason != "")
      {
         Print(">>> NO SIGNAL: ", sig.reason,
               " | ADX=", DoubleToString(GetADX(),1),
               " ATR=", DoubleToString(GetATRPips(),1), "p",
               " RSI=", DoubleToString(GetRSI(1),1));
      }
      return;
   }

   string modeStr = (sig.mode == MODE_RANGE) ? "RANGE" : "TREND";
   if(sig.signal == SIG_BUY)
   {
      Print(">>> ANTU v03 [", modeStr, "] BUY - ", sig.reason);
      OpenBuy("[" + modeStr + "]");
   }
   else if(sig.signal == SIG_SELL)
   {
      Print(">>> ANTU v03 [", modeStr, "] SELL - ", sig.reason);
      OpenSell("[" + modeStr + "]");
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket)) return;

   long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

   if(magic == (long)InpMagicNumber && entry == DEAL_ENTRY_OUT)
   {
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                      HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                      HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      OnTradeClose(profit);
      Print(">>> CLOSED: P/L=$", DoubleToString(profit,2),
            " | Daily=$", DoubleToString(g_dailyPnL,2),
            " | Trades=", g_tradesToday);
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void DashboardInit()
{
   string n = "ANTU_V3_BG";
   ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, 290);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, 460);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C'25,25,35');
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}

void DashLabel(string name, int x, int y, string text, color clr, int fs = 9)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DashboardUpdate()
{
   color cWhite=clrWhite, cGood=clrLime, cBad=clrRed,
         cWarn=clrOrange, cGold=C'255,200,50';
   int x = 25, y = 25;

   DashLabel("ANTU_V3_TITLE", x, y, "ANTU PROFITENGINE v03 [PRO]", cGold, 10); y += 22;

   // Status
   string statusTxt; color statusClr;
   if(g_locked) { statusTxt = "STATUS: [LOCKED] " + LockReasonText(); statusClr = cBad; }
   else         { statusTxt = "STATUS: [ACTIVE]"; statusClr = cGood; }
   DashLabel("ANTU_V3_STATUS", x, y, statusTxt, statusClr); y += 18;

   // Mode + ADX
   double adx = GetADX();
   double atrP = GetATRPips();
   string modeTxt; color modeClr;
   if(adx < 0) { modeTxt = "Mode: [LOADING]"; modeClr = cWarn; }
   else if(adx <= InpADXRangeMax) { modeTxt = "Mode: [RANGE] ADX=" + DoubleToString(adx,1); modeClr = cGood; }
   else if(adx >= InpADXTrendMin) { modeTxt = "Mode: [TREND] ADX=" + DoubleToString(adx,1); modeClr = cWarn; }
   else                            { modeTxt = "Mode: [GAP] ADX=" + DoubleToString(adx,1) + " (no trade)"; modeClr = clrSlateGray; }
   DashLabel("ANTU_V3_MODE", x, y, modeTxt, modeClr); y += 18;

   // H1 trend
   ENUM_HTFTREND htf = GetHTFTrend();
   string htfTxt; color htfClr;
   if(htf == HTF_UP)         { htfTxt = "H1 Trend: UP"; htfClr = cGood; }
   else if(htf == HTF_DOWN)  { htfTxt = "H1 Trend: DOWN"; htfClr = cBad; }
   else                      { htfTxt = "H1 Trend: FLAT"; htfClr = cWarn; }
   DashLabel("ANTU_V3_HTF", x, y, htfTxt, htfClr); y += 22;

   DashLabel("ANTU_V3_DIV1", x, y, "------ INDICATORS ------", clrSlateGray); y += 17;
   DashLabel("ANTU_V3_ADX", x, y, "ADX:  " + DoubleToString(adx,1), cWhite); y += 17;
   DashLabel("ANTU_V3_ATR", x, y, "ATR:  " + DoubleToString(atrP,1) + " pips", cWhite); y += 17;
   DashLabel("ANTU_V3_RSI", x, y, "RSI:  " + DoubleToString(GetRSI(1),1), cWhite); y += 17;
   DashLabel("ANTU_V3_SPR", x, y, "Spread: " + IntegerToString(GetSpread()) + " pts", cWhite); y += 22;

   // Range
   DashLabel("ANTU_V3_DIV2", x, y, "------ RANGE ------", clrSlateGray); y += 17;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_rangeValid)
   {
      DashLabel("ANTU_V3_RH", x, y, "High: " + DoubleToString(g_rangeHigh, digits), cWhite); y += 17;
      DashLabel("ANTU_V3_RL", x, y, "Low:  " + DoubleToString(g_rangeLow, digits), cWhite); y += 17;
      DashLabel("ANTU_V3_RS", x, y, "Size: " + DoubleToString(g_rangeSizePips,1) + " pips", cWhite); y += 17;
   } else {
      DashLabel("ANTU_V3_RH", x, y, "Range: [INVALID]", cWarn); y += 17;
      DashLabel("ANTU_V3_RL", x, y, "", cWhite); y += 17;
      DashLabel("ANTU_V3_RS", x, y, "", cWhite); y += 17;
   }
   y += 5;

   // P&L
   DashLabel("ANTU_V3_DIV3", x, y, "------ DAILY P&L ------", clrSlateGray); y += 17;
   double total = g_dailyPnL + GetFloatingPnL();
   double pct = (InpDailyProfitTarget > 0) ? (total / InpDailyProfitTarget * 100.0) : 0;
   color pnlClr = (total >= 0) ? cGood : cBad;
   DashLabel("ANTU_V3_PNL", x, y,
             "P&L: $" + DoubleToString(total,2) + " (" + DoubleToString(pct,0) + "%)",
             pnlClr); y += 17;
   DashLabel("ANTU_V3_TGT", x, y,
             "Target: $" + DoubleToString(InpDailyProfitTarget,0) +
             " | Loss: -$" + DoubleToString(InpDailyLossLimit,0), cWhite); y += 17;
   DashLabel("ANTU_V3_TRD", x, y,
             "Trades: " + IntegerToString(g_tradesToday) + "/" + IntegerToString(InpMaxTradesPerDay) +
             "  Open: " + IntegerToString(CountOpenPositions()), cWhite); y += 17;
   DashLabel("ANTU_V3_CL", x, y,
             "Consec L: " + IntegerToString(g_consecLosses), cWhite); y += 22;

   DashLabel("ANTU_V3_LAST", x, y, "Last: " + StringSubstr(g_lastSignalReason, 0, 38),
             clrLightGray, 8);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
