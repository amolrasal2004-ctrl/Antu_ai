//+------------------------------------------------------------------+
//|                       ANTU_PROFITENGINE_v02_DualStrategy.mq5     |
//|                                                                  |
//|  ANTU PROFIT ENGINE v02 - DUAL STRATEGY EA                       |
//|                                                                  |
//|  AUTOMATIC strategy selection based on market mode:              |
//|                                                                  |
//|   ADX < 25  =>  Strategy A: RANGE (Mean Reversion)               |
//|                  Buy at Asian range low, Sell at high             |
//|                                                                  |
//|   ADX >= 25 =>  Strategy B: TREND (EMA Pullback)                 |
//|                  Trend up = buy on EMA pullback                  |
//|                  Trend down = sell on EMA pullback               |
//|                                                                  |
//|  Result: Trades in BOTH market types = more opportunities!       |
//|                                                                  |
//|  Symbol:    XAUUSD (Gold)                                        |
//|  Broker:    Vantage                                              |
//|  Account:   $300 starter                                         |
//|  Target:    $10-15 daily profit (sustainable)                    |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v02 - Dual Strategy"
#property link      ""
#property version   "2.00"
#property strict
#property description "XAUUSD Dual Strategy: Range + Trend Pullback. Trades BOTH market types."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "===== GENERAL ====="
input ulong   InpMagicNumber       = 20260201;     // Magic Number (different from v01)
input string  InpComment           = "ANTU_PE_v02";// Trade comment

input group "===== STRATEGY MODE SELECTION ====="
input bool    InpUseRangeStrategy  = true;         // Strategy A: Range (sideways)
input bool    InpUseTrendStrategy  = true;         // Strategy B: Trend (pullback)
input double  InpADXThreshold      = 25.0;         // ADX threshold (below=range, above=trend)

input group "===== RANGE STRATEGY (Strategy A) ====="
input int     InpAsianStart        = 0;            // Asian Start Hour
input int     InpAsianEnd          = 7;            // Asian End Hour
input double  InpMinRangePips      = 20.0;         // Min Range (pips)
input double  InpMaxRangePips      = 120.0;        // Max Range (pips)
input double  InpEntryBufferPips   = 8.0;          // Entry Buffer from boundary
input double  InpRangeRSIOversold  = 40.0;         // Range: RSI Oversold (BUY)
input double  InpRangeRSIOverbought= 60.0;         // Range: RSI Overbought (SELL)

input group "===== TREND STRATEGY (Strategy B) ====="
input int     InpFastEMA           = 20;           // Fast EMA (trend)
input int     InpSlowEMA           = 50;           // Slow EMA (filter)
input double  InpPullbackPips      = 10.0;         // Pullback distance from EMA
input double  InpTrendRSIBuy       = 50.0;         // Trend BUY: RSI must be > this
input double  InpTrendRSISell      = 50.0;         // Trend SELL: RSI must be < this

input group "===== COMMON FILTERS ====="
input ENUM_TIMEFRAMES InpSignalTF  = PERIOD_M5;    // Signal Timeframe
input double  InpMaxATR            = 12.0;         // Max ATR (extreme volatility block)
input int     InpMaxSpread         = 60;           // Max Spread (points)
input int     InpSessionStart      = 0;            // Trade Session Start
input int     InpSessionEnd        = 22;           // Trade Session End

input group "===== TRADE PARAMETERS ====="
input double  InpStopLossPips      = 15.0;         // Stop Loss (pips)
input double  InpTakeProfitPips    = 25.0;         // Take Profit (pips) - 1:1.66 R:R
input double  InpManualLot         = 0.03;         // Manual Lot

input group "===== RISK MANAGEMENT ====="
input double  InpDailyProfitTarget = 12.0;         // Daily Profit Target ($)
input double  InpDailyLossLimit    = 9.0;          // Daily Loss Limit ($)
input int     InpMaxTradesPerDay   = 6;            // Max Trades per Day (more for dual)
input int     InpMaxConsecLosses   = 3;            // Max Consec Losses (pause)
input double  InpMaxDrawdownPct    = 6.0;          // Max DD % (lock)

input group "===== DASHBOARD & LOG ====="
input bool    InpShowDashboard     = true;         // Show Dashboard
input int     InpDashUpdateSec     = 1;            // Update interval (sec)
input bool    InpDebugLog          = true;         // Print no-signal reasons

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL  { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = 2 };
enum ENUM_MODE    { MODE_RANGE = 0, MODE_TREND = 1, MODE_NONE = 2 };
enum ENUM_LOCK    { LOCK_NONE=0, LOCK_PROFIT=1, LOCK_LOSS=2, LOCK_TRADES=3, LOCK_DD=4, LOCK_PAUSE=5 };

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

double   g_pipValue = 0.1;  // XAUUSD pip
datetime g_lastBarTime = 0;
datetime g_lastDashUpdate = 0;

// Range data
double   g_rangeHigh = 0;
double   g_rangeLow = 0;
double   g_rangeSizePips = 0;
bool     g_rangeValid = false;

// Daily counters
datetime g_dayStart = 0;
double   g_dayStartBalance = 0;
double   g_dailyPnL = 0;
int      g_tradesToday = 0;
int      g_consecLosses = 0;
datetime g_pauseUntil = 0;
bool     g_locked = false;
ENUM_LOCK g_lockReason = LOCK_NONE;

// Last signal info for dashboard
string   g_lastSignalReason = "Waiting for first bar...";
ENUM_MODE g_lastMode = MODE_NONE;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("================================================");
   Print(" ANTU PROFITENGINE v02 - DUAL STRATEGY");
   Print(" Symbol: ", _Symbol);
   Print(" Account: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print(" Strategies: Range=", InpUseRangeStrategy, " | Trend=", InpUseTrendStrategy);
   Print(" ADX Threshold: ", InpADXThreshold, " (below=range, above=trend)");
   Print(" Daily Target: $", InpDailyProfitTarget, " | Loss Limit: $", InpDailyLossLimit);
   Print("================================================");

   // Initialize indicator handles
   g_handleADX     = iADX(_Symbol, InpSignalTF, 14);
   g_handleATR     = iATR(_Symbol, InpSignalTF, 14);
   g_handleRSI     = iRSI(_Symbol, InpSignalTF, 14, PRICE_CLOSE);
   g_handleFastEMA = iMA(_Symbol, InpSignalTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_handleSlowEMA = iMA(_Symbol, InpSignalTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(g_handleADX == INVALID_HANDLE || g_handleATR == INVALID_HANDLE ||
      g_handleRSI == INVALID_HANDLE || g_handleFastEMA == INVALID_HANDLE ||
      g_handleSlowEMA == INVALID_HANDLE)
   {
      Print(">>> ANTU ERROR: Indicator handle creation failed");
      return INIT_FAILED;
   }

   // XAUUSD pip = 0.10
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      g_pipValue = 0.1;
   else
      g_pipValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;

   // Trade setup
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(20);

   ResetDay();

   // Calculate initial range
   CalculateRange();

   // Init dashboard background
   if(InpShowDashboard) DashboardInit();

   Print(">>> ANTU v02 READY - Pip Value: ", g_pipValue);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_handleADX != INVALID_HANDLE)     IndicatorRelease(g_handleADX);
   if(g_handleATR != INVALID_HANDLE)     IndicatorRelease(g_handleATR);
   if(g_handleRSI != INVALID_HANDLE)     IndicatorRelease(g_handleRSI);
   if(g_handleFastEMA != INVALID_HANDLE) IndicatorRelease(g_handleFastEMA);
   if(g_handleSlowEMA != INVALID_HANDLE) IndicatorRelease(g_handleSlowEMA);

   ObjectsDeleteAll(0, "ANTU_V2_");
   ChartRedraw(0);
   Print(">>> ANTU v02 STOPPED (reason: ", reason, ")");
}

//+------------------------------------------------------------------+
//| INDICATOR HELPER FUNCTIONS                                       |
//+------------------------------------------------------------------+
double GetIndicator(int handle, int buffer = 0, int shift = 0)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer, shift, 1, arr) <= 0) return -1;
   return arr[0];
}

double GetADX() { return GetIndicator(g_handleADX, 0); }
double GetATR() { return GetIndicator(g_handleATR, 0); }
double GetRSI() { return GetIndicator(g_handleRSI, 0); }
double GetFastEMA(int shift = 0) { return GetIndicator(g_handleFastEMA, 0, shift); }
double GetSlowEMA(int shift = 0) { return GetIndicator(g_handleSlowEMA, 0, shift); }

int GetSpread() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

bool IsSessionOpen()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;       // Weekend
   if(dt.day_of_week == 5 && dt.hour >= 18) return false;             // Friday close
   if(dt.day_of_week == 1 && dt.hour < InpSessionStart) return false; // Mon early
   return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
}

//+------------------------------------------------------------------+
//| RANGE CALCULATION (Asian Session + Fallback)                     |
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

   int copiedH = CopyHigh(_Symbol, PERIOD_M5, asianStart, asianEnd, highArr);
   int copiedL = CopyLow(_Symbol, PERIOD_M5, asianStart, asianEnd, lowArr);

   if(copiedH > 0 && copiedL > 0)
   {
      g_rangeHigh = highArr[ArrayMaximum(highArr)];
      g_rangeLow  = lowArr[ArrayMinimum(lowArr)];
      g_rangeSizePips = (g_rangeHigh - g_rangeLow) / g_pipValue;
      g_rangeValid = (g_rangeSizePips >= InpMinRangePips &&
                      g_rangeSizePips <= InpMaxRangePips);

      // Fallback: if Asian invalid, use last 12h
      if(!g_rangeValid)
      {
         datetime end = TimeCurrent();
         datetime start = end - 12 * 3600;
         CopyHigh(_Symbol, PERIOD_M5, start, end, highArr);
         CopyLow(_Symbol, PERIOD_M5, start, end, lowArr);
         if(ArraySize(highArr) > 0 && ArraySize(lowArr) > 0)
         {
            g_rangeHigh = highArr[ArrayMaximum(highArr)];
            g_rangeLow  = lowArr[ArrayMinimum(lowArr)];
            g_rangeSizePips = (g_rangeHigh - g_rangeLow) / g_pipValue;
            g_rangeValid = (g_rangeSizePips >= 15.0);
         }
      }
   }
   else
   {
      g_rangeValid = false;
   }
}

//+------------------------------------------------------------------+
//| STRATEGY A: RANGE (Mean Reversion)                               |
//+------------------------------------------------------------------+
SignalResult CheckRangeStrategy()
{
   SignalResult res;
   res.signal = SIG_NONE;
   res.mode = MODE_RANGE;
   res.reason = "";

   if(!g_rangeValid)
   {
      res.reason = "Range invalid";
      return res;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double rsi = GetRSI();
   double bufferPrice = InpEntryBufferPips * g_pipValue;

   // Near range LOW + RSI oversold = BUY
   if(ask <= g_rangeLow + bufferPrice)
   {
      if(rsi < InpRangeRSIOversold)
      {
         res.signal = SIG_BUY;
         res.reason = "RANGE BUY: range_low + RSI=" + DoubleToString(rsi,1);
      }
      else
      {
         res.reason = "Range BUY zone but RSI=" + DoubleToString(rsi,1) +
                      " (need <" + DoubleToString(InpRangeRSIOversold,1) + ")";
      }
      return res;
   }

   // Near range HIGH + RSI overbought = SELL
   if(bid >= g_rangeHigh - bufferPrice)
   {
      if(rsi > InpRangeRSIOverbought)
      {
         res.signal = SIG_SELL;
         res.reason = "RANGE SELL: range_high + RSI=" + DoubleToString(rsi,1);
      }
      else
      {
         res.reason = "Range SELL zone but RSI=" + DoubleToString(rsi,1) +
                      " (need >" + DoubleToString(InpRangeRSIOverbought,1) + ")";
      }
      return res;
   }

   res.reason = "Price mid-range, no setup";
   return res;
}

//+------------------------------------------------------------------+
//| STRATEGY B: TREND (EMA Pullback)                                 |
//+------------------------------------------------------------------+
SignalResult CheckTrendStrategy()
{
   SignalResult res;
   res.signal = SIG_NONE;
   res.mode = MODE_TREND;
   res.reason = "";

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double midPrice = (bid + ask) / 2.0;

   double fastEMA = GetFastEMA(0);
   double slowEMA = GetSlowEMA(0);
   double rsi = GetRSI();

   if(fastEMA < 0 || slowEMA < 0)
   {
      res.reason = "EMA not ready";
      return res;
   }

   // Determine trend
   bool uptrend = (fastEMA > slowEMA);
   bool downtrend = (fastEMA < slowEMA);

   double pullbackDist = InpPullbackPips * g_pipValue;

   // UPTREND: price pulled back near fast EMA = BUY opportunity
   if(uptrend)
   {
      // Price should be near or just above fast EMA (pullback)
      if(midPrice >= fastEMA - pullbackDist && midPrice <= fastEMA + pullbackDist)
      {
         if(rsi > InpTrendRSIBuy)
         {
            res.signal = SIG_BUY;
            res.reason = "TREND BUY: uptrend + EMA pullback + RSI=" + DoubleToString(rsi,1);
         }
         else
         {
            res.reason = "Uptrend pullback but RSI=" + DoubleToString(rsi,1) +
                         " (need >" + DoubleToString(InpTrendRSIBuy,1) + ")";
         }
         return res;
      }
      res.reason = "Uptrend but price away from EMA pullback zone";
      return res;
   }

   // DOWNTREND: price pulled back near fast EMA = SELL opportunity
   if(downtrend)
   {
      if(midPrice >= fastEMA - pullbackDist && midPrice <= fastEMA + pullbackDist)
      {
         if(rsi < InpTrendRSISell)
         {
            res.signal = SIG_SELL;
            res.reason = "TREND SELL: downtrend + EMA pullback + RSI=" + DoubleToString(rsi,1);
         }
         else
         {
            res.reason = "Downtrend pullback but RSI=" + DoubleToString(rsi,1) +
                         " (need <" + DoubleToString(InpTrendRSISell,1) + ")";
         }
         return res;
      }
      res.reason = "Downtrend but price away from EMA pullback zone";
      return res;
   }

   res.reason = "No clear trend (fast EMA = slow EMA)";
   return res;
}

//+------------------------------------------------------------------+
//| MASTER SIGNAL CHECK (auto-select strategy)                       |
//+------------------------------------------------------------------+
SignalResult GetSignal()
{
   SignalResult res;
   res.signal = SIG_NONE;
   res.mode = MODE_NONE;
   res.reason = "";

   // Common filters first
   if(!IsSessionOpen())
   {
      res.reason = "Session closed";
      return res;
   }

   if(GetSpread() > InpMaxSpread)
   {
      res.reason = "Spread too high (" + IntegerToString(GetSpread()) + ")";
      return res;
   }

   double atr = GetATR();
   if(atr > InpMaxATR)
   {
      res.reason = "ATR too high (" + DoubleToString(atr,2) + ") - extreme volatility";
      return res;
   }

   double adx = GetADX();
   if(adx < 0)
   {
      res.reason = "ADX not ready";
      return res;
   }

   // STRATEGY SELECTION based on ADX
   bool isRangeMarket = (adx < InpADXThreshold);
   bool isTrendMarket = (adx >= InpADXThreshold);

   // Try Range strategy first (if applicable)
   if(isRangeMarket && InpUseRangeStrategy)
   {
      res = CheckRangeStrategy();
      if(res.signal != SIG_NONE)
         return res;
      // If range gave no signal, also try trend (some setups overlap)
   }

   // Try Trend strategy (if applicable)
   if(isTrendMarket && InpUseTrendStrategy)
   {
      res = CheckTrendStrategy();
      if(res.signal != SIG_NONE)
         return res;
   }

   // No signal from either strategy
   if(res.reason == "")
   {
      if(isRangeMarket)
         res.reason = "RANGE mode (ADX=" + DoubleToString(adx,1) + ") - no setup";
      else
         res.reason = "TREND mode (ADX=" + DoubleToString(adx,1) + ") - no setup";
   }
   res.mode = isRangeMarket ? MODE_RANGE : MODE_TREND;
   return res;
}

//+------------------------------------------------------------------+
//| ORDER EXECUTION                                                  |
//+------------------------------------------------------------------+
bool OpenBuy(string comment)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(ask - InpStopLossPips * g_pipValue, digits);
   double tp = NormalizeDouble(ask + InpTakeProfitPips * g_pipValue, digits);

   if(g_trade.Buy(InpManualLot, _Symbol, ask, sl, tp, InpComment + " " + comment))
   {
      Print(">>> ANTU BUY: ", InpManualLot, " @ ", ask, " SL:", sl, " TP:", tp, " | ", comment);
      return true;
   }
   Print(">>> ANTU BUY FAILED: ", g_trade.ResultRetcodeDescription());
   return false;
}

bool OpenSell(string comment)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(bid + InpStopLossPips * g_pipValue, digits);
   double tp = NormalizeDouble(bid - InpTakeProfitPips * g_pipValue, digits);

   if(g_trade.Sell(InpManualLot, _Symbol, bid, sl, tp, InpComment + " " + comment))
   {
      Print(">>> ANTU SELL: ", InpManualLot, " @ ", bid, " SL:", sl, " TP:", tp, " | ", comment);
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
      if(g_pos.SelectByIndex(i) &&
         g_pos.Symbol() == _Symbol &&
         g_pos.Magic() == InpMagicNumber)
         count++;
   }
   return count;
}

double GetFloatingPnL()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i) &&
         g_pos.Symbol() == _Symbol &&
         g_pos.Magic() == InpMagicNumber)
      {
         total += g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      }
   }
   return total;
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
      Print(">>> ANTU: New day - counters reset");
   }
}

bool CanTrade()
{
   CheckNewDay();
   if(g_locked) return false;

   if(g_dailyPnL >= InpDailyProfitTarget)
   {
      g_locked = true; g_lockReason = LOCK_PROFIT;
      Print(">>> ANTU LOCKED: Daily profit target hit ($", g_dailyPnL, ")");
      return false;
   }
   if(g_dailyPnL <= -InpDailyLossLimit)
   {
      g_locked = true; g_lockReason = LOCK_LOSS;
      Print(">>> ANTU LOCKED: Daily loss limit hit ($", g_dailyPnL, ")");
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
      g_pauseUntil = TimeCurrent() + 7200;  // 2 hr pause
      Print(">>> ANTU PAUSE: ", g_consecLosses, " losses - 2hr pause");
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
      case LOCK_PAUSE:  return "Paused";
      default:          return "None";
   }
}

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION (Main Loop)                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckNewDay();

   // Update dashboard frequently
   if(InpShowDashboard && TimeCurrent() - g_lastDashUpdate >= InpDashUpdateSec)
   {
      DashboardUpdate();
      g_lastDashUpdate = TimeCurrent();
   }

   // Process signals only on new bar
   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, InpSignalTF, SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime) return;
   g_lastBarTime = curBarTime;

   // Refresh range
   CalculateRange();

   // Risk gate
   if(!CanTrade())
   {
      if(InpDebugLog) Print(">>> ANTU SKIP: ", LockReasonText());
      return;
   }

   if(CountOpenPositions() > 0) return; // Already in trade

   // Get signal from dual strategy
   SignalResult sig = GetSignal();
   g_lastSignalReason = sig.reason;
   g_lastMode = sig.mode;

   if(sig.signal == SIG_NONE)
   {
      if(InpDebugLog && sig.reason != "")
      {
         Print(">>> NO SIGNAL: ", sig.reason,
               " | ADX=", DoubleToString(GetADX(),1),
               " ATR=", DoubleToString(GetATR(),2),
               " RSI=", DoubleToString(GetRSI(),1));
      }
      return;
   }

   // Execute trade
   string modeStr = (sig.mode == MODE_RANGE) ? "RANGE" : "TREND";
   if(sig.signal == SIG_BUY)
   {
      Print(">>> ANTU SIGNAL [", modeStr, "]: BUY - ", sig.reason);
      OpenBuy("[" + modeStr + "]");
   }
   else if(sig.signal == SIG_SELL)
   {
      Print(">>> ANTU SIGNAL [", modeStr, "]: SELL - ", sig.reason);
      OpenSell("[" + modeStr + "]");
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION HANDLER                                        |
//+------------------------------------------------------------------+
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
//| DASHBOARD - INIT                                                 |
//+------------------------------------------------------------------+
void DashboardInit()
{
   string n = "ANTU_V2_BG";
   ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, 280);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, 410);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C'25,25,35');
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);

   // Header
   string h = "ANTU_V2_HDR";
   ObjectCreate(0, h, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, h, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, h, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, h, OBJPROP_XSIZE, 280);
   ObjectSetInteger(0, h, OBJPROP_YSIZE, 24);
   ObjectSetInteger(0, h, OBJPROP_BGCOLOR, C'45,45,75');
   ObjectSetInteger(0, h, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, h, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, h, OBJPROP_BACK, false);
   ObjectSetInteger(0, h, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| DASHBOARD - LABEL HELPER                                         |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| DASHBOARD - UPDATE                                               |
//+------------------------------------------------------------------+
void DashboardUpdate()
{
   color cWhite = clrWhite, cGood = clrLime, cBad = clrRed,
         cWarn = clrOrange, cGold = C'255,200,50';
   int x = 25, y = 25;

   // Title
   DashLabel("ANTU_V2_TITLE", x, y, "ANTU PROFITENGINE v02 [DUAL]", cGold, 10);
   y += 22;

   // Status
   string statusTxt; color statusClr;
   if(g_locked) {
      statusTxt = "STATUS: [LOCKED] " + LockReasonText();
      statusClr = cBad;
   } else {
      statusTxt = "STATUS: [ACTIVE]";
      statusClr = cGood;
   }
   DashLabel("ANTU_V2_STATUS", x, y, statusTxt, statusClr); y += 18;

   // Current Mode
   double adx = GetADX();
   string modeTxt;
   color modeClr;
   if(adx < 0) {
      modeTxt = "Mode:   [LOADING...]"; modeClr = cWarn;
   } else if(adx < InpADXThreshold) {
      modeTxt = "Mode:   [A] RANGE (ADX=" + DoubleToString(adx,1) + ")";
      modeClr = cGood;
   } else {
      modeTxt = "Mode:   [B] TREND (ADX=" + DoubleToString(adx,1) + ")";
      modeClr = cWarn;
   }
   DashLabel("ANTU_V2_MODE", x, y, modeTxt, modeClr); y += 23;

   // Section: Range
   DashLabel("ANTU_V2_DIV1", x, y, "------ RANGE STRATEGY ------", clrSlateGray); y += 17;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_rangeValid)
   {
      DashLabel("ANTU_V2_RH", x, y, "High: " + DoubleToString(g_rangeHigh, digits), cWhite); y += 17;
      DashLabel("ANTU_V2_RL", x, y, "Low:  " + DoubleToString(g_rangeLow, digits), cWhite); y += 17;
      DashLabel("ANTU_V2_RS", x, y, "Size: " + DoubleToString(g_rangeSizePips, 1) + " pips", cWhite); y += 17;
   } else {
      DashLabel("ANTU_V2_RH", x, y, "Range: [INVALID]", cWarn); y += 17;
      DashLabel("ANTU_V2_RL", x, y, "", cWhite); y += 17;
      DashLabel("ANTU_V2_RS", x, y, "", cWhite); y += 17;
   }
   y += 5;

   // Section: Trend
   DashLabel("ANTU_V2_DIV2", x, y, "------ TREND STRATEGY ------", clrSlateGray); y += 17;
   double fEMA = GetFastEMA(0), sEMA = GetSlowEMA(0);
   string trendStr;
   color trendClr;
   if(fEMA > 0 && sEMA > 0) {
      if(fEMA > sEMA) { trendStr = "Trend: UP";   trendClr = cGood; }
      else            { trendStr = "Trend: DOWN"; trendClr = cBad;  }
      DashLabel("ANTU_V2_TR", x, y, trendStr, trendClr); y += 17;
      DashLabel("ANTU_V2_FE", x, y, "EMA20: " + DoubleToString(fEMA, digits), cWhite); y += 17;
      DashLabel("ANTU_V2_SE", x, y, "EMA50: " + DoubleToString(sEMA, digits), cWhite); y += 17;
   } else {
      DashLabel("ANTU_V2_TR", x, y, "Trend: [LOADING]", cWarn); y += 17;
      DashLabel("ANTU_V2_FE", x, y, "", cWhite); y += 17;
      DashLabel("ANTU_V2_SE", x, y, "", cWhite); y += 17;
   }
   y += 5;

   // Daily P&L
   DashLabel("ANTU_V2_DIV3", x, y, "------ DAILY P&L ------", clrSlateGray); y += 17;
   double total = g_dailyPnL + GetFloatingPnL();
   double pct = (InpDailyProfitTarget > 0) ? (total / InpDailyProfitTarget * 100.0) : 0.0;
   color pnlClr = (total >= 0) ? cGood : cBad;
   DashLabel("ANTU_V2_PNL", x, y,
             "P&L: $" + DoubleToString(total, 2) + " (" + DoubleToString(pct, 0) + "%)",
             pnlClr); y += 17;
   DashLabel("ANTU_V2_TGT", x, y,
             "Target: $" + DoubleToString(InpDailyProfitTarget, 0) +
             " | Loss: -$" + DoubleToString(InpDailyLossLimit, 0), cWhite); y += 17;
   DashLabel("ANTU_V2_TRD", x, y,
             "Trades: " + IntegerToString(g_tradesToday) + "/" +
             IntegerToString(InpMaxTradesPerDay) +
             "  Open: " + IntegerToString(CountOpenPositions()), cWhite); y += 17;
   DashLabel("ANTU_V2_CL", x, y,
             "Consec L: " + IntegerToString(g_consecLosses) +
             "  ATR: " + DoubleToString(GetATR(), 2), cWhite); y += 22;

   // Last signal status
   DashLabel("ANTU_V2_LAST", x, y, "Last: " + StringSubstr(g_lastSignalReason, 0, 35),
             clrLightGray, 8);

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
