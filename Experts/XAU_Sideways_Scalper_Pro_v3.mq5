//+------------------------------------------------------------------+
//|                          XAU_Sideways_Scalper_Pro_v3.mq5         |
//|                                          Copyright 2026, Antu AI |
//|                                                                  |
//|  XAU Sideways Scalper Pro v3                                     |
//|  Single-file production-ready EA for XAUUSD M5.                  |
//|  Strategy = mean-reversion scalping inside confirmed sideways    |
//|  ranges only. Designed to run every day, every month, every year |
//|  with low drawdown.                                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antu AI"
#property version   "3.00"
#property strict
#property description "XAU Sideways Scalper Pro v3 - XAUUSD M5 mean-reversion scalper"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//============================== INPUTS ==============================

// --- General ---
input ulong  InpMagic                 = 20260601;
input string InpTradeComment          = "XAU_SSP3";
input bool   InpAllowOnlyXAU          = true;
input bool   InpDrawObjects           = true;
input bool   InpShowDashboard         = true;
input bool   InpPushAlerts            = false;
input string InpLogFileName           = "XAU_SSP3_log.txt";

// --- Risk & Daily Limits ---
input double InpRiskPercent           = 0.5;   // % balance risked per trade
input double InpDailyProfitTargetPct  = 1.5;   // stop trading once daily PnL >= +X%
input double InpMaxDailyLossPercent   = 2.0;   // stop & flat if daily PnL <= -X%
input int    InpMaxConsecutiveLosses  = 3;     // circuit breaker
input int    InpMaxOpenTrades         = 1;
input int    InpMaxTradesPerDay       = 8;     // hard cap

// --- Range Detection ---
input int    InpRangeLookback         = 50;    // M5 bars to scan for range
input int    InpMinTouchesPerSide     = 2;
input double InpTouchTolerancePoints  = 250;   // 2.50 USD on 2-digit gold
input double InpAtrMaxRatio           = 0.35;  // ATR/RangeWidth must be <= this
input int    InpBreakoutCooldownBars  = 20;    // pause N bars after breakout
input bool   InpUseHtfFilter          = true;  // M15 HTF range confirmation
input ENUM_TIMEFRAMES InpHtfPeriod    = PERIOD_M15;

// --- Indicators ---
input int    InpAtrPeriod             = 14;
input int    InpAdxPeriod             = 14;
input double InpAdxMax                = 25.0;  // sideways = ADX <= 25
input int    InpRsiPeriod             = 14;
input double InpRsiBuyMax             = 35.0;
input double InpRsiSellMin            = 65.0;
input int    InpStochKPeriod          = 14;
input int    InpStochDPeriod          = 3;
input int    InpStochSlowing          = 3;
input double InpStochOversold         = 25.0;
input double InpStochOverbought       = 75.0;
input int    InpBbPeriod              = 20;
input double InpBbDeviation           = 2.0;
input bool   InpRequireBbTag          = true;

// --- SL / TP / Exits ---
input double InpSlAtrMultiplier       = 1.2;   // tight SL beyond range edge
input double InpTpRRMultiplier        = 1.5;   // base RR
input bool   InpTpAtRangeMid          = true;  // TP capped at range midpoint
input bool   InpUsePartialClose       = true;
input double InpPartialClosePct       = 50.0;
input bool   InpUseBreakEven          = true;
input double InpBreakEvenLockPts      = 30;    // 0.30 USD locked after partial
input bool   InpUseTrailing           = true;
input double InpTrailAtrMultiplier    = 1.0;
input int    InpMaxBarsInTrade        = 24;    // close after N M5 bars (~2h)

// --- Filters ---
input int    InpSpreadLimitPoints     = 50;    // 0.50 USD on 2-digit gold
input int    InpSlippagePoints        = 20;
input bool   InpUseSessionFilter      = true;
input int    InpSessionStartHour      = 7;     // server time
input int    InpSessionEndHour        = 19;
input bool   InpAvoidLondonOpen       = true;
input bool   InpAvoidNYOpen           = true;
input int    InpLondonOpenHour        = 10;
input int    InpNyOpenHour            = 15;
input int    InpAvoidMinutesAround    = 20;
input bool   InpAvoidFridayLate       = true;
input int    InpFridayCutoffHour      = 18;

//============================== TYPES ===============================

enum ENUM_SIGNAL { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = 2 };

struct SRange
{
   bool     valid;
   double   support;
   double   resistance;
   double   mid;
   double   width;
   int      supportTouches;
   int      resistanceTouches;
   double   atr;
   double   adx;
   double   bbWidth;
   string   reason;
};

struct STradeMeta
{
   ulong    ticket;
   datetime openTime;
   double   openPrice;
   double   initialSL;
   bool     partialDone;
   long     type;
};

//============================== GLOBALS =============================

CTrade         g_trade;
CPositionInfo  g_pos;

int            g_atrHandle      = INVALID_HANDLE;
int            g_adxHandle      = INVALID_HANDLE;
int            g_rsiHandle      = INVALID_HANDLE;
int            g_stochHandle    = INVALID_HANDLE;
int            g_bbHandle       = INVALID_HANDLE;
int            g_atrHtfHandle   = INVALID_HANDLE;
int            g_adxHtfHandle   = INVALID_HANDLE;

SRange         g_range;
datetime       g_lastBarTime    = 0;
int            g_breakoutCooldown = 0;

double         g_dayStartEquity = 0;
datetime       g_dayStartTime   = 0;
int            g_dayTradesOpened = 0;
int            g_dayConsecutiveLosses = 0;
bool           g_dayStopFlag    = false;
ulong          g_lastClosedDealId = 0;

int            g_totalTrades  = 0;
int            g_wins         = 0;
int            g_losses       = 0;
ulong          g_lastDealIdSeen = 0;

int            g_logHandle = INVALID_HANDLE;
string         g_lastReason = "init";

STradeMeta     g_meta;

//============================== LOG =================================

void WriteLog(const string msg)
{
   Print("[XAU SSP3] ", msg);
   if(g_logHandle == INVALID_HANDLE) return;
   string line = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " | " + msg + "\n";
   FileWriteString(g_logHandle, line);
   FileFlush(g_logHandle);
}

//============================== TIME ================================

datetime StartOfDay(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

void RollDayIfNeeded()
{
   datetime today = StartOfDay(TimeCurrent());
   if(today != g_dayStartTime)
   {
      g_dayStartTime         = today;
      g_dayStartEquity       = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dayTradesOpened      = 0;
      g_dayConsecutiveLosses = 0;
      g_dayStopFlag          = false;
      WriteLog("--- New day. StartEquity=" + DoubleToString(g_dayStartEquity, 2) + " ---");
   }
}

//============================== RISK ================================

double DayPnL()
{
   return AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity;
}

double DayPnLPercent()
{
   if(g_dayStartEquity <= 0) return 0.0;
   return (DayPnL() / g_dayStartEquity) * 100.0;
}

bool DailyProfitTargetHit()
{
   if(InpDailyProfitTargetPct <= 0) return false;
   return DayPnLPercent() >= InpDailyProfitTargetPct;
}

bool DailyLossHit()
{
   if(InpMaxDailyLossPercent <= 0) return false;
   return DayPnLPercent() <= -InpMaxDailyLossPercent;
}

double NormalizeLot(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   lots = MathFloor(lots / stepLot) * stepLot;
   return NormalizeDouble(lots, 2);
}

double CalcLotByRisk(const double slDistancePrice)
{
   if(slDistancePrice <= 0) return 0.0;
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0) return 0.0;
   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0.0;
   return NormalizeLot(riskMoney / lossPerLot);
}

//============================== FILTERS =============================

int CurrentSpreadPoints()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
}

bool IsAroundHour(int curH, int curM, int targetH, int avoidM)
{
   int curMinutes    = curH * 60 + curM;
   int targetMinutes = targetH * 60;
   int diff          = (int)MathAbs(curMinutes - targetMinutes);
   int wrap          = 24 * 60 - diff;
   if(wrap < diff) diff = wrap;
   return diff <= avoidM;
}

bool FiltersOK(string &reason)
{
   int sp = CurrentSpreadPoints();
   if(sp > InpSpreadLimitPoints)
   {
      reason = "Spread " + IntegerToString(sp) + " > " + IntegerToString(InpSpreadLimitPoints);
      return false;
   }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   int m = dt.min;
   int dow = dt.day_of_week;

   if(InpAvoidFridayLate && dow == 5 && h >= InpFridayCutoffHour)
   {
      reason = "Friday late";
      return false;
   }

   if(InpUseSessionFilter)
   {
      if(InpSessionStartHour <= InpSessionEndHour)
      {
         if(h < InpSessionStartHour || h >= InpSessionEndHour)
         {
            reason = "Out of session";
            return false;
         }
      }
      else
      {
         if(h < InpSessionStartHour && h >= InpSessionEndHour)
         {
            reason = "Out of session";
            return false;
         }
      }
   }

   if(InpAvoidLondonOpen && IsAroundHour(h, m, InpLondonOpenHour, InpAvoidMinutesAround))
   {
      reason = "London open blackout";
      return false;
   }
   if(InpAvoidNYOpen && IsAroundHour(h, m, InpNyOpenHour, InpAvoidMinutesAround))
   {
      reason = "NY open blackout";
      return false;
   }
   return true;
}

//============================== RANGE DETECTION =====================

bool RangeUpdate()
{
   ZeroMemory(g_range);
   g_range.reason = "";

   if(Bars(_Symbol, _Period) < InpRangeLookback + 5)
   {
      g_range.reason = "not enough bars";
      return false;
   }

   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);
   if(CopyHigh(_Symbol, _Period, 1, InpRangeLookback, highs)   <= 0) return false;
   if(CopyLow(_Symbol, _Period, 1, InpRangeLookback, lows)     <= 0) return false;
   if(CopyClose(_Symbol, _Period, 1, InpRangeLookback, closes) <= 0) return false;

   int idxR = ArrayMaximum(highs, 0, InpRangeLookback);
   int idxS = ArrayMinimum(lows,  0, InpRangeLookback);
   if(idxR < 0 || idxS < 0) return false;

   double resistance = highs[idxR];
   double support    = lows[idxS];
   double width      = resistance - support;
   if(width <= 0) { g_range.reason = "no width"; return false; }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpTouchTolerancePoints * point;

   int sTouch = 0, rTouch = 0;
   for(int i = 0; i < InpRangeLookback; i++)
   {
      if(highs[i] >= resistance - tol && closes[i] < resistance - tol * 0.5) rTouch++;
      if(lows[i]  <= support + tol    && closes[i] > support + tol * 0.5)    sTouch++;
   }

   double atrBuf[];
   double adxBuf[];
   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0) return false;
   if(CopyBuffer(g_adxHandle, 0, 1, 1, adxBuf) <= 0) return false;
   double atr = atrBuf[0];
   double adx = adxBuf[0];

   double bbU[], bbL[];
   ArraySetAsSeries(bbU, true);
   ArraySetAsSeries(bbL, true);
   double bbWidth = 0;
   if(CopyBuffer(g_bbHandle, 1, 1, 1, bbU) > 0 &&
      CopyBuffer(g_bbHandle, 2, 1, 1, bbL) > 0)
      bbWidth = bbU[0] - bbL[0];

   g_range.support           = support;
   g_range.resistance        = resistance;
   g_range.mid               = (support + resistance) / 2.0;
   g_range.width             = width;
   g_range.supportTouches    = sTouch;
   g_range.resistanceTouches = rTouch;
   g_range.atr               = atr;
   g_range.adx               = adx;
   g_range.bbWidth           = bbWidth;

   if(sTouch < InpMinTouchesPerSide || rTouch < InpMinTouchesPerSide)
   {
      g_range.valid = false;
      g_range.reason = "touches";
      return true;
   }

   if(atr <= 0 || (atr / width) > InpAtrMaxRatio)
   {
      g_range.valid = false;
      g_range.reason = "ATR/W too high";
      return true;
   }

   if(adx > InpAdxMax)
   {
      g_range.valid = false;
      g_range.reason = "ADX trending";
      return true;
   }

   if(InpUseHtfFilter)
   {
      double htfAdxBuf[], htfAtrBuf[];
      ArraySetAsSeries(htfAdxBuf, true);
      ArraySetAsSeries(htfAtrBuf, true);
      if(CopyBuffer(g_adxHtfHandle, 0, 1, 1, htfAdxBuf) <= 0 ||
         CopyBuffer(g_atrHtfHandle, 0, 1, 1, htfAtrBuf) <= 0)
      {
         g_range.valid = false;
         g_range.reason = "HTF data n/a";
         return true;
      }
      if(htfAdxBuf[0] > InpAdxMax + 5)
      {
         g_range.valid = false;
         g_range.reason = "HTF ADX trending";
         return true;
      }
      if(htfAtrBuf[0] > width * 0.6)
      {
         g_range.valid = false;
         g_range.reason = "HTF ATR too big";
         return true;
      }
   }

   g_range.valid = true;
   g_range.reason = "OK";
   return true;
}

bool IsStrongBreakout()
{
   if(g_range.width <= 0 || g_range.atr <= 0) return false;

   double o[], c[];
   ArraySetAsSeries(o, true);
   ArraySetAsSeries(c, true);
   if(CopyOpen(_Symbol, _Period, 1, 2, o) <= 0) return false;
   if(CopyClose(_Symbol, _Period, 1, 2, c) <= 0) return false;

   double body0 = MathAbs(c[0] - o[0]);
   bool bigCandle = body0 > 1.2 * g_range.atr;

   bool brokeUp   = (c[0] > g_range.resistance) && bigCandle;
   bool brokeDown = (c[0] < g_range.support)    && bigCandle;
   return brokeUp || brokeDown;
}

bool NearSupport(const double price)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpTouchTolerancePoints * point;
   return (price <= g_range.support + tol);
}

bool NearResistance(const double price)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpTouchTolerancePoints * point;
   return (price >= g_range.resistance - tol);
}

//============================== PATTERNS ============================

bool IsBullishEngulfing(double o1, double c1, double o0, double c0)
{
   if(!(c1 < o1 && c0 > o0)) return false;
   if(c0 < o1) return false;
   if(o0 > c1) return false;
   double body0 = c0 - o0;
   double body1 = o1 - c1;
   return (body0 >= body1 * 0.9);
}

bool IsBearishEngulfing(double o1, double c1, double o0, double c0)
{
   if(!(c1 > o1 && c0 < o0)) return false;
   if(c0 > o1) return false;
   if(o0 < c1) return false;
   double body0 = o0 - c0;
   double body1 = c1 - o1;
   return (body0 >= body1 * 0.9);
}

bool IsBullishPin(double op, double hi, double lo, double cl)
{
   double rng = hi - lo;
   if(rng <= 0) return false;
   double body  = MathAbs(cl - op);
   double lower = MathMin(op, cl) - lo;
   double upper = hi - MathMax(op, cl);
   if(body <= 0) return false;
   return (lower >= 1.8 * body) && (upper <= 0.6 * body) && (cl > op);
}

bool IsShootingStar(double op, double hi, double lo, double cl)
{
   double rng = hi - lo;
   if(rng <= 0) return false;
   double body  = MathAbs(cl - op);
   double upper = hi - MathMax(op, cl);
   double lower = MathMin(op, cl) - lo;
   if(body <= 0) return false;
   return (upper >= 1.8 * body) && (lower <= 0.6 * body) && (cl < op);
}

//============================== SIGNAL ENGINE =======================

ENUM_SIGNAL EvaluateSignal(double &outRsi, double &outStoch, string &outReason)
{
   outRsi = 0.0;
   outStoch = 0.0;
   outReason = "";

   if(!g_range.valid) { outReason = "range invalid"; return SIG_NONE; }

   double o[], h[], l[], c[];
   ArraySetAsSeries(o, true);
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   if(CopyOpen(_Symbol, _Period, 1, 2, o)  <= 0) return SIG_NONE;
   if(CopyHigh(_Symbol, _Period, 1, 2, h)  <= 0) return SIG_NONE;
   if(CopyLow(_Symbol, _Period, 1, 2, l)   <= 0) return SIG_NONE;
   if(CopyClose(_Symbol, _Period, 1, 2, c) <= 0) return SIG_NONE;

   double rsiBuf[], stochK[], bbU[], bbL[];
   ArraySetAsSeries(rsiBuf, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(bbU, true);
   ArraySetAsSeries(bbL, true);

   if(CopyBuffer(g_rsiHandle,   0, 1, 2, rsiBuf) <= 0) return SIG_NONE;
   if(CopyBuffer(g_stochHandle, 0, 1, 2, stochK) <= 0) return SIG_NONE;
   if(CopyBuffer(g_bbHandle,    1, 1, 1, bbU)    <= 0) return SIG_NONE;
   if(CopyBuffer(g_bbHandle,    2, 1, 1, bbL)    <= 0) return SIG_NONE;

   double rsiNow  = rsiBuf[0];
   double rsiPrev = rsiBuf[1];
   double stNow   = stochK[0];
   double stPrev  = stochK[1];
   outRsi   = rsiNow;
   outStoch = stNow;

   bool nearSup = NearSupport(l[0]);
   bool nearRes = NearResistance(h[0]);
   if(!nearSup && !nearRes) { outReason = "not at S/R"; return SIG_NONE; }

   if(nearSup)
   {
      bool pat = IsBullishEngulfing(o[1], c[1], o[0], c[0]) ||
                 IsBullishPin(o[0], h[0], l[0], c[0]);
      if(!pat)                       { outReason = "no bull pattern";       return SIG_NONE; }
      if(rsiNow > InpRsiBuyMax)      { outReason = "rsi too high";          return SIG_NONE; }
      if(rsiNow < rsiPrev)           { outReason = "rsi not turning up";    return SIG_NONE; }
      if(stNow > InpStochOversold)   { outReason = "stoch too high";        return SIG_NONE; }
      if(stNow < stPrev)             { outReason = "stoch not turning up";  return SIG_NONE; }
      if(InpRequireBbTag && l[0] > bbL[0]) { outReason = "no BB lower tag"; return SIG_NONE; }
      return SIG_BUY;
   }

   if(nearRes)
   {
      bool pat = IsBearishEngulfing(o[1], c[1], o[0], c[0]) ||
                 IsShootingStar(o[0], h[0], l[0], c[0]);
      if(!pat)                          { outReason = "no bear pattern";       return SIG_NONE; }
      if(rsiNow < InpRsiSellMin)        { outReason = "rsi too low";           return SIG_NONE; }
      if(rsiNow > rsiPrev)              { outReason = "rsi not turning down";  return SIG_NONE; }
      if(stNow < InpStochOverbought)    { outReason = "stoch too low";         return SIG_NONE; }
      if(stNow > stPrev)                { outReason = "stoch not turning down";return SIG_NONE; }
      if(InpRequireBbTag && h[0] < bbU[0]) { outReason = "no BB upper tag";    return SIG_NONE; }
      return SIG_SELL;
   }
   return SIG_NONE;
}

//============================== TRADE MGMT ==========================

int CountOpenPositions()
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      cnt++;
   }
   return cnt;
}

void DrawEntryArrow(const ENUM_ORDER_TYPE type, const double price)
{
   if(!InpDrawObjects) return;
   string arrowName = "XSSP3_ARR_" + IntegerToString((int)TimeCurrent());
   if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), price))
   {
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, (type == ORDER_TYPE_BUY) ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, (type == ORDER_TYPE_BUY) ? clrLime : clrRed);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
   }
}

bool OpenTrade(const ENUM_ORDER_TYPE type, const double lots,
               const double sl, const double tp, const string comment)
{
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool ok;
   if(type == ORDER_TYPE_BUY)
      ok = g_trade.Buy(lots, _Symbol, price, sl, tp, comment);
   else
      ok = g_trade.Sell(lots, _Symbol, price, sl, tp, comment);

   if(ok)
   {
      WriteLog("OPEN " + ((type == ORDER_TYPE_BUY) ? "BUY" : "SELL") +
               " lots=" + DoubleToString(lots, 2) +
               " price=" + DoubleToString(price, _Digits) +
               " SL=" + DoubleToString(sl, _Digits) +
               " TP=" + DoubleToString(tp, _Digits));
      if(InpPushAlerts)
         SendNotification("[XAU SSP3] " + ((type == ORDER_TYPE_BUY) ? "BUY" : "SELL") +
                          " @ " + DoubleToString(price, _Digits));
      DrawEntryArrow(type, price);

      g_meta.ticket      = g_trade.ResultDeal();
      g_meta.openTime    = TimeCurrent();
      g_meta.openPrice   = price;
      g_meta.initialSL   = sl;
      g_meta.partialDone = false;
      g_meta.type        = (type == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

      g_dayTradesOpened++;
   }
   else
   {
      WriteLog("OPEN FAIL err=" + IntegerToString(g_trade.ResultRetcode()) + " " +
               g_trade.ResultRetcodeDescription());
   }
   return ok;
}

void CloseAllOurPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!g_pos.SelectByTicket(ticket)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if((ulong)g_pos.Magic() != InpMagic) continue;
      if(g_trade.PositionClose(ticket))
         WriteLog("CLOSE ticket=" + IntegerToString((int)ticket) + " (" + reason + ")");
   }
}

void ManageOpenPositions()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return;

   double atr = g_range.atr;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!g_pos.SelectByTicket(ticket)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if((ulong)g_pos.Magic() != InpMagic) continue;

      double openPrice = g_pos.PriceOpen();
      double sl        = g_pos.StopLoss();
      double tp        = g_pos.TakeProfit();
      long   ptype     = g_pos.PositionType();
      double volume    = g_pos.Volume();
      datetime tOpen   = (datetime)g_pos.Time();

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double curPrice = (ptype == POSITION_TYPE_BUY) ? bid : ask;

      double initSL = (g_meta.initialSL > 0 && g_pos.Ticket() == g_meta.ticket)
                      ? g_meta.initialSL : sl;
      double oneR = (ptype == POSITION_TYPE_BUY)
                     ? (openPrice - initSL)
                     : (initSL - openPrice);
      if(oneR <= 0) oneR = (atr > 0 ? atr : point * 100);

      double profitPrice = (ptype == POSITION_TYPE_BUY)
                           ? (curPrice - openPrice)
                           : (openPrice - curPrice);

      // ---- Time-based exit ----
      if(InpMaxBarsInTrade > 0)
      {
         long secsPerBar = PeriodSeconds(_Period);
         long elapsed = (long)(TimeCurrent() - tOpen);
         if(secsPerBar > 0 && elapsed >= secsPerBar * InpMaxBarsInTrade)
         {
            if(g_trade.PositionClose(ticket))
               WriteLog("TIME EXIT ticket=" + IntegerToString((int)ticket));
            continue;
         }
      }

      // ---- Partial close at +1R ----
      bool partialDone = (g_pos.Ticket() == g_meta.ticket) ? g_meta.partialDone : true;
      if(InpUsePartialClose && !partialDone && profitPrice >= oneR)
      {
         double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         if(stepLot <= 0) stepLot = 0.01;
         double closeLot = volume * (InpPartialClosePct / 100.0);
         closeLot = MathFloor(closeLot / stepLot) * stepLot;
         closeLot = NormalizeDouble(closeLot, 2);
         if(closeLot >= minLot && closeLot < volume)
         {
            if(g_trade.PositionClosePartial(ticket, closeLot))
            {
               WriteLog("PARTIAL CLOSE " + DoubleToString(closeLot, 2) + " lots @ +1R");
               if(g_pos.Ticket() == g_meta.ticket) g_meta.partialDone = true;

               if(InpUseBreakEven)
               {
                  double beSL = (ptype == POSITION_TYPE_BUY)
                                ? openPrice + InpBreakEvenLockPts * point
                                : openPrice - InpBreakEvenLockPts * point;
                  beSL = NormalizeDouble(beSL, _Digits);
                  if(g_trade.PositionModify(ticket, beSL, tp))
                     WriteLog("BE SL set " + DoubleToString(beSL, _Digits));
               }
               continue;
            }
         }
      }

      // ---- ATR trailing stop ----
      bool canTrail = InpUseTrailing && atr > 0 &&
                      (partialDone || (!InpUsePartialClose && profitPrice >= oneR));
      if(canTrail)
      {
         double trailDist = InpTrailAtrMultiplier * atr;
         double newSL = (ptype == POSITION_TYPE_BUY)
                        ? curPrice - trailDist
                        : curPrice + trailDist;
         newSL = NormalizeDouble(newSL, _Digits);
         bool improve;
         if(ptype == POSITION_TYPE_BUY)
            improve = (newSL > sl + point);
         else
            improve = (newSL < sl - point) || (sl == 0);
         if(improve)
         {
            if(g_trade.PositionModify(ticket, newSL, tp))
               WriteLog("TRAIL SL=" + DoubleToString(newSL, _Digits));
         }
      }
   }
}

//============================== STATS ===============================

void UpdateClosedTradeStats()
{
   datetime from = TimeCurrent() - 60 * 60 * 24 * 30;
   if(!HistorySelect(from, TimeCurrent())) return;
   int total = HistoryDealsTotal();
   int trades = 0, wins = 0, losses = 0;
   ulong newest = g_lastDealIdSeen;

   for(int i = 0; i < total; i++)
   {
      ulong dealId = HistoryDealGetTicket(i);
      if(dealId == 0) continue;
      if((ulong)HistoryDealGetInteger(dealId, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(dealId, DEAL_SYMBOL) != _Symbol) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealId, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double profit = HistoryDealGetDouble(dealId, DEAL_PROFIT)
                    + HistoryDealGetDouble(dealId, DEAL_SWAP)
                    + HistoryDealGetDouble(dealId, DEAL_COMMISSION);
      trades++;
      if(profit >= 0) wins++; else losses++;

      datetime dealTime = (datetime)HistoryDealGetInteger(dealId, DEAL_TIME);
      if(dealId > g_lastClosedDealId && dealTime >= g_dayStartTime)
      {
         if(profit < 0) g_dayConsecutiveLosses++;
         else           g_dayConsecutiveLosses = 0;
         g_lastClosedDealId = dealId;
      }

      if(dealId > newest) newest = dealId;
   }
   g_totalTrades   = trades;
   g_wins          = wins;
   g_losses        = losses;
   g_lastDealIdSeen = newest;
}

//============================== DASHBOARD ===========================

void DrawLabel(int line, const string title, const string value, color clr)
{
   string name = "XSSP3_DASH_L" + IntegerToString(line);
   string text = title + " : " + value;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20 + line * 16);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
      ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString (0, name, OBJPROP_TEXT,  text);
}

void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   int line = 0;
   DrawLabel(line++, "XAU SSP3", "v3.0  " + _Symbol, clrGold);

   string rangeStr;
   if(g_range.valid)
      rangeStr = "S=" + DoubleToString(g_range.support, 2) +
                 " R=" + DoubleToString(g_range.resistance, 2) +
                 " W=" + DoubleToString(g_range.width, 2);
   else
      rangeStr = "INVALID (" + g_range.reason + ")";
   DrawLabel(line++, "Range", rangeStr, g_range.valid ? clrLime : clrOrangeRed);

   DrawLabel(line++, "Indic",
             "S=" + IntegerToString(g_range.supportTouches) +
             " R=" + IntegerToString(g_range.resistanceTouches) +
             " ATR=" + DoubleToString(g_range.atr, 2) +
             " ADX=" + DoubleToString(g_range.adx, 1),
             clrWhite);

   double wr = (g_totalTrades > 0) ? (100.0 * g_wins / g_totalTrades) : 0.0;
   DrawLabel(line++, "Trades30d",
             IntegerToString(g_totalTrades) + " (W:" + IntegerToString(g_wins) +
             " L:" + IntegerToString(g_losses) + ") " + DoubleToString(wr, 1) + "%",
             clrWhite);

   DrawLabel(line++, "Today",
             "PnL=" + DoubleToString(DayPnL(), 2) +
             " (" + DoubleToString(DayPnLPercent(), 2) + "%) " +
             "trades=" + IntegerToString(g_dayTradesOpened) +
             " consecL=" + IntegerToString(g_dayConsecutiveLosses),
             (DayPnL() >= 0) ? clrLime : clrRed);

   DrawLabel(line++, "Limits",
             "Tgt=+" + DoubleToString(InpDailyProfitTargetPct, 1) + "% " +
             "MaxLoss=-" + DoubleToString(InpMaxDailyLossPercent, 1) + "% " +
             "MaxL=" + IntegerToString(InpMaxConsecutiveLosses),
             clrSilver);
   DrawLabel(line++, "Spread", IntegerToString(CurrentSpreadPoints()) + " pts", clrWhite);
   DrawLabel(line++, "Status", g_lastReason, g_dayStopFlag ? clrRed : clrOrange);
}

//============================== ONINIT / ONTICK =====================

int OnInit()
{
   if(InpAllowOnlyXAU)
   {
      string sym = _Symbol;
      string symU = sym;
      StringToUpper(symU);
      if(StringFind(symU, "XAU") < 0 && StringFind(symU, "GOLD") < 0)
      {
         Print("This EA is intended for XAUUSD/GOLD. Current: ", _Symbol);
         return INIT_FAILED;
      }
   }
   if(_Period != PERIOD_M5)
      Print("WARNING: EA tuned for M5. Current TF: ", EnumToString(_Period));

   g_atrHandle    = iATR(_Symbol, _Period, InpAtrPeriod);
   g_adxHandle    = iADX(_Symbol, _Period, InpAdxPeriod);
   g_rsiHandle    = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   g_stochHandle  = iStochastic(_Symbol, _Period,
                                InpStochKPeriod, InpStochDPeriod, InpStochSlowing,
                                MODE_SMA, STO_LOWHIGH);
   g_bbHandle     = iBands(_Symbol, _Period, InpBbPeriod, 0, InpBbDeviation, PRICE_CLOSE);

   if(InpUseHtfFilter)
   {
      g_atrHtfHandle = iATR(_Symbol, InpHtfPeriod, InpAtrPeriod);
      g_adxHtfHandle = iADX(_Symbol, InpHtfPeriod, InpAdxPeriod);
      if(g_atrHtfHandle == INVALID_HANDLE || g_adxHtfHandle == INVALID_HANDLE)
      {
         Print("HTF indicator handles failed");
         return INIT_FAILED;
      }
   }

   if(g_atrHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE ||
      g_bbHandle == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);

   g_logHandle = FileOpen(InpLogFileName, FILE_WRITE|FILE_READ|FILE_TXT);
   if(g_logHandle != INVALID_HANDLE)
   {
      FileSeek(g_logHandle, 0, SEEK_END);
      WriteLog("=== EA Started v3.0 ===");
   }

   g_dayStartEquity       = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartTime         = StartOfDay(TimeCurrent());
   g_dayTradesOpened      = 0;
   g_dayConsecutiveLosses = 0;
   g_dayStopFlag          = false;

   ZeroMemory(g_range);
   ZeroMemory(g_meta);
   g_lastBarTime      = 0;
   g_breakoutCooldown = 0;
   g_totalTrades = 0;
   g_wins = 0;
   g_losses = 0;

   Print("XAU Sideways Scalper Pro v3.0 initialised on ", _Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle    != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle    != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_rsiHandle    != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_stochHandle  != INVALID_HANDLE) IndicatorRelease(g_stochHandle);
   if(g_bbHandle     != INVALID_HANDLE) IndicatorRelease(g_bbHandle);
   if(g_atrHtfHandle != INVALID_HANDLE) IndicatorRelease(g_atrHtfHandle);
   if(g_adxHtfHandle != INVALID_HANDLE) IndicatorRelease(g_adxHtfHandle);
   if(g_logHandle    != INVALID_HANDLE)
   {
      WriteLog("=== EA Stopped ===");
      FileClose(g_logHandle);
   }
   ObjectsDeleteAll(0, "XSSP3_DASH_");
}

void OnTick()
{
   RollDayIfNeeded();
   ManageOpenPositions();

   if(!g_dayStopFlag && DailyProfitTargetHit())
   {
      CloseAllOurPositions("Daily profit target reached");
      g_dayStopFlag = true;
      g_lastReason  = "DAY DONE: target hit";
      WriteLog(g_lastReason);
   }

   if(!g_dayStopFlag && DailyLossHit())
   {
      CloseAllOurPositions("Daily loss limit");
      g_dayStopFlag = true;
      g_lastReason  = "DAY STOP: loss hit";
      WriteLog(g_lastReason);
   }

   if(!g_dayStopFlag && InpMaxConsecutiveLosses > 0 &&
      g_dayConsecutiveLosses >= InpMaxConsecutiveLosses)
   {
      CloseAllOurPositions("Circuit breaker");
      g_dayStopFlag = true;
      g_lastReason  = "DAY STOP: consec losses";
      WriteLog(g_lastReason);
   }

   if(g_dayStopFlag)
   {
      UpdateDashboard();
      return;
   }

   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime)
   {
      static datetime lastDashUpdate = 0;
      if(TimeCurrent() - lastDashUpdate >= 2)
      {
         UpdateDashboard();
         lastDashUpdate = TimeCurrent();
      }
      return;
   }
   g_lastBarTime = curBarTime;

   RangeUpdate();

   if(IsStrongBreakout())
   {
      g_breakoutCooldown = InpBreakoutCooldownBars;
      WriteLog("Strong breakout -> cooldown");
   }
   if(g_breakoutCooldown > 0) g_breakoutCooldown--;

   UpdateClosedTradeStats();

   string filterReason = "";
   bool filtersOk = FiltersOK(filterReason);

   if(CountOpenPositions() >= InpMaxOpenTrades)
   {
      g_lastReason = "max trades open";
      UpdateDashboard();
      return;
   }
   if(g_dayTradesOpened >= InpMaxTradesPerDay)
   {
      g_lastReason = "daily trade cap";
      UpdateDashboard();
      return;
   }
   if(g_breakoutCooldown > 0)
   {
      g_lastReason = "breakout cooldown " + IntegerToString(g_breakoutCooldown);
      UpdateDashboard();
      return;
   }
   if(!filtersOk)
   {
      g_lastReason = filterReason;
      UpdateDashboard();
      return;
   }

   double rsi = 0.0, stoch = 0.0;
   string sigReason = "";
   ENUM_SIGNAL sig = EvaluateSignal(rsi, stoch, sigReason);
   if(sig == SIG_NONE)
   {
      g_lastReason = sigReason;
      UpdateDashboard();
      return;
   }

   double atr = (g_range.atr > 0) ? g_range.atr : 0.0;
   if(atr <= 0)
   {
      g_lastReason = "atr=0";
      UpdateDashboard();
      return;
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = 0, tp = 0, entry = 0;

   if(sig == SIG_BUY)
   {
      entry = ask;
      sl    = g_range.support - InpSlAtrMultiplier * atr;
      double slDist = entry - sl;
      tp    = entry + InpTpRRMultiplier * slDist;
      if(InpTpAtRangeMid && g_range.mid > entry)
      {
         double midTp = g_range.mid - 5 * point;
         if(midTp < tp) tp = midTp;
      }
      double resCap = g_range.resistance - 5 * point;
      if(resCap < tp) tp = resCap;
   }
   else
   {
      entry = bid;
      sl    = g_range.resistance + InpSlAtrMultiplier * atr;
      double slDist = sl - entry;
      tp    = entry - InpTpRRMultiplier * slDist;
      if(InpTpAtRangeMid && g_range.mid < entry)
      {
         double midTp = g_range.mid + 5 * point;
         if(midTp > tp) tp = midTp;
      }
      double supCap = g_range.support + 5 * point;
      if(supCap > tp) tp = supCap;
   }

   double slDistPrice = MathAbs(entry - sl);
   double tpDistPrice = MathAbs(tp - entry);
   if(slDistPrice <= 0 || tpDistPrice < slDistPrice * 0.6)
   {
      g_lastReason = "RR too small";
      UpdateDashboard();
      return;
   }

   double lots = CalcLotByRisk(slDistPrice);
   if(lots <= 0)
   {
      g_lastReason = "lots=0";
      UpdateDashboard();
      return;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   string cmt = InpTradeComment + ((sig == SIG_BUY) ? "_B" : "_S");

   ENUM_ORDER_TYPE otype = (sig == SIG_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   OpenTrade(otype, lots, sl, tp, cmt);

   g_lastReason = (sig == SIG_BUY) ? "BUY signal" : "SELL signal";
   UpdateDashboard();
}

void OnTrade()
{
   // optional: keep for future use
}
//+------------------------------------------------------------------+
