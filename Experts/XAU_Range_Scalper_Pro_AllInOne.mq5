//+------------------------------------------------------------------+
//|                              XAU_Range_Scalper_Pro_AllInOne.mq5  |
//|                                          Copyright 2026, Antu AI |
//|                                                                  |
//|  ALL-IN-ONE single-file version of XAU Range Scalper Pro v1.1    |
//|  No external include files needed. Just copy this single file    |
//|  to MQL5\Experts\ and compile with F7.                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antu AI"
#property version   "1.10"
#property strict
#property description "XAU Range Scalper Pro v1.1 (All-in-One) - XAUUSD M5 range strategy"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//============================== INPUTS ==============================

input group "=== General ==="
input ulong  InpMagic                = 20260525;
input string InpTradeComment          = "XAU_RSP";
input bool   InpAllowTradingOnlyXAU   = true;
input bool   InpDrawObjects           = true;
input bool   InpShowDashboard         = true;
input bool   InpPushAlerts            = false;
input string InpLogFileName           = "XAU_RSP_log.txt";

input group "=== Risk Management ==="
input double InpRiskPercent           = 0.5;
input double InpMaxDailyLossPercent   = 2.5;
input int    InpMaxOpenTrades         = 1;

input group "=== Range Detection ==="
input int    InpRangeLookback         = 60;
input int    InpMinTouchesPerSide     = 3;
input int    InpMinTouchSpacing       = 5;
input double InpTouchTolerancePoints  = 200;
input double InpAtrMaxRatio           = 0.28;
input int    InpBreakoutCooldownBars  = 30;
input bool   InpUseHtfFilter          = true;
input ENUM_TIMEFRAMES InpHtfPeriod    = PERIOD_M15;

input group "=== Indicators ==="
input int    InpAtrPeriod             = 14;
input int    InpAdxPeriod             = 14;
input double InpAdxMax                = 22.0;
input int    InpRsiPeriod             = 14;
input double InpRsiBuyMax             = 32.0;
input double InpRsiSellMin            = 68.0;
input bool   InpUseBollinger          = false;
input int    InpBbPeriod              = 20;
input double InpBbDeviation           = 2.0;
input bool   InpUseTrendFilter        = true;
input int    InpEmaPeriod             = 200;
input double InpEmaMaxDistAtr         = 4.0;

input group "=== SL / TP ==="
input double InpSlAtrMultiplier       = 1.3;
input double InpTpRRMultiplier        = 1.6;
input bool   InpTpAtRangeOpposite     = true;

input group "=== Trade Management ==="
input bool   InpUseBreakEven          = true;
input double InpBreakEvenTriggerPts   = 600;
input double InpBreakEvenLockPts      = 50;
input bool   InpUseTrailing           = true;
input double InpTrailStartPoints      = 1000;
input double InpTrailStepPoints       = 500;

input group "=== Filters ==="
input int    InpSpreadLimitPoints     = 35;
input int    InpSlippagePoints        = 20;
input bool   InpUseSessionFilter      = true;
input int    InpSessionStartHour      = 8;
input int    InpSessionEndHour        = 19;
input bool   InpAvoidLondonOpen       = true;
input bool   InpAvoidNYOpen           = true;
input int    InpLondonOpenHour        = 10;
input int    InpNyOpenHour            = 15;
input int    InpAvoidMinutesAround    = 20;

//============================== TYPES ===============================

enum ENUM_SIGNAL { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = 2 };

struct SRange
{
   bool     valid;
   double   support;
   double   resistance;
   double   width;
   int      supportTouches;
   int      resistanceTouches;
   double   atr;
   double   adx;
   datetime computedAt;
   string   reason;
};

//============================== GLOBALS =============================

CTrade         g_trade;
CPositionInfo  g_pos;

int            g_atrHandle    = INVALID_HANDLE;
int            g_adxHandle    = INVALID_HANDLE;
int            g_atrHtfHandle = INVALID_HANDLE;
int            g_rsiHandle    = INVALID_HANDLE;
int            g_bbHandle     = INVALID_HANDLE;
int            g_emaHandle    = INVALID_HANDLE;

SRange         g_range;
datetime       g_lastBarTime  = 0;
int            g_breakoutCooldown = 0;

double         g_dayStartEquity = 0;
datetime       g_dayStartTime   = 0;

int            g_totalTrades  = 0;
int            g_wins         = 0;
int            g_losses       = 0;
ulong          g_lastDealId   = 0;

int            g_logHandle = INVALID_HANDLE;

//============================== LOGGING =============================

void WriteLog(const string msg)
{
   Print("[XAU RSP] ", msg);
   if(g_logHandle == INVALID_HANDLE) return;
   string line = StringFormat("%s | %s\n",
                              TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                              msg);
   FileWriteString(g_logHandle, line);
   FileFlush(g_logHandle);
}

//============================== RISK ================================

datetime StartOfDay(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

void RiskOnTick()
{
   datetime today = StartOfDay(TimeCurrent());
   if(today != g_dayStartTime)
   {
      g_dayStartTime   = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }
}

double DayPnL()
{
   return AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity;
}

double DayPnLPercent()
{
   if(g_dayStartEquity <= 0) return 0.0;
   return (DayPnL() / g_dayStartEquity) * 100.0;
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
   lots = MathMax(minLot, MathMin(maxLot, lots));
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
   int diff          = MathAbs(curMinutes - targetMinutes);
   diff = MathMin(diff, 24 * 60 - diff);
   return diff <= avoidM;
}

bool FiltersOK(string &reason)
{
   int sp = CurrentSpreadPoints();
   if(sp > InpSpreadLimitPoints)
   {
      reason = StringFormat("Spread too high: %d > %d", sp, InpSpreadLimitPoints);
      return false;
   }

   if(!InpUseSessionFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour, m = dt.min;

   if(InpSessionStartHour <= InpSessionEndHour)
   {
      if(h < InpSessionStartHour || h >= InpSessionEndHour)
      {
         reason = StringFormat("Outside session %02d-%02d (now %02d:%02d)",
                               InpSessionStartHour, InpSessionEndHour, h, m);
         return false;
      }
   }
   else
   {
      if(h < InpSessionStartHour && h >= InpSessionEndHour)
      {
         reason = StringFormat("Outside session %02d-%02d (now %02d:%02d)",
                               InpSessionStartHour, InpSessionEndHour, h, m);
         return false;
      }
   }

   if(InpAvoidLondonOpen && IsAroundHour(h, m, InpLondonOpenHour, InpAvoidMinutesAround))
   {
      reason = StringFormat("London open +/- %dm", InpAvoidMinutesAround);
      return false;
   }
   if(InpAvoidNYOpen && IsAroundHour(h, m, InpNyOpenHour, InpAvoidMinutesAround))
   {
      reason = StringFormat("NY open +/- %dm", InpAvoidMinutesAround);
      return false;
   }
   return true;
}

//============================== RANGE DETECTION =====================

bool TouchesSpaced(const int &idx[], const int count, const int minSpace)
{
   if(count < 2) return false;
   for(int i = 0; i < count; i++)
      for(int j = i + 1; j < count; j++)
         if(MathAbs(idx[i] - idx[j]) >= minSpace)
            return true;
   return false;
}

bool RangeUpdate()
{
   ZeroMemory(g_range);
   g_range.computedAt = TimeCurrent();
   g_range.reason = "n/a";

   if(Bars(_Symbol, _Period) < InpRangeLookback + 5)
   {
      g_range.reason = "not enough bars";
      return false;
   }

   double highs[], lows[], closes[], opens[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(opens, true);
   if(CopyHigh(_Symbol, _Period, 1, InpRangeLookback, highs) <= 0) return false;
   if(CopyLow(_Symbol, _Period, 1, InpRangeLookback, lows)   <= 0) return false;
   if(CopyClose(_Symbol, _Period, 1, InpRangeLookback, closes) <= 0) return false;
   if(CopyOpen(_Symbol, _Period, 1, InpRangeLookback, opens)  <= 0) return false;

   double resistance = highs[ArrayMaximum(highs, 0, InpRangeLookback)];
   double support    = lows[ArrayMinimum(lows, 0, InpRangeLookback)];
   double width      = resistance - support;
   if(width <= 0)
   {
      g_range.reason = "no width";
      return false;
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpTouchTolerancePoints * point;

   int sIdx[256], rIdx[256];
   int sTouch = 0, rTouch = 0;
   int N = MathMin(InpRangeLookback, 256);

   for(int i = 0; i < N; i++)
   {
      if(highs[i] >= resistance - tol && closes[i] < resistance - tol*0.5)
      {
         if(rTouch < 256) rIdx[rTouch] = i;
         rTouch++;
      }
      if(lows[i] <= support + tol && closes[i] > support + tol*0.5)
      {
         if(sTouch < 256) sIdx[sTouch] = i;
         sTouch++;
      }
   }

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0) return false;
   double atr = atrBuf[0];

   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(g_adxHandle, 0, 1, 1, adxBuf) <= 0) return false;
   double adx = adxBuf[0];

   g_range.support           = support;
   g_range.resistance        = resistance;
   g_range.width             = width;
   g_range.supportTouches    = sTouch;
   g_range.resistanceTouches = rTouch;
   g_range.atr               = atr;
   g_range.adx               = adx;

   if(sTouch < InpMinTouchesPerSide || rTouch < InpMinTouchesPerSide)
   {
      g_range.valid = false;
      g_range.reason = StringFormat("touches S=%d R=%d", sTouch, rTouch);
      return true;
   }

   if(!TouchesSpaced(sIdx, sTouch, InpMinTouchSpacing) ||
      !TouchesSpaced(rIdx, rTouch, InpMinTouchSpacing))
   {
      g_range.valid = false;
      g_range.reason = "touches clustered";
      return true;
   }

   if(atr <= 0 || (atr / width) > InpAtrMaxRatio)
   {
      g_range.valid = false;
      g_range.reason = StringFormat("ATR/W=%.2f", (width > 0 ? atr/width : 0));
      return true;
   }

   if(adx > InpAdxMax)
   {
      g_range.valid = false;
      g_range.reason = StringFormat("ADX=%.1f trending", adx);
      return true;
   }

   if(InpUseHtfFilter)
   {
      double htfAtr[];
      ArraySetAsSeries(htfAtr, true);
      if(CopyBuffer(g_atrHtfHandle, 0, 1, 3, htfAtr) > 0)
      {
         double htfAtrAvg = (htfAtr[0] + htfAtr[1] + htfAtr[2]) / 3.0;
         if(htfAtrAvg > width * 0.5)
         {
            g_range.valid = false;
            g_range.reason = "HTF too volatile";
            return true;
         }
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
   bool bigCandle = body0 > 1.0 * g_range.atr;

   bool brokeUp = (c[0] > g_range.resistance) && (c[1] > g_range.resistance) && bigCandle;
   bool brokeDown = (c[0] < g_range.support) && (c[1] < g_range.support) && bigCandle;
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
   double body0 = c0 - o0;
   double body1 = o1 - c1;
   if(body1 <= 0 || body0 <= 0) return false;
   return (c0 >= o1) && (o0 <= c1) && (body0 >= body1);
}

bool IsBearishEngulfing(double o1, double c1, double o0, double c0)
{
   if(!(c1 > o1 && c0 < o0)) return false;
   double body0 = o0 - c0;
   double body1 = c1 - o1;
   if(body1 <= 0 || body0 <= 0) return false;
   return (c0 <= o1) && (o0 >= c1) && (body0 >= body1);
}

bool IsBullishPin(double op, double hi, double lo, double cl)
{
   double rng = hi - lo;
   if(rng <= 0) return false;
   double body  = MathAbs(cl - op);
   if(body <= 0) return false;
   double lower = MathMin(op, cl) - lo;
   double upper = hi - MathMax(op, cl);
   return (lower >= 2.0 * body) && (upper <= 0.5 * body) &&
          (cl >= lo + rng * 0.5) && (body <= rng * 0.4);
}

bool IsShootingStar(double op, double hi, double lo, double cl)
{
   double rng = hi - lo;
   if(rng <= 0) return false;
   double body  = MathAbs(cl - op);
   if(body <= 0) return false;
   double upper = hi - MathMax(op, cl);
   double lower = MathMin(op, cl) - lo;
   return (upper >= 2.0 * body) && (lower <= 0.5 * body) &&
          (cl <= lo + rng * 0.5) && (body <= rng * 0.4);
}

//============================== SIGNAL ENGINE =======================

ENUM_SIGNAL EvaluateSignal(double &outRsi)
{
   outRsi = 0.0;
   if(!g_range.valid) return SIG_NONE;

   double o[], h[], l[], c[];
   ArraySetAsSeries(o, true);
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   if(CopyOpen(_Symbol, _Period, 1, 3, o)  <= 0) return SIG_NONE;
   if(CopyHigh(_Symbol, _Period, 1, 3, h)  <= 0) return SIG_NONE;
   if(CopyLow(_Symbol, _Period, 1, 3, l)   <= 0) return SIG_NONE;
   if(CopyClose(_Symbol, _Period, 1, 3, c) <= 0) return SIG_NONE;

   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);
   if(CopyBuffer(g_rsiHandle, 0, 1, 2, rsiBuf) <= 0) return SIG_NONE;
   double rsiNow  = rsiBuf[0];
   double rsiPrev = rsiBuf[1];
   outRsi = rsiNow;

   double bbLower = 0.0, bbUpper = 0.0;
   if(InpUseBollinger)
   {
      double up[], lo[];
      ArraySetAsSeries(up, true);
      ArraySetAsSeries(lo, true);
      if(CopyBuffer(g_bbHandle, 1, 1, 1, up) <= 0) return SIG_NONE;
      if(CopyBuffer(g_bbHandle, 2, 1, 1, lo) <= 0) return SIG_NONE;
      bbUpper = up[0];
      bbLower = lo[0];
   }

   double ema = 0;
   if(InpUseTrendFilter)
   {
      double emaBuf[];
      ArraySetAsSeries(emaBuf, true);
      if(CopyBuffer(g_emaHandle, 0, 1, 1, emaBuf) <= 0) return SIG_NONE;
      ema = emaBuf[0];
   }

   bool nearSup = NearSupport(l[0]);
   bool nearRes = NearResistance(h[0]);

   if(nearSup)
   {
      bool patternOK = IsBullishEngulfing(o[1], c[1], o[0], c[0]) ||
                       IsBullishPin(o[0], h[0], l[0], c[0]);
      bool rsiOK     = (rsiNow <= InpRsiBuyMax) && (rsiNow >= rsiPrev);
      bool bbOK      = (!InpUseBollinger) || (l[0] <= bbLower);

      bool trendOK = true;
      if(InpUseTrendFilter && g_range.atr > 0)
      {
         double dist = ema - c[0];
         if(dist > InpEmaMaxDistAtr * g_range.atr) trendOK = false;
      }
      if(patternOK && rsiOK && bbOK && trendOK) return SIG_BUY;
   }

   if(nearRes)
   {
      bool patternOK = IsBearishEngulfing(o[1], c[1], o[0], c[0]) ||
                       IsShootingStar(o[0], h[0], l[0], c[0]);
      bool rsiOK     = (rsiNow >= InpRsiSellMin) && (rsiNow <= rsiPrev);
      bool bbOK      = (!InpUseBollinger) || (h[0] >= bbUpper);

      bool trendOK = true;
      if(InpUseTrendFilter && g_range.atr > 0)
      {
         double dist = c[0] - ema;
         if(dist > InpEmaMaxDistAtr * g_range.atr) trendOK = false;
      }
      if(patternOK && rsiOK && bbOK && trendOK) return SIG_SELL;
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

void DrawEntryObjects(const ENUM_ORDER_TYPE type, const double price,
                      const double sl, const double tp)
{
   if(!InpDrawObjects) return;
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string tag = "XRSP_" + ts;
   StringReplace(tag, ":", "");
   StringReplace(tag, " ", "_");
   StringReplace(tag, ".", "");

   string arrowName = "ARR_" + tag;
   if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), price))
   {
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, (type == ORDER_TYPE_BUY) ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, (type == ORDER_TYPE_BUY) ? clrLime : clrRed);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
   }
   if(sl > 0)
   {
      string slName = "SL_" + tag;
      if(ObjectCreate(0, slName, OBJ_HLINE, 0, 0, sl))
      {
         ObjectSetInteger(0, slName, OBJPROP_COLOR, clrCrimson);
         ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DOT);
      }
   }
   if(tp > 0)
   {
      string tpName = "TP_" + tag;
      if(ObjectCreate(0, tpName, OBJ_HLINE, 0, 0, tp))
      {
         ObjectSetInteger(0, tpName, OBJPROP_COLOR, clrDodgerBlue);
         ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DOT);
      }
   }
}

bool OpenTrade(const ENUM_ORDER_TYPE type, const double lots,
               const double sl, const double tp, const string comment)
{
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool ok = (type == ORDER_TYPE_BUY)
             ? g_trade.Buy(lots, _Symbol, price, sl, tp, comment)
             : g_trade.Sell(lots, _Symbol, price, sl, tp, comment);

   if(ok)
   {
      WriteLog(StringFormat("OPEN %s lots=%.2f price=%.2f SL=%.2f TP=%.2f (%s)",
                            (type == ORDER_TYPE_BUY ? "BUY":"SELL"),
                            lots, price, sl, tp, comment));
      if(InpPushAlerts)
      {
         SendNotification(StringFormat("[XAU RSP] %s @ %.2f",
                          (type == ORDER_TYPE_BUY ? "BUY":"SELL"), price));
         Alert(StringFormat("XAU RSP %s @ %.2f",
                          (type == ORDER_TYPE_BUY ? "BUY":"SELL"), price));
      }
      DrawEntryObjects(type, price, sl, tp);
   }
   else
   {
      WriteLog(StringFormat("OPEN FAIL err=%d %s",
                            g_trade.ResultRetcode(),
                            g_trade.ResultRetcodeDescription()));
   }
   return ok;
}

void ManageOpenPositions()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return;

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
      long   type      = g_pos.PositionType();

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double curPrice = (type == POSITION_TYPE_BUY) ? bid : ask;

      double profitPts = (type == POSITION_TYPE_BUY)
                         ? (curPrice - openPrice) / point
                         : (openPrice - curPrice) / point;

      double newSL = sl;

      if(InpUseBreakEven && profitPts >= InpBreakEvenTriggerPts)
      {
         double beSL = (type == POSITION_TYPE_BUY)
                       ? openPrice + InpBreakEvenLockPts * point
                       : openPrice - InpBreakEvenLockPts * point;
         if(type == POSITION_TYPE_BUY  && (sl < beSL || sl == 0)) newSL = beSL;
         if(type == POSITION_TYPE_SELL && (sl > beSL || sl == 0)) newSL = beSL;
      }

      if(InpUseTrailing && profitPts >= InpTrailStartPoints)
      {
         double trailSL = (type == POSITION_TYPE_BUY)
                          ? curPrice - InpTrailStepPoints * point
                          : curPrice + InpTrailStepPoints * point;
         if(type == POSITION_TYPE_BUY  && trailSL > newSL) newSL = trailSL;
         if(type == POSITION_TYPE_SELL && (trailSL < newSL || newSL == 0)) newSL = trailSL;
      }

      if(MathAbs(newSL - sl) > point && newSL != 0)
      {
         if(g_trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp))
            WriteLog(StringFormat("MODIFY ticket=%I64u newSL=%.2f", ticket, newSL));
      }
   }
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
         WriteLog(StringFormat("CLOSE ticket=%I64u (%s)", ticket, reason));
   }
}

//============================== STATS ===============================

void UpdateClosedTradeStats()
{
   datetime from = TimeCurrent() - 60 * 60 * 24 * 30;
   if(!HistorySelect(from, TimeCurrent())) return;
   int total = HistoryDealsTotal();
   int trades = 0, wins = 0, losses = 0;
   ulong newest = g_lastDealId;
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
      if(dealId > newest) newest = dealId;
   }
   g_totalTrades = trades;
   g_wins = wins;
   g_losses = losses;
   g_lastDealId = newest;
}

//============================== DASHBOARD ===========================

void DrawLabel(int line, const string title, const string value, color clr)
{
   string name = StringFormat("XRSP_DASH_L%02d", line);
   string text = StringFormat("%-10s : %s", title, value);
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

void UpdateDashboard(const string filterReason, const bool filtersOK)
{
   if(!InpShowDashboard) return;
   int line = 0;
   DrawLabel(line++, "XAU RSP", StringFormat("v1.1  %s", _Symbol), clrGold);
   DrawLabel(line++, "Range",
             g_range.valid
                ? StringFormat("S=%.2f  R=%.2f  W=%.2f", g_range.support, g_range.resistance, g_range.width)
                : StringFormat("INVALID (%s)", g_range.reason),
             g_range.valid ? clrLime : clrOrangeRed);
   DrawLabel(line++, "Touches",
             StringFormat("Sup=%d  Res=%d  ATR=%.2f  ADX=%.1f",
                          g_range.supportTouches, g_range.resistanceTouches, g_range.atr, g_range.adx),
             clrWhite);
   double wr = (g_totalTrades > 0) ? (100.0 * g_wins / g_totalTrades) : 0.0;
   DrawLabel(line++, "Trades",
             StringFormat("%d (W:%d / L:%d)  WR=%.1f%%", g_totalTrades, g_wins, g_losses, wr),
             clrWhite);
   DrawLabel(line++, "Daily PnL",
             StringFormat("%.2f (%.2f%%)", DayPnL(), DayPnLPercent()),
             (DayPnL() >= 0) ? clrLime : clrRed);
   DrawLabel(line++, "Spread", StringFormat("%d pts", CurrentSpreadPoints()), clrWhite);
   DrawLabel(line++, "Filter", filtersOK ? "OK" : filterReason,
             filtersOK ? clrLime : clrOrange);
}

//============================== ONINIT / ONTICK =====================

int OnInit()
{
   if(InpAllowTradingOnlyXAU)
   {
      string sym = _Symbol;
      StringToUpper(sym);
      if(StringFind(sym, "XAU") < 0)
      {
         Print("This EA is intended for XAUUSD. Current symbol: ", _Symbol);
         return INIT_FAILED;
      }
   }
   if(_Period != PERIOD_M5)
      Print("WARNING: EA tuned for M5. Current TF: ", EnumToString(_Period));

   g_atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   g_adxHandle = iADX(_Symbol, _Period, InpAdxPeriod);
   g_rsiHandle = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   if(g_atrHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed");
      return INIT_FAILED;
   }
   if(InpUseBollinger)
   {
      g_bbHandle = iBands(_Symbol, _Period, InpBbPeriod, 0, InpBbDeviation, PRICE_CLOSE);
      if(g_bbHandle == INVALID_HANDLE) return INIT_FAILED;
   }
   if(InpUseTrendFilter)
   {
      g_emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaHandle == INVALID_HANDLE) return INIT_FAILED;
   }
   if(InpUseHtfFilter)
   {
      g_atrHtfHandle = iATR(_Symbol, InpHtfPeriod, InpAtrPeriod);
      if(g_atrHtfHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_logHandle = FileOpen(InpLogFileName,
                          FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON|FILE_SHARE_READ);
   if(g_logHandle != INVALID_HANDLE)
   {
      FileSeek(g_logHandle, 0, SEEK_END);
      WriteLog("=== EA Started ===");
   }

   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartTime   = StartOfDay(TimeCurrent());

   ZeroMemory(g_range);
   g_lastBarTime = 0;
   g_breakoutCooldown = 0;
   g_totalTrades = g_wins = g_losses = 0;

   Print("XAU Range Scalper Pro v1.1 (All-in-One) initialised on ",
         _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle    != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle    != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_atrHtfHandle != INVALID_HANDLE) IndicatorRelease(g_atrHtfHandle);
   if(g_rsiHandle    != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_bbHandle     != INVALID_HANDLE) IndicatorRelease(g_bbHandle);
   if(g_emaHandle    != INVALID_HANDLE) IndicatorRelease(g_emaHandle);
   if(g_logHandle    != INVALID_HANDLE)
   {
      WriteLog("=== EA Stopped ===");
      FileClose(g_logHandle);
   }
   ObjectsDeleteAll(0, "XRSP_DASH_");
}

void OnTick()
{
   RiskOnTick();
   ManageOpenPositions();

   if(DailyLossHit())
   {
      static bool closedOnce = false;
      if(!closedOnce)
      {
         CloseAllOurPositions("Daily loss limit");
         closedOnce = true;
      }
      UpdateDashboard("Daily loss limit hit", false);
      return;
   }

   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime)
   {
      static datetime lastDashUpdate = 0;
      if(TimeCurrent() - lastDashUpdate >= 2)
      {
         UpdateDashboard("", true);
         lastDashUpdate = TimeCurrent();
      }
      return;
   }
   g_lastBarTime = curBarTime;

   RangeUpdate();

   if(IsStrongBreakout())
   {
      g_breakoutCooldown = InpBreakoutCooldownBars;
      WriteLog("Strong breakout detected -> entries paused");
   }
   if(g_breakoutCooldown > 0) g_breakoutCooldown--;

   UpdateClosedTradeStats();

   string filterReason = "";
   bool filtersOk = FiltersOK(filterReason);

   if(CountOpenPositions() >= InpMaxOpenTrades)
   {
      UpdateDashboard("Max trades open", false);
      return;
   }
   if(g_breakoutCooldown > 0)
   {
      UpdateDashboard(StringFormat("Breakout cooldown (%d)", g_breakoutCooldown), false);
      return;
   }
   if(!filtersOk)
   {
      UpdateDashboard(filterReason, false);
      return;
   }

   double rsi = 0.0;
   ENUM_SIGNAL sig = EvaluateSignal(rsi);
   if(sig == SIG_NONE || !g_range.valid)
   {
      UpdateDashboard("", true);
      return;
   }

   double atr = (g_range.atr > 0) ? g_range.atr : 0.0;
   if(atr <= 0)
   {
      UpdateDashboard("ATR not ready", false);
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = 0, tp = 0, entry = 0;

   if(sig == SIG_BUY)
   {
      entry = ask;
      sl    = g_range.support - InpSlAtrMultiplier * atr;
      double slDist = entry - sl;
      tp    = entry + InpTpRRMultiplier * slDist;
      if(InpTpAtRangeOpposite)
         tp = MathMin(tp, g_range.resistance - 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }
   else
   {
      entry = bid;
      sl    = g_range.resistance + InpSlAtrMultiplier * atr;
      double slDist = sl - entry;
      tp    = entry - InpTpRRMultiplier * slDist;
      if(InpTpAtRangeOpposite)
         tp = MathMax(tp, g_range.support + 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }

   double slDistPrice = MathAbs(entry - sl);
   double tpDistPrice = MathAbs(tp - entry);
   if(slDistPrice <= 0 || tpDistPrice < slDistPrice * 0.8)
   {
      UpdateDashboard("RR too small", false);
      return;
   }

   double lots = CalcLotByRisk(slDistPrice);
   if(lots <= 0)
   {
      UpdateDashboard("Lot calc failed", false);
      return;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   string cmt = StringFormat("%s_%s_RSI%.0f_ADX%.0f", InpTradeComment,
                             (sig == SIG_BUY ? "B":"S"), rsi, g_range.adx);

   ENUM_ORDER_TYPE otype = (sig == SIG_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   OpenTrade(otype, lots, sl, tp, cmt);

   UpdateDashboard("", true);
}

void OnTrade() {}
//+------------------------------------------------------------------+
