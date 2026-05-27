//+------------------------------------------------------------------+
//|                              ANTU_PROFITENGINE_v01_AllInOne.mq5  |
//|                                                                  |
//|  ANTU PROFIT ENGINE v01 - ALL-IN-ONE SINGLE FILE VERSION         |
//|  No include files needed - bas yeh ek file MQL5/Experts/ me      |
//|  daal do, F7 press karo, ho gaya!                                |
//|                                                                  |
//|  Symbol:    XAUUSD (Gold)                                        |
//|  Broker:    Vantage                                              |
//|  Account:   $300 starter                                         |
//|  Target:    $15-20 daily profit (consistent)                     |
//|  Strategy:  Mean Reversion in Asian Session range                |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property link      ""
#property version   "1.00"
#property strict
#property description "Sideways/Range XAUUSD scalper - $300 account, $15-20 daily target"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "===== GENERAL ====="
input ulong   InpMagicNumber       = 20260101;     // Magic Number
input string  InpComment           = "ANTU_PE_v01";// Trade comment

input group "===== RANGE DETECTION (Asian Session) ====="
input int     InpAsianStart        = 0;            // Asian Start Hour (Server)
input int     InpAsianEnd          = 7;            // Asian End Hour (Server)
input double  InpMinRangePips      = 30.0;         // Min Range (pips)
input double  InpMaxRangePips      = 80.0;         // Max Range (pips)
input double  InpEntryBufferPips   = 3.0;          // Entry Buffer from boundary

input group "===== SIGNAL ENGINE ====="
input ENUM_TIMEFRAMES InpSignalTF  = PERIOD_M5;    // Signal Timeframe
input double  InpRSIOversold       = 35.0;         // RSI Oversold (BUY) - relaxed
input double  InpRSIOverbought     = 65.0;         // RSI Overbought (SELL) - relaxed
input bool    InpRequireCandleConf = false;        // Require candle confirmation

input group "===== SAFETY FILTERS ====="
input double  InpMaxADX            = 30.0;         // Max ADX (gold tuned, relaxed)
input double  InpMaxATR            = 8.0;          // Max ATR (gold real volatility)
input int     InpMaxSpread         = 50;           // Max Spread (Vantage XAUUSD)
input int     InpSessionStart      = 0;            // Trade Session Start (hr)
input int     InpSessionEnd        = 20;           // Trade Session End (hr) - extended

input group "===== RANGE DETECTION OVERRIDE ====="
input bool    InpUseFallbackRange  = true;         // Use last 24h H/L if Asian invalid
input bool    InpDebugLog          = true;         // Print signal block reasons

input group "===== TRADE PARAMETERS ====="
input double  InpStopLossPips      = 15.0;         // Stop Loss (pips)
input double  InpTakeProfitPips    = 20.0;         // Take Profit (pips) - bigger for $20 daily
input bool    InpUseAutoLot        = false;        // Auto Lot from Risk %
input double  InpManualLot         = 0.05;         // Manual Lot - 0.05 = ~$10 per win @ 20pip TP

input group "===== RISK MANAGEMENT ====="
input double  InpRiskPercent       = 2.5;          // Risk % per trade (relaxed for $20 target)
input double  InpDailyProfitTarget = 20.0;         // Daily Profit Target ($)
input double  InpDailyLossLimit    = 15.0;         // Daily Loss Limit ($)
input int     InpMaxTradesPerDay   = 5;            // Max Trades per Day
input int     InpMaxConsecLosses   = 3;            // Max Consec Losses (pause)
input double  InpMaxDrawdownPct    = 7.0;          // Max DD % (lock)

input group "===== DASHBOARD ====="
input bool    InpShowDashboard     = true;         // Show Dashboard
input int     InpDashUpdateSec     = 1;            // Update interval (sec)

//+------------------------------------------------------------------+
//| ENUMS & STRUCTS                                                  |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
};

enum ENUM_LOCK_REASON
{
   LOCK_NONE             = 0,
   LOCK_DAILY_LOSS       = 1,
   LOCK_DAILY_PROFIT     = 2,
   LOCK_CONSEC_LOSSES    = 3,
   LOCK_DRAWDOWN         = 4,
   LOCK_TRADE_LIMIT      = 5,
   LOCK_MANUAL           = 6
};

struct RangeData
{
   double   high;
   double   low;
   double   middle;
   double   sizePips;
   datetime startTime;
   datetime endTime;
   bool     isValid;
};

//+------------------------------------------------------------------+
//| ===== RANGE DETECTOR CLASS =====                                 |
//+------------------------------------------------------------------+
class CRangeDetector
{
private:
   string   m_symbol;
   int      m_asianStartHour;
   int      m_asianEndHour;
   double   m_minRangePips;
   double   m_maxRangePips;
   double   m_pipValue;

public:
   RangeData currentRange;

   CRangeDetector(string symbol, int asianStart, int asianEnd,
                  double minPips, double maxPips)
   {
      m_symbol = symbol;
      m_asianStartHour = asianStart;
      m_asianEndHour = asianEnd;
      m_minRangePips = minPips;
      m_maxRangePips = maxPips;

      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_pipValue = (digits == 3 || digits == 5) ?
                   SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10 :
                   SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      if(StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
         m_pipValue = 0.1;

      ZeroMemory(currentRange);
   }

   bool CalculateRange()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = m_asianStartHour;
      dt.min = 0;
      dt.sec = 0;
      datetime asianStart = StructToTime(dt);
      dt.hour = m_asianEndHour;
      datetime asianEnd = StructToTime(dt);

      if(TimeCurrent() < asianEnd)
      {
         asianStart -= 86400;
         asianEnd -= 86400;
      }

      double highArr[], lowArr[];
      ArraySetAsSeries(highArr, true);
      ArraySetAsSeries(lowArr, true);

      int copiedH = CopyHigh(m_symbol, PERIOD_M5, asianStart, asianEnd, highArr);
      int copiedL = CopyLow(m_symbol, PERIOD_M5, asianStart, asianEnd, lowArr);

      if(copiedH <= 0 || copiedL <= 0)
      {
         currentRange.isValid = false;
         return false;
      }

      double rHigh = highArr[ArrayMaximum(highArr)];
      double rLow  = lowArr[ArrayMinimum(lowArr)];
      double sizePips = (rHigh - rLow) / m_pipValue;

      currentRange.high      = rHigh;
      currentRange.low       = rLow;
      currentRange.middle    = (rHigh + rLow) / 2.0;
      currentRange.sizePips  = sizePips;
      currentRange.startTime = asianStart;
      currentRange.endTime   = asianEnd;

      currentRange.isValid = (sizePips >= m_minRangePips &&
                              sizePips <= m_maxRangePips);
      return currentRange.isValid;
   }

   //--- Fallback: use last N hours high/low if Asian invalid
   bool CalculateFallbackRange(int hoursBack = 12)
   {
      datetime end = TimeCurrent();
      datetime start = end - (hoursBack * 3600);

      double highArr[], lowArr[];
      ArraySetAsSeries(highArr, true);
      ArraySetAsSeries(lowArr, true);

      int copiedH = CopyHigh(m_symbol, PERIOD_M5, start, end, highArr);
      int copiedL = CopyLow(m_symbol, PERIOD_M5, start, end, lowArr);

      if(copiedH <= 0 || copiedL <= 0) return false;

      double rHigh = highArr[ArrayMaximum(highArr)];
      double rLow  = lowArr[ArrayMinimum(lowArr)];
      double sizePips = (rHigh - rLow) / m_pipValue;

      currentRange.high      = rHigh;
      currentRange.low       = rLow;
      currentRange.middle    = (rHigh + rLow) / 2.0;
      currentRange.sizePips  = sizePips;
      currentRange.startTime = start;
      currentRange.endTime   = end;

      // Fallback validation: only check upper limit (use it even if size big)
      currentRange.isValid = (sizePips >= 15.0); // minimum 15 pips for meaningful range
      return currentRange.isValid;
   }

   bool IsNearHigh(double price, double bufferPips = 3.0)
   {
      if(!currentRange.isValid) return false;
      double buffer = bufferPips * m_pipValue;
      return (price >= currentRange.high - buffer);
   }

   bool IsNearLow(double price, double bufferPips = 3.0)
   {
      if(!currentRange.isValid) return false;
      double buffer = bufferPips * m_pipValue;
      return (price <= currentRange.low + buffer);
   }

   double PipValue() { return m_pipValue; }
};

//+------------------------------------------------------------------+
//| ===== FILTERS CLASS =====                                        |
//+------------------------------------------------------------------+
class CFilters
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int      m_handleADX;
   int      m_handleATR;
   int      m_handleRSI;
   double   m_maxADX;
   double   m_maxATR;
   int      m_maxSpread;
   int      m_sessionStart;
   int      m_sessionEnd;

public:
   CFilters(string symbol, ENUM_TIMEFRAMES tf, double maxADX,
            double maxATR, int maxSpread, int sessStart, int sessEnd)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_maxADX = maxADX;
      m_maxATR = maxATR;
      m_maxSpread = maxSpread;
      m_sessionStart = sessStart;
      m_sessionEnd = sessEnd;
      m_handleADX = iADX(m_symbol, m_tf, 14);
      m_handleATR = iATR(m_symbol, m_tf, 14);
      m_handleRSI = iRSI(m_symbol, m_tf, 14, PRICE_CLOSE);
   }

   ~CFilters()
   {
      if(m_handleADX != INVALID_HANDLE) IndicatorRelease(m_handleADX);
      if(m_handleATR != INVALID_HANDLE) IndicatorRelease(m_handleATR);
      if(m_handleRSI != INVALID_HANDLE) IndicatorRelease(m_handleRSI);
   }

   double GetADX()
   {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(m_handleADX, 0, 0, 2, adx) <= 0) return -1;
      return adx[0];
   }

   double GetATR()
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_handleATR, 0, 0, 2, atr) <= 0) return -1;
      return atr[0];
   }

   double GetRSI()
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(m_handleRSI, 0, 0, 2, rsi) <= 0) return -1;
      return rsi[0];
   }

   int GetSpread()
   {
      return (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   }

   bool ADXOk()
   {
      double adx = GetADX();
      if(adx < 0) return false;
      return (adx < m_maxADX);
   }

   bool ATROk()
   {
      double atr = GetATR();
      if(atr < 0) return false;
      return (atr < m_maxATR);
   }

   bool SpreadOk() { return (GetSpread() <= m_maxSpread); }

   bool SessionOk()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
      if(dt.day_of_week == 5 && hour >= 18) return false;
      if(dt.day_of_week == 1 && hour < m_sessionStart) return false;
      if(m_sessionStart <= m_sessionEnd)
         return (hour >= m_sessionStart && hour < m_sessionEnd);
      else
         return (hour >= m_sessionStart || hour < m_sessionEnd);
   }

   bool AllFiltersOk()
   {
      return ADXOk() && ATROk() && SpreadOk() && SessionOk();
   }
};

//+------------------------------------------------------------------+
//| ===== SIGNAL ENGINE CLASS =====                                  |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   string         m_symbol;
   ENUM_TIMEFRAMES m_tf;
   double         m_rsiOversold;
   double         m_rsiOverbought;
   bool           m_requireCandleConf;

public:
   CSignalEngine(string symbol, ENUM_TIMEFRAMES tf,
                 double rsiOS = 30.0, double rsiOB = 70.0,
                 bool requireCandle = false)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_rsiOversold = rsiOS;
      m_rsiOverbought = rsiOB;
      m_requireCandleConf = requireCandle;
   }

   bool GetCandle(int shift, double &op, double &cl, double &hi, double &lo)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_tf, shift, 1, rates) <= 0) return false;
      op = rates[0].open;
      cl = rates[0].close;
      hi = rates[0].high;
      lo = rates[0].low;
      return true;
   }

   bool IsBullishCandle()
   {
      double op, cl, hi, lo;
      if(!GetCandle(1, op, cl, hi, lo)) return false;
      double body  = MathAbs(cl - op);
      double range = hi - lo;
      if(range == 0) return false;
      return (cl > op && body / range > 0.3);
   }

   bool IsBearishCandle()
   {
      double op, cl, hi, lo;
      if(!GetCandle(1, op, cl, hi, lo)) return false;
      double body  = MathAbs(cl - op);
      double range = hi - lo;
      if(range == 0) return false;
      return (cl < op && body / range > 0.3);
   }

   ENUM_SIGNAL CheckSignal(CRangeDetector *rangeDet, CFilters *filters, string &reason)
   {
      reason = "";
      if(!filters.AllFiltersOk())
      {
         reason = "Filters blocked: ";
         if(!filters.ADXOk())     reason += "ADX-high ";
         if(!filters.ATROk())     reason += "ATR-high ";
         if(!filters.SpreadOk())  reason += "Spread-high ";
         if(!filters.SessionOk()) reason += "Session-closed ";
         return SIGNAL_NONE;
      }
      if(!rangeDet.currentRange.isValid)
      {
         reason = "Range invalid";
         return SIGNAL_NONE;
      }

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double rsi = filters.GetRSI();

      bool nearLow  = rangeDet.IsNearLow(ask);
      bool nearHigh = rangeDet.IsNearHigh(bid);

      // BUY check
      if(nearLow)
      {
         if(rsi >= m_rsiOversold)
         {
            reason = "BUY zone hit but RSI=" + DoubleToString(rsi,1) +
                     " (need <" + DoubleToString(m_rsiOversold,1) + ")";
            return SIGNAL_NONE;
         }
         if(m_requireCandleConf && !IsBullishCandle())
         {
            reason = "BUY zone+RSI ok but no bullish candle";
            return SIGNAL_NONE;
         }
         return SIGNAL_BUY;
      }

      // SELL check
      if(nearHigh)
      {
         if(rsi <= m_rsiOverbought)
         {
            reason = "SELL zone hit but RSI=" + DoubleToString(rsi,1) +
                     " (need >" + DoubleToString(m_rsiOverbought,1) + ")";
            return SIGNAL_NONE;
         }
         if(m_requireCandleConf && !IsBearishCandle())
         {
            reason = "SELL zone+RSI ok but no bearish candle";
            return SIGNAL_NONE;
         }
         return SIGNAL_SELL;
      }

      reason = "Price not at range boundary (mid-range)";
      return SIGNAL_NONE;
   }
};

//+------------------------------------------------------------------+
//| ===== RISK MANAGER CLASS =====                                   |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   double   m_dailyProfitTarget;
   double   m_dailyLossLimit;
   double   m_riskPercent;
   int      m_maxTradesPerDay;
   int      m_maxConsecLosses;
   double   m_maxDrawdownPct;
   datetime m_dayStart;
   double   m_dayStartBalance;
   double   m_dailyPnL;
   int      m_tradesToday;
   int      m_consecLosses;
   datetime m_pauseUntil;
   bool     m_locked;
   ENUM_LOCK_REASON m_lockReason;

public:
   CRiskManager(double dailyProfit, double dailyLoss, double riskPct,
                int maxTrades, int maxConsecL, double maxDDPct)
   {
      m_dailyProfitTarget = dailyProfit;
      m_dailyLossLimit    = dailyLoss;
      m_riskPercent       = riskPct;
      m_maxTradesPerDay   = maxTrades;
      m_maxConsecLosses   = maxConsecL;
      m_maxDrawdownPct    = maxDDPct;
      ResetDay();
   }

   void ResetDay()
   {
      m_dayStart        = TimeCurrent();
      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_dailyPnL        = 0.0;
      m_tradesToday     = 0;
      m_consecLosses    = 0;
      m_pauseUntil      = 0;
      m_locked          = false;
      m_lockReason      = LOCK_NONE;
   }

   void CheckNewDay()
   {
      MqlDateTime dtNow, dtStart;
      TimeToStruct(TimeCurrent(), dtNow);
      TimeToStruct(m_dayStart, dtStart);
      if(dtNow.day != dtStart.day || dtNow.mon != dtStart.mon)
      {
         ResetDay();
         Print(">>> ANTU: New day started - counters reset");
      }
   }

   double CalculateLot(string symbol, double slPips, double pipValue)
   {
      double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount  = balance * (m_riskPercent / 100.0);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double slPoints  = slPips * (pipValue / point);
      double lossPerLot = slPoints * tickValue * (point / tickSize);
      if(lossPerLot <= 0) return 0.01;
      double lot = riskAmount / lossPerLot;
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(lot, minLot);
      lot = MathMin(lot, maxLot);
      double balanceCap = balance * 0.0002;
      lot = MathMin(lot, balanceCap);
      lot = MathMax(lot, minLot);
      return NormalizeDouble(lot, 2);
   }

   void OnTradeClosed(double profit)
   {
      m_dailyPnL += profit;
      m_tradesToday++;
      if(profit < 0) m_consecLosses++;
      else if(profit > 0) m_consecLosses = 0;
      if(m_consecLosses >= m_maxConsecLosses)
      {
         m_pauseUntil = TimeCurrent() + 7200;
         Print(">>> ANTU: ", m_consecLosses, " losses in row - paused 2hrs");
      }
   }

   bool CanTrade()
   {
      CheckNewDay();
      if(m_locked) return false;
      if(m_dailyPnL >= m_dailyProfitTarget)
      {
         m_locked = true;
         m_lockReason = LOCK_DAILY_PROFIT;
         return false;
      }
      if(m_dailyPnL <= -m_dailyLossLimit)
      {
         m_locked = true;
         m_lockReason = LOCK_DAILY_LOSS;
         return false;
      }
      if(m_tradesToday >= m_maxTradesPerDay)
      {
         m_locked = true;
         m_lockReason = LOCK_TRADE_LIMIT;
         return false;
      }
      double currBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double ddPct = (m_dayStartBalance - currBalance) / m_dayStartBalance * 100.0;
      if(ddPct >= m_maxDrawdownPct)
      {
         m_locked = true;
         m_lockReason = LOCK_DRAWDOWN;
         return false;
      }
      if(TimeCurrent() < m_pauseUntil) return false;
      return true;
   }

   void SetManualLock(bool lock)
   {
      m_locked = lock;
      m_lockReason = lock ? LOCK_MANUAL : LOCK_NONE;
   }

   double   DailyPnL()         { return m_dailyPnL; }
   double   DailyTarget()      { return m_dailyProfitTarget; }
   double   DailyLossLimit()   { return m_dailyLossLimit; }
   int      TradesToday()      { return m_tradesToday; }
   int      MaxTrades()        { return m_maxTradesPerDay; }
   int      ConsecLosses()     { return m_consecLosses; }
   bool     IsLocked()         { return m_locked; }
   datetime PausedUntil()      { return m_pauseUntil; }

   string LockReasonText()
   {
      switch(m_lockReason)
      {
         case LOCK_DAILY_LOSS:    return "Daily Loss Hit";
         case LOCK_DAILY_PROFIT:  return "Profit Target Hit";
         case LOCK_CONSEC_LOSSES: return "Consec Losses";
         case LOCK_DRAWDOWN:      return "Drawdown Limit";
         case LOCK_TRADE_LIMIT:   return "Max Trades";
         case LOCK_MANUAL:        return "Manual Lock";
         default:                 return "None";
      }
   }
};

//+------------------------------------------------------------------+
//| ===== TRADE MANAGER CLASS =====                                  |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade         m_trade;
   CPositionInfo  m_pos;
   string         m_symbol;
   ulong          m_magicNumber;
   string         m_comment;

public:
   CTradeManager(string symbol, ulong magic, string comment)
   {
      m_symbol      = symbol;
      m_magicNumber = magic;
      m_comment     = comment;
      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(m_symbol);
      m_trade.SetDeviationInPoints(20);
   }

   bool OpenBuy(double lot, double slPips, double tpPips, double pipValue)
   {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - slPips * pipValue,
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      double tp  = NormalizeDouble(ask + tpPips * pipValue,
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      bool result = m_trade.Buy(lot, m_symbol, ask, sl, tp, m_comment);
      if(result)
         Print(">>> ANTU BUY: ", lot, " lots @ ", ask, " SL:", sl, " TP:", tp);
      else
         Print(">>> ANTU BUY FAILED: ", m_trade.ResultRetcodeDescription());
      return result;
   }

   bool OpenSell(double lot, double slPips, double tpPips, double pipValue)
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + slPips * pipValue,
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      double tp  = NormalizeDouble(bid - tpPips * pipValue,
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      bool result = m_trade.Sell(lot, m_symbol, bid, sl, tp, m_comment);
      if(result)
         Print(">>> ANTU SELL: ", lot, " lots @ ", bid, " SL:", sl, " TP:", tp);
      else
         Print(">>> ANTU SELL FAILED: ", m_trade.ResultRetcodeDescription());
      return result;
   }

   int CountOpenPositions()
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_pos.SelectByIndex(i))
         {
            if(m_pos.Symbol() == m_symbol && m_pos.Magic() == m_magicNumber)
               count++;
         }
      }
      return count;
   }

   void CloseAll()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_pos.SelectByIndex(i))
         {
            if(m_pos.Symbol() == m_symbol && m_pos.Magic() == m_magicNumber)
               m_trade.PositionClose(m_pos.Ticket());
         }
      }
   }

   double GetFloatingPnL()
   {
      double total = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_pos.SelectByIndex(i))
         {
            if(m_pos.Symbol() == m_symbol && m_pos.Magic() == m_magicNumber)
               total += m_pos.Profit() + m_pos.Swap() + m_pos.Commission();
         }
      }
      return total;
   }

   ulong Magic() { return m_magicNumber; }
};

//+------------------------------------------------------------------+
//| ===== DASHBOARD CLASS =====                                      |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   string m_prefix;
   int    m_xStart;
   int    m_yStart;
   int    m_width;
   int    m_lineHeight;
   color  m_bgColor;
   color  m_textColor;
   color  m_goodColor;
   color  m_badColor;
   color  m_warnColor;
   color  m_headerColor;

   void CreateBG(string name, int x, int y, int w, int h, color clr)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   void CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 9)
   {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

public:
   CDashboard(string prefix = "ANTU_DASH_")
   {
      m_prefix      = prefix;
      m_xStart      = 15;
      m_yStart      = 25;
      m_width       = 280;
      m_lineHeight  = 17;
      m_bgColor     = C'25,25,35';
      m_textColor   = clrWhite;
      m_goodColor   = clrLime;
      m_badColor    = clrRed;
      m_warnColor   = clrOrange;
      m_headerColor = C'255,200,50';
   }

   void Init()
   {
      CreateBG(m_prefix + "BG", m_xStart - 5, m_yStart - 5, m_width, 380, m_bgColor);
      CreateBG(m_prefix + "HDR", m_xStart - 5, m_yStart - 5, m_width, 24, C'45,45,75');
   }

   void Update(string symbol, CRangeDetector *rangeDet,
               CFilters *filters, CRiskManager *risk,
               int openPositions, double floatingPnL)
   {
      int y = m_yStart;
      int x = m_xStart;

      CreateLabel(m_prefix + "TITLE", x, y, "  ANTU PROFITENGINE v01", m_headerColor, 10);
      y += m_lineHeight + 8;

      string statusText;
      color  statusClr;
      if(risk.IsLocked())
      {
         statusText = "STATUS:  [LOCKED] " + risk.LockReasonText();
         statusClr  = m_badColor;
      }
      else
      {
         statusText = "STATUS:  [ACTIVE]";
         statusClr  = m_goodColor;
      }
      CreateLabel(m_prefix + "STATUS", x, y, statusText, statusClr);
      y += m_lineHeight;

      bool isRange = filters.ADXOk() && filters.ATROk();
      CreateLabel(m_prefix + "MODE", x, y,
                  "Market: " + (isRange ? "[RANGE - OK]" : "[TREND - WAIT]"),
                  isRange ? m_goodColor : m_warnColor);
      y += m_lineHeight + 5;

      CreateLabel(m_prefix + "DIV1", x, y, "---------- RANGE ----------", clrSlateGray);
      y += m_lineHeight;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(rangeDet.currentRange.isValid)
      {
         CreateLabel(m_prefix + "RHIGH", x, y,
                     "High:   " + DoubleToString(rangeDet.currentRange.high, digits), m_textColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RLOW", x, y,
                     "Low:    " + DoubleToString(rangeDet.currentRange.low, digits), m_textColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RSIZE", x, y,
                     "Size:   " + DoubleToString(rangeDet.currentRange.sizePips, 1) + " pips", m_textColor);
         y += m_lineHeight;
      }
      else
      {
         CreateLabel(m_prefix + "RHIGH", x, y, "Range:  [INVALID]", m_warnColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RLOW", x, y, "", m_textColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RSIZE", x, y, "", m_textColor);
         y += m_lineHeight;
      }

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      CreateLabel(m_prefix + "RPRICE", x, y, "Price:  " + DoubleToString(bid, digits), m_headerColor);
      y += m_lineHeight + 5;

      CreateLabel(m_prefix + "DIV2", x, y, "---------- FILTERS --------", clrSlateGray);
      y += m_lineHeight;

      CreateLabel(m_prefix + "FADX", x, y,
                  "ADX:    " + DoubleToString(filters.GetADX(), 1) +
                  (filters.ADXOk() ? "  [OK]" : "  [TREND]"),
                  filters.ADXOk() ? m_goodColor : m_warnColor);
      y += m_lineHeight;

      CreateLabel(m_prefix + "FATR", x, y,
                  "ATR:    " + DoubleToString(filters.GetATR(), 2) +
                  (filters.ATROk() ? "  [OK]" : "  [HIGH]"),
                  filters.ATROk() ? m_goodColor : m_warnColor);
      y += m_lineHeight;

      CreateLabel(m_prefix + "FRSI", x, y,
                  "RSI:    " + DoubleToString(filters.GetRSI(), 1), m_textColor);
      y += m_lineHeight;

      CreateLabel(m_prefix + "FSPR", x, y,
                  "Spread: " + IntegerToString(filters.GetSpread()) + " pts" +
                  (filters.SpreadOk() ? "  [OK]" : "  [HIGH]"),
                  filters.SpreadOk() ? m_goodColor : m_warnColor);
      y += m_lineHeight;

      CreateLabel(m_prefix + "FSESS", x, y,
                  "Session: " + (filters.SessionOk() ? "[OPEN]" : "[CLOSED]"),
                  filters.SessionOk() ? m_goodColor : m_warnColor);
      y += m_lineHeight + 5;

      CreateLabel(m_prefix + "DIV3", x, y, "---------- TODAY ----------", clrSlateGray);
      y += m_lineHeight;

      double pnl   = risk.DailyPnL() + floatingPnL;
      double tgt   = risk.DailyTarget();
      double pct   = (tgt > 0) ? (pnl / tgt * 100.0) : 0.0;
      color  pnlClr = (pnl >= 0) ? m_goodColor : m_badColor;

      CreateLabel(m_prefix + "PNL", x, y,
                  "P&L:    $" + DoubleToString(pnl, 2) +
                  "  (" + DoubleToString(pct, 0) + "%)", pnlClr);
      y += m_lineHeight;

      CreateLabel(m_prefix + "TGT", x, y,
                  "Target: $" + DoubleToString(tgt, 2) +
                  " | Loss: -$" + DoubleToString(risk.DailyLossLimit(), 2), m_textColor);
      y += m_lineHeight;

      CreateLabel(m_prefix + "TRADES", x, y,
                  "Trades: " + IntegerToString(risk.TradesToday()) +
                  " / " + IntegerToString(risk.MaxTrades()), m_textColor);
      y += m_lineHeight;

      CreateLabel(m_prefix + "OPEN", x, y,
                  "Open:   " + IntegerToString(openPositions) +
                  "  | Float: $" + DoubleToString(floatingPnL, 2),
                  (floatingPnL >= 0) ? m_goodColor : m_badColor);
      y += m_lineHeight;

      CreateLabel(m_prefix + "CONSEC", x, y,
                  "Consec L: " + IntegerToString(risk.ConsecLosses()),
                  (risk.ConsecLosses() > 0) ? m_warnColor : m_textColor);
      y += m_lineHeight + 5;

      CreateLabel(m_prefix + "LOCK", x, y,
                  "EMERGENCY: " + (risk.IsLocked() ? "[ACTIVE]" : "[OFF]"),
                  risk.IsLocked() ? m_badColor : m_goodColor);

      ChartRedraw(0);
   }

   void Cleanup()
   {
      ObjectsDeleteAll(0, m_prefix);
      ChartRedraw(0);
   }
};

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS                                                   |
//+------------------------------------------------------------------+
CRangeDetector *g_range    = NULL;
CFilters       *g_filters  = NULL;
CSignalEngine  *g_signal   = NULL;
CRiskManager   *g_risk     = NULL;
CTradeManager  *g_trade    = NULL;
CDashboard     *g_dash     = NULL;

datetime g_lastBarTime = 0;
datetime g_lastDashUpdate = 0;
double   g_lastFloatingPnL = 0;
int      g_lastOpenCount = 0;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("================================================");
   Print(" ANTU PROFIT ENGINE v01 - INITIALIZING");
   Print(" Symbol: ", _Symbol);
   Print(" Account: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print(" Daily Target: $", InpDailyProfitTarget,
         " | Loss Limit: $", InpDailyLossLimit);
   Print("================================================");

   g_range = new CRangeDetector(_Symbol, InpAsianStart, InpAsianEnd,
                                InpMinRangePips, InpMaxRangePips);

   g_filters = new CFilters(_Symbol, InpSignalTF, InpMaxADX, InpMaxATR,
                            InpMaxSpread, InpSessionStart, InpSessionEnd);

   g_signal = new CSignalEngine(_Symbol, InpSignalTF,
                                InpRSIOversold, InpRSIOverbought,
                                InpRequireCandleConf);

   g_risk = new CRiskManager(InpDailyProfitTarget, InpDailyLossLimit,
                             InpRiskPercent, InpMaxTradesPerDay,
                             InpMaxConsecLosses, InpMaxDrawdownPct);

   g_trade = new CTradeManager(_Symbol, InpMagicNumber, InpComment);

   if(InpShowDashboard)
   {
      g_dash = new CDashboard("ANTU_DASH_");
      g_dash.Init();
   }

   if(!g_range.CalculateRange() && InpUseFallbackRange)
      g_range.CalculateFallbackRange(12);

   Print(">>> ANTU READY - Strategy active");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_dash != NULL)    { g_dash.Cleanup(); delete g_dash;   g_dash = NULL; }
   if(g_trade != NULL)   { delete g_trade;   g_trade = NULL; }
   if(g_risk != NULL)    { delete g_risk;    g_risk = NULL; }
   if(g_signal != NULL)  { delete g_signal;  g_signal = NULL; }
   if(g_filters != NULL) { delete g_filters; g_filters = NULL; }
   if(g_range != NULL)   { delete g_range;   g_range = NULL; }

   Print(">>> ANTU PROFIT ENGINE v01 - Stopped (reason: ", reason, ")");
}

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION (Main Loop)                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   g_risk.CheckNewDay();

   if(InpShowDashboard && g_dash != NULL)
   {
      if(TimeCurrent() - g_lastDashUpdate >= InpDashUpdateSec)
      {
         g_lastFloatingPnL = g_trade.GetFloatingPnL();
         g_lastOpenCount   = g_trade.CountOpenPositions();
         g_dash.Update(_Symbol, g_range, g_filters, g_risk,
                       g_lastOpenCount, g_lastFloatingPnL);
         g_lastDashUpdate = TimeCurrent();
      }
   }

   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, InpSignalTF,
                                                     SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime) return;
   g_lastBarTime = curBarTime;

   // Calculate range, with fallback if Asian invalid
   if(!g_range.CalculateRange() && InpUseFallbackRange)
   {
      g_range.CalculateFallbackRange(12);  // last 12h H/L
   }

   if(!g_risk.CanTrade())
   {
      if(InpDebugLog)
         Print(">>> ANTU SKIP: Risk blocked - ", g_risk.LockReasonText());
      return;
   }
   if(g_trade.CountOpenPositions() > 0) return;

   string sigReason = "";
   ENUM_SIGNAL sig = g_signal.CheckSignal(g_range, g_filters, sigReason);
   if(sig == SIGNAL_NONE)
   {
      if(InpDebugLog && sigReason != "")
      {
         Print(">>> ANTU NO SIGNAL: ", sigReason,
               " | ADX=", DoubleToString(g_filters.GetADX(),1),
               " ATR=", DoubleToString(g_filters.GetATR(),2),
               " RSI=", DoubleToString(g_filters.GetRSI(),1),
               " RangeValid=", g_range.currentRange.isValid);
      }
      return;
   }

   double lot = InpManualLot;
   if(InpUseAutoLot)
      lot = g_risk.CalculateLot(_Symbol, InpStopLossPips, g_range.PipValue());

   if(sig == SIGNAL_BUY)
   {
      Print(">>> ANTU SIGNAL: BUY (Range Low Bounce)");
      g_trade.OpenBuy(lot, InpStopLossPips, InpTakeProfitPips, g_range.PipValue());
   }
   else if(sig == SIGNAL_SELL)
   {
      Print(">>> ANTU SIGNAL: SELL (Range High Rejection)");
      g_trade.OpenSell(lot, InpStopLossPips, InpTakeProfitPips, g_range.PipValue());
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION HANDLER                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

         if(magic == (long)InpMagicNumber && entry == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                            HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                            HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            g_risk.OnTradeClosed(profit);
            Print(">>> ANTU TRADE CLOSED: P/L = $", DoubleToString(profit, 2),
                  " | Daily P/L = $", DoubleToString(g_risk.DailyPnL(), 2),
                  " | Trades = ", g_risk.TradesToday());
         }
      }
   }
}
//+------------------------------------------------------------------+
