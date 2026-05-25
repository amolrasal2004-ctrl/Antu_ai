//+------------------------------------------------------------------+
//|                              XAU_Range_Scalper_Pro_Final_v2.mq5  |
//|                                          Copyright 2026, Antu AI |
//|                                                                  |
//|  XAUUSD M5 range/scalping EA - FINAL v2                          |
//|  - Single self-contained file (no external includes needed)     |
//|  - Professional on-chart dashboard                               |
//|  - ADX + ATR/range ratio + touch-spacing range detection         |
//|  - Bullish/Bearish engulfing + pin/star pattern signals          |
//|  - RSI slope confirmation                                        |
//|  - Optional EMA-200 trend filter, BB filter, HTF filter          |
//|  - Risk %-based sizing, daily loss guard                         |
//|  - Break-even + trailing stop                                    |
//|  - Session + spread + London/NY open avoidance filters           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antu AI"
#property version   "2.00"
#property description "XAU Range Scalper Pro Final v2 - XAUUSD M5"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//============================== INPUTS ==============================
input group "=== General ==="
input ulong  InpMagic                = 20260525;
input string InpTradeComment         = "XAU_RSP";
input bool   InpAllowOnlyXAU         = true;
input bool   InpDrawObjects          = true;
input bool   InpShowDashboard        = true;
input bool   InpPushAlerts           = false;
input string InpLogFileName          = "XAU_RSP_log.txt";

input group "=== Risk Management ==="
input double InpRiskPercent          = 1.0;
input double InpMaxDailyLossPercent  = 3.0;
input int    InpMaxOpenTrades        = 1;


input group "=== Range Detection ==="
input int    InpRangeLookback        = 50;
input int    InpMinTouchesPerSide    = 2;
input int    InpMinTouchSpacing      = 3;
input double InpTouchTolerancePoints = 250;
input double InpAtrMaxRatio          = 0.45;
input int    InpBreakoutCooldownBars = 20;
input bool   InpUseHtfFilter         = false;
input ENUM_TIMEFRAMES InpHtfPeriod   = PERIOD_M15;

input group "=== Indicators ==="
input int    InpAtrPeriod            = 14;
input int    InpAdxPeriod            = 14;
input double InpAdxMax               = 30.0;
input int    InpRsiPeriod            = 14;
input double InpRsiBuyMax            = 38.0;
input double InpRsiSellMin           = 62.0;
input bool   InpUseBollinger         = false;
input int    InpBbPeriod             = 20;
input double InpBbDeviation          = 2.0;
input bool   InpUseTrendFilter       = false;
input int    InpEmaPeriod            = 200;
input double InpEmaMaxDistAtr        = 5.0;

input group "=== SL / TP ==="
input double InpSlAtrMultiplier      = 1.5;
input double InpTpRRMultiplier       = 1.8;
input bool   InpTpAtRangeOpposite    = true;

input group "=== Trade Management ==="
input bool   InpUseBreakEven         = true;
input double InpBreakEvenTriggerPts  = 600;
input double InpBreakEvenLockPts     = 50;
input bool   InpUseTrailing          = true;
input double InpTrailStartPoints     = 1000;
input double InpTrailStepPoints      = 500;

input group "=== Filters ==="
input int    InpSpreadLimitPoints    = 50;
input int    InpSlippagePoints       = 20;
input bool   InpUseSessionFilter     = true;
input int    InpSessionStartHour     = 8;
input int    InpSessionEndHour       = 19;
input bool   InpAvoidLondonOpen      = true;
input bool   InpAvoidNYOpen          = true;
input int    InpLondonOpenHour       = 10;
input int    InpNyOpenHour           = 15;
input int    InpAvoidMinutesAround   = 20;


input group "=== Dashboard Style ==="
input int    InpDashX                = 14;
input int    InpDashY                = 30;
input int    InpDashWidth            = 360;
input color  InpDashBgColor          = C'18,22,30';
input color  InpDashBorderColor      = C'80,90,110';
input color  InpDashTitleColor       = clrGold;
input color  InpDashLabelColor       = C'170,180,200';
input color  InpDashValueColor       = clrWhite;
input color  InpDashOkColor          = C'70,200,120';
input color  InpDashBadColor         = C'235,90,90';
input color  InpDashWarnColor        = C'255,170,60';

//============================== TYPES ===============================
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

enum ENUM_SIGNAL { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = 2 };

//============================== GLOBALS =============================
CTrade         g_trade;
CPositionInfo  g_pos;

int    g_atrHandle    = INVALID_HANDLE;
int    g_adxHandle    = INVALID_HANDLE;
int    g_atrHtfHandle = INVALID_HANDLE;
int    g_rsiHandle    = INVALID_HANDLE;
int    g_bbHandle     = INVALID_HANDLE;
int    g_emaHandle    = INVALID_HANDLE;

SRange   g_range;
datetime g_lastBarTime    = 0;
int      g_breakoutCD     = 0;
int      g_logHandle      = INVALID_HANDLE;

double   g_dayStartEquity = 0.0;
datetime g_dayStartTime   = 0;

int      g_totalTrades    = 0;
int      g_wins           = 0;
int      g_losses         = 0;

ENUM_SIGNAL g_lastSignal  = SIG_NONE;
string      g_lastFilter  = "";
bool        g_filtersOK   = true;


//============================== UTILS ===============================
datetime StartOfDay(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

void ResetRange()
{
   g_range.valid             = false;
   g_range.support           = 0.0;
   g_range.resistance        = 0.0;
   g_range.width             = 0.0;
   g_range.supportTouches    = 0;
   g_range.resistanceTouches = 0;
   g_range.atr               = 0.0;
   g_range.adx               = 0.0;
   g_range.computedAt        = 0;
   g_range.reason            = "";
}

void WriteLog(const string msg)
{
   Print("[XAU RSP] ", msg);
   if(g_logHandle == INVALID_HANDLE) return;
   string ts   = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string line = ts + " | " + msg;
   FileWriteString(g_logHandle, line);
   FileWriteString(g_logHandle, ShortToString(13) + ShortToString(10));
   FileFlush(g_logHandle);
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


double DayPnL()        { return AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity; }
double DayPnLPercent() { return (g_dayStartEquity > 0) ? (DayPnL() / g_dayStartEquity) * 100.0 : 0.0; }
bool   DailyLossHit()  { return (InpMaxDailyLossPercent > 0) && (DayPnLPercent() <= -InpMaxDailyLossPercent); }

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

//============================== FILTERS =============================
int CurrentSpreadPoints() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

bool IsAroundHour(int curH, int curM, int targetH, int avoidMin)
{
   int curMinutes    = curH * 60 + curM;
   int targetMinutes = targetH * 60;
   int diff          = MathAbs(curMinutes - targetMinutes);
   diff = MathMin(diff, 24 * 60 - diff);
   return diff <= avoidMin;
}

bool FiltersOK(string &reason)
{
   int sp = CurrentSpreadPoints();
   if(sp > InpSpreadLimitPoints)
   {
      reason = StringFormat("Spread %d > %d", sp, InpSpreadLimitPoints);
      return false;
   }
   if(InpUseSessionFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour, m = dt.min;
      if(InpSessionStartHour <= InpSessionEndHour)
      {
         if(h < InpSessionStartHour || h >= InpSessionEndHour)
         {
            reason = StringFormat("Outside %02d-%02d (now %02d:%02d)",
                                  InpSessionStartHour, InpSessionEndHour, h, m);
            return false;
         }
      }
      if(InpAvoidLondonOpen && IsAroundHour(h, m, InpLondonOpenHour, InpAvoidMinutesAround))
      {
         reason = StringFormat("London open +/-%dm", InpAvoidMinutesAround);
         return false;
      }
      if(InpAvoidNYOpen && IsAroundHour(h, m, InpNyOpenHour, InpAvoidMinutesAround))
      {
         reason = StringFormat("NY open +/-%dm", InpAvoidMinutesAround);
         return false;
      }
   }
   reason = "";
   return true;
}


//============================== RANGE DETECTION =====================
bool TouchesSpaced(const int &idx[], const int count)
{
   if(count < 2) return false;
   for(int i = 0; i < count; i++)
      for(int j = i + 1; j < count; j++)
         if(MathAbs(idx[i] - idx[j]) >= InpMinTouchSpacing)
            return true;
   return false;
}

bool RangeUpdate()
{
   ResetRange();
   g_range.computedAt = TimeCurrent();
   g_range.reason     = "n/a";

   if(Bars(_Symbol, _Period) < InpRangeLookback + 5)
   {
      g_range.reason = "not enough bars"; return false;
   }

   double highs[], lows[], closes[], opens[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(opens, true);
   if(CopyHigh(_Symbol, _Period, 1, InpRangeLookback, highs)   <= 0) return false;
   if(CopyLow(_Symbol, _Period, 1, InpRangeLookback, lows)     <= 0) return false;
   if(CopyClose(_Symbol, _Period, 1, InpRangeLookback, closes) <= 0) return false;
   if(CopyOpen(_Symbol, _Period, 1, InpRangeLookback, opens)   <= 0) return false;

   double resistance = highs[ArrayMaximum(highs, 0, InpRangeLookback)];
   double support    = lows[ArrayMinimum(lows,  0, InpRangeLookback)];
   double width      = resistance - support;
   if(width <= 0) { g_range.reason = "no width"; return false; }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpTouchTolerancePoints * point;

   int sIdx[], rIdx[];
   ArrayResize(sIdx, 0); ArrayResize(rIdx, 0);
   int sTouch = 0, rTouch = 0;

   for(int i = 0; i < InpRangeLookback; i++)
   {
      if(highs[i] >= resistance - tol && closes[i] < resistance - tol*0.5)
      {
         int n = ArraySize(rIdx); ArrayResize(rIdx, n+1); rIdx[n] = i; rTouch++;
      }
      if(lows[i] <= support + tol && closes[i] > support + tol*0.5)
      {
         int n = ArraySize(sIdx); ArrayResize(sIdx, n+1); sIdx[n] = i; sTouch++;
      }
   }


   double atrBuf[]; ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0) return false;
   double atr = atrBuf[0];

   double adxBuf[]; ArraySetAsSeries(adxBuf, true);
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
      g_range.reason = StringFormat("touches S=%d R=%d", sTouch, rTouch); return true;
   }
   if(!TouchesSpaced(sIdx, sTouch) || !TouchesSpaced(rIdx, rTouch))
   {
      g_range.reason = "touches clustered"; return true;
   }
   if(atr <= 0 || (atr / width) > InpAtrMaxRatio)
   {
      g_range.reason = StringFormat("ATR/W=%.2f", (width > 0 ? atr/width : 0)); return true;
   }
   if(adx > InpAdxMax)
   {
      g_range.reason = StringFormat("ADX=%.1f trend", adx); return true;
   }
   if(InpUseHtfFilter && g_atrHtfHandle != INVALID_HANDLE)
   {
      double htfAtr[]; ArraySetAsSeries(htfAtr, true);
      if(CopyBuffer(g_atrHtfHandle, 0, 1, 3, htfAtr) > 0)
      {
         double avg = (htfAtr[0] + htfAtr[1] + htfAtr[2]) / 3.0;
         if(avg > width * 0.5) { g_range.reason = "HTF too volatile"; return true; }
      }
   }
   g_range.valid  = true;
   g_range.reason = "OK";
   return true;
}

bool IsStrongBreakout()
{
   if(g_range.width <= 0 || g_range.atr <= 0) return false;
   double o[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if(CopyOpen(_Symbol, _Period, 1, 2, o) <= 0) return false;
   if(CopyClose(_Symbol, _Period, 1, 2, c) <= 0) return false;
   double body0 = MathAbs(c[0] - o[0]);
   bool bigCandle = body0 > 1.0 * g_range.atr;
   bool brokeUp   = (c[0] > g_range.resistance) && (c[1] > g_range.resistance) && bigCandle;
   bool brokeDown = (c[0] < g_range.support)    && (c[1] < g_range.support)    && bigCandle;
   return brokeUp || brokeDown;
}

bool NearSupport(const double price)
{
   double tol = InpTouchTolerancePoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (price <= g_range.support + tol);
}
bool NearResistance(const double price)
{
   double tol = InpTouchTolerancePoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (price >= g_range.resistance - tol);
}


//============================== PATTERNS ============================
bool IsBullishEngulfing(double o1, double c1, double o0, double c0)
{
   if(!(c1 < o1 && c0 > o0)) return false;
   double b0 = c0 - o0, b1 = o1 - c1;
   if(b1 <= 0 || b0 <= 0) return false;
   return (c0 >= o1) && (o0 <= c1) && (b0 >= b1);
}
bool IsBearishEngulfing(double o1, double c1, double o0, double c0)
{
   if(!(c1 > o1 && c0 < o0)) return false;
   double b0 = o0 - c0, b1 = c1 - o1;
   if(b1 <= 0 || b0 <= 0) return false;
   return (c0 <= o1) && (o0 >= c1) && (b0 >= b1);
}
bool IsBullishPin(double op, double hi, double lo, double cl)
{
   double rng = hi - lo; if(rng <= 0) return false;
   double body = MathAbs(cl - op); if(body <= 0) return false;
   double lower = MathMin(op, cl) - lo;
   double upper = hi - MathMax(op, cl);
   return (lower >= 2.0*body) && (upper <= 0.5*body) &&
          (cl >= lo + rng*0.5) && (body <= rng*0.4);
}
bool IsShootingStar(double op, double hi, double lo, double cl)
{
   double rng = hi - lo; if(rng <= 0) return false;
   double body = MathAbs(cl - op); if(body <= 0) return false;
   double upper = hi - MathMax(op, cl);
   double lower = MathMin(op, cl) - lo;
   return (upper >= 2.0*body) && (lower <= 0.5*body) &&
          (cl <= lo + rng*0.5) && (body <= rng*0.4);
}

//============================== SIGNAL ==============================
ENUM_SIGNAL EvaluateSignal(double &outRsi)
{
   outRsi = 0.0;
   if(!g_range.valid) return SIG_NONE;

   double o[], h[], l[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   if(CopyOpen(_Symbol, _Period, 1, 3, o)  <= 0) return SIG_NONE;
   if(CopyHigh(_Symbol, _Period, 1, 3, h)  <= 0) return SIG_NONE;
   if(CopyLow(_Symbol, _Period, 1, 3, l)   <= 0) return SIG_NONE;
   if(CopyClose(_Symbol, _Period, 1, 3, c) <= 0) return SIG_NONE;

   double rsiBuf[]; ArraySetAsSeries(rsiBuf, true);
   if(CopyBuffer(g_rsiHandle, 0, 1, 2, rsiBuf) <= 0) return SIG_NONE;
   double rsiNow = rsiBuf[0], rsiPrev = rsiBuf[1];
   outRsi = rsiNow;

   double bbU = 0, bbL = 0;
   if(InpUseBollinger && g_bbHandle != INVALID_HANDLE)
   {
      double up[], lo[]; ArraySetAsSeries(up, true); ArraySetAsSeries(lo, true);
      if(CopyBuffer(g_bbHandle, 1, 1, 1, up) <= 0) return SIG_NONE;
      if(CopyBuffer(g_bbHandle, 2, 1, 1, lo) <= 0) return SIG_NONE;
      bbU = up[0]; bbL = lo[0];
   }
   double ema = 0;
   if(InpUseTrendFilter && g_emaHandle != INVALID_HANDLE)
   {
      double e[]; ArraySetAsSeries(e, true);
      if(CopyBuffer(g_emaHandle, 0, 1, 1, e) <= 0) return SIG_NONE;
      ema = e[0];
   }


   if(NearSupport(l[0]))
   {
      bool pat = IsBullishEngulfing(o[1], c[1], o[0], c[0]) || IsBullishPin(o[0], h[0], l[0], c[0]);
      bool rsiOK = (rsiNow <= InpRsiBuyMax) && (rsiNow >= rsiPrev);
      bool bbOK  = (!InpUseBollinger) || (l[0] <= bbL);
      bool trOK  = true;
      if(InpUseTrendFilter && g_range.atr > 0)
         if((ema - c[0]) > InpEmaMaxDistAtr * g_range.atr) trOK = false;
      if(pat && rsiOK && bbOK && trOK) return SIG_BUY;
   }
   if(NearResistance(h[0]))
   {
      bool pat = IsBearishEngulfing(o[1], c[1], o[0], c[0]) || IsShootingStar(o[0], h[0], l[0], c[0]);
      bool rsiOK = (rsiNow >= InpRsiSellMin) && (rsiNow <= rsiPrev);
      bool bbOK  = (!InpUseBollinger) || (h[0] >= bbU);
      bool trOK  = true;
      if(InpUseTrendFilter && g_range.atr > 0)
         if((c[0] - ema) > InpEmaMaxDistAtr * g_range.atr) trOK = false;
      if(pat && rsiOK && bbOK && trOK) return SIG_SELL;
   }
   return SIG_NONE;
}

//============================== TRADE OPS ===========================
bool OpenTrade(const ENUM_ORDER_TYPE type, const double lots, const double sl, const double tp, const string cmt)
{
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool ok = (type == ORDER_TYPE_BUY)
             ? g_trade.Buy(lots, _Symbol, price, sl, tp, cmt)
             : g_trade.Sell(lots, _Symbol, price, sl, tp, cmt);
   if(ok)
   {
      WriteLog(StringFormat("OPEN %s lots=%.2f price=%.2f SL=%.2f TP=%.2f (%s)",
               (type == ORDER_TYPE_BUY ? "BUY":"SELL"), lots, price, sl, tp, cmt));
      if(InpPushAlerts) { SendNotification("[XAU RSP] " + cmt); }
   }
   else
   {
      WriteLog(StringFormat("OPEN FAIL retcode=%d %s",
               g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
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
      double sl = g_pos.StopLoss();
      double tp = g_pos.TakeProfit();
      long   type = g_pos.PositionType();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur = (type == POSITION_TYPE_BUY) ? bid : ask;
      double profitPts = (type == POSITION_TYPE_BUY) ? (cur - openPrice)/point : (openPrice - cur)/point;
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
                          ? cur - InpTrailStepPoints * point
                          : cur + InpTrailStepPoints * point;
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


//============================== PRO DASHBOARD =======================
#define DASH_PFX "XRSPv2_"

void DashRect(const string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

void DashText(const string name, int x, int y, const string text, color clr,
              int fontSize = 9, const string font = "Consolas", bool bold = false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString (0, name, OBJPROP_FONT, bold ? "Arial Bold" : font);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
}

//--- a small status pill (colored rectangle + text) for OK/BAD badges
void DashPill(const string nameBg, const string nameTxt,
              int x, int y, int w, int h, const string text, color bg, color txtClr)
{
   DashRect(nameBg, x, y, w, h, bg, bg);
   DashText(nameTxt, x + 6, y + 2, text, txtClr, 8, "Arial", true);
}

void DashboardInit()
{
   // pre-create the panel so first frame already shows
   int x = InpDashX, y = InpDashY, w = InpDashWidth;
   DashRect(DASH_PFX + "BG", x, y, w, 232, InpDashBgColor, InpDashBorderColor);
   // header strip
   DashRect(DASH_PFX + "HDR", x, y, w, 26, C'30,40,55', InpDashBorderColor);
}

void DashboardDeinit()
{
   ObjectsDeleteAll(0, DASH_PFX);
}


void DashboardUpdate()
{
   if(!InpShowDashboard) return;

   int x = InpDashX, y = InpDashY, w = InpDashWidth;
   int panelH = 232;

   // panel + header
   DashRect(DASH_PFX + "BG",  x, y, w, panelH, InpDashBgColor, InpDashBorderColor);
   DashRect(DASH_PFX + "HDR", x, y, w, 26,     C'30,40,55',    InpDashBorderColor);

   // header text: title + symbol + TF
   DashText(DASH_PFX + "TITLE", x + 10, y + 5,
            "XAU RANGE SCALPER PRO  v2.0", InpDashTitleColor, 10, "Arial Bold", true);
   string tfStr = EnumToString(_Period);
   StringReplace(tfStr, "PERIOD_", "");
   DashText(DASH_PFX + "SYMTF", x + w - 90, y + 5,
            StringFormat("%s  %s", _Symbol, tfStr), InpDashLabelColor, 9, "Arial", true);

   //----- Section 1: Range -----
   int sy = y + 32;
   DashText(DASH_PFX + "S1", x + 10, sy, "RANGE", InpDashTitleColor, 8, "Arial", true);

   // status pill: VALID / INVALID
   color pillBg = g_range.valid ? InpDashOkColor : InpDashBadColor;
   string pillTxt = g_range.valid ? " VALID " : " INVALID ";
   DashPill(DASH_PFX + "PILL_BG", DASH_PFX + "PILL_TXT",
            x + w - 80, sy - 1, 70, 16, pillTxt, pillBg, clrWhite);

   sy += 16;
   string l1 = g_range.valid
               ? StringFormat("S %.2f   R %.2f   W %.2f",
                              g_range.support, g_range.resistance, g_range.width)
               : StringFormat("Reason: %s", g_range.reason);
   DashText(DASH_PFX + "L1", x + 10, sy, l1,
            g_range.valid ? InpDashValueColor : InpDashWarnColor, 9);

   sy += 14;
   DashText(DASH_PFX + "L2", x + 10, sy,
            StringFormat("Touches  S:%d  R:%d   ATR %.2f   ADX %.1f",
                         g_range.supportTouches, g_range.resistanceTouches,
                         g_range.atr, g_range.adx),
            InpDashLabelColor, 9);

   //----- Section 2: Signal & Filters -----
   sy += 22;
   DashText(DASH_PFX + "S2", x + 10, sy, "SIGNAL  /  FILTERS", InpDashTitleColor, 8, "Arial", true);

   sy += 16;
   string sigTxt; color sigCol;
   if(g_lastSignal == SIG_BUY)       { sigTxt = " BUY ";  sigCol = InpDashOkColor; }
   else if(g_lastSignal == SIG_SELL) { sigTxt = " SELL "; sigCol = InpDashBadColor; }
   else                              { sigTxt = " WAIT "; sigCol = C'90,100,120'; }
   DashPill(DASH_PFX + "SIG_BG", DASH_PFX + "SIG_TXT",
            x + 10, sy - 1, 56, 16, sigTxt, sigCol, clrWhite);

   string filtPill = g_filtersOK ? " OK " : " BLOCK ";
   color  filtCol  = g_filtersOK ? InpDashOkColor : InpDashWarnColor;
   DashPill(DASH_PFX + "FLT_BG", DASH_PFX + "FLT_TXT",
            x + 72, sy - 1, 56, 16, filtPill, filtCol, clrWhite);

   string filtMsg = g_filtersOK ? "Ready to trade" : g_lastFilter;
   DashText(DASH_PFX + "FLT_MSG", x + 134, sy + 1, filtMsg,
            g_filtersOK ? InpDashValueColor : InpDashWarnColor, 9);

   sy += 16;
   DashText(DASH_PFX + "SPRD", x + 10, sy,
            StringFormat("Spread %d pts   Cooldown %d", CurrentSpreadPoints(), g_breakoutCD),
            InpDashLabelColor, 9);


   //----- Section 3: Performance -----
   sy += 22;
   DashText(DASH_PFX + "S3", x + 10, sy, "PERFORMANCE", InpDashTitleColor, 8, "Arial", true);

   sy += 16;
   double wr = (g_totalTrades > 0) ? (100.0 * g_wins / g_totalTrades) : 0.0;
   DashText(DASH_PFX + "TRADES", x + 10, sy,
            StringFormat("Trades %d   W %d   L %d   WR %.1f%%",
                         g_totalTrades, g_wins, g_losses, wr),
            InpDashValueColor, 9);

   sy += 14;
   double pnl  = DayPnL();
   double pnlP = DayPnLPercent();
   color  pnlC = (pnl >= 0) ? InpDashOkColor : InpDashBadColor;
   string acc  = AccountInfoString(ACCOUNT_CURRENCY);
   DashText(DASH_PFX + "PNL", x + 10, sy,
            StringFormat("Day PnL  %+.2f %s   (%+.2f%%)", pnl, acc, pnlP),
            pnlC, 9);

   //----- Section 4: Risk Meter -----
   sy += 20;
   DashText(DASH_PFX + "S4", x + 10, sy, "DAILY RISK USED", InpDashTitleColor, 8, "Arial", true);

   sy += 14;
   // background bar
   int barW = w - 20, barH = 10;
   DashRect(DASH_PFX + "RISK_BG", x + 10, sy, barW, barH, C'40,46,58', C'70,80,95');

   // fill: red portion = % of daily loss budget consumed (0..100)
   double usedPct = 0.0;
   if(InpMaxDailyLossPercent > 0 && pnlP < 0)
      usedPct = MathMin(100.0, (-pnlP) / InpMaxDailyLossPercent * 100.0);
   int fillW = (int)MathRound(barW * usedPct / 100.0);
   color fillC = (usedPct < 50)  ? InpDashOkColor
               : (usedPct < 80)  ? InpDashWarnColor
                                 : InpDashBadColor;
   if(fillW > 0)
      DashRect(DASH_PFX + "RISK_FILL", x + 10, sy, fillW, barH, fillC, fillC);
   else
      ObjectDelete(0, DASH_PFX + "RISK_FILL");

   sy += 12;
   DashText(DASH_PFX + "RISK_TXT", x + 10, sy,
            StringFormat("%.1f%% of %.1f%% used   |   Risk/trade %.2f%%",
                         usedPct, InpMaxDailyLossPercent, InpRiskPercent),
            InpDashLabelColor, 8);

   //----- Section 5: Footer status line -----
   sy += 18;
   DashRect(DASH_PFX + "FTR", x, sy, w, 22, C'24,30,42', InpDashBorderColor);
   string st;
   if(DailyLossHit())                 st = "DAILY LOSS LIMIT - TRADING HALTED";
   else if(g_breakoutCD > 0)          st = StringFormat("Breakout cooldown - %d bars left", g_breakoutCD);
   else if(CountOpenPositions() > 0)  st = StringFormat("Position open (%d)", CountOpenPositions());
   else if(!g_range.valid)            st = "Searching for range...";
   else if(!g_filtersOK)              st = "Waiting on filters";
   else                               st = "Scanning for setup";
   DashText(DASH_PFX + "FTR_TXT", x + 10, sy + 4, st, InpDashValueColor, 9, "Consolas", true);

   // tiny clock on right
   string clk = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   DashText(DASH_PFX + "CLK", x + w - 110, sy + 4, clk, InpDashLabelColor, 9);
}


//============================== CHART OBJECTS =======================
void DrawRangeOnChart()
{
   if(!InpDrawObjects) return;
   string sn = "XRSP_SUP", rn = "XRSP_RES";
   if(!g_range.valid)
   {
      ObjectDelete(0, sn); ObjectDelete(0, rn);
      return;
   }
   if(ObjectFind(0, sn) < 0) ObjectCreate(0, sn, OBJ_HLINE, 0, 0, g_range.support);
   if(ObjectFind(0, rn) < 0) ObjectCreate(0, rn, OBJ_HLINE, 0, 0, g_range.resistance);
   ObjectSetDouble (0, sn, OBJPROP_PRICE, g_range.support);
   ObjectSetDouble (0, rn, OBJPROP_PRICE, g_range.resistance);
   ObjectSetInteger(0, sn, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, rn, OBJPROP_COLOR, clrTomato);
   ObjectSetInteger(0, sn, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, rn, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, sn, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, rn, OBJPROP_WIDTH, 1);
   ObjectSetString (0, sn, OBJPROP_TEXT, "Support");
   ObjectSetString (0, rn, OBJPROP_TEXT, "Resistance");
}

void DrawEntry(const ENUM_ORDER_TYPE type, const double price, const double sl, const double tp)
{
   if(!InpDrawObjects) return;
   string ts  = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string tag = "XRSP_" + ts;
   StringReplace(tag, ":", ""); StringReplace(tag, " ", "_"); StringReplace(tag, ".", "");
   string an = "ARR_" + tag;
   if(ObjectCreate(0, an, OBJ_ARROW, 0, TimeCurrent(), price))
   {
      ObjectSetInteger(0, an, OBJPROP_ARROWCODE, (type == ORDER_TYPE_BUY) ? 233 : 234);
      ObjectSetInteger(0, an, OBJPROP_COLOR, (type == ORDER_TYPE_BUY) ? clrLime : clrRed);
      ObjectSetInteger(0, an, OBJPROP_WIDTH, 2);
   }
}

//============================== STATS ===============================
void UpdateClosedTradeStats()
{
   datetime from = TimeCurrent() - 60 * 60 * 24 * 30;
   if(!HistorySelect(from, TimeCurrent())) return;
   int total = HistoryDealsTotal();
   int trades = 0, wins = 0, losses = 0;
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
   }
   g_totalTrades = trades; g_wins = wins; g_losses = losses;
}


//============================== ON INIT =============================
int OnInit()
{
   if(InpAllowOnlyXAU)
   {
      string sym = _Symbol; StringToUpper(sym);
      if(StringFind(sym, "XAU") < 0)
      {
         Print("EA intended for XAUUSD. Symbol=", _Symbol);
         return INIT_FAILED;
      }
   }
   if(_Period != PERIOD_M5)
      Print("WARNING: EA tuned for M5. Current TF=", EnumToString(_Period));

   g_atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   g_adxHandle = iADX(_Symbol, _Period, InpAdxPeriod);
   g_rsiHandle = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   if(g_atrHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE || g_rsiHandle == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed err=", GetLastError());
      return INIT_FAILED;
   }
   if(InpUseHtfFilter)
   {
      g_atrHtfHandle = iATR(_Symbol, InpHtfPeriod, InpAtrPeriod);
      if(g_atrHtfHandle == INVALID_HANDLE) { Print("HTF ATR failed"); return INIT_FAILED; }
   }
   if(InpUseBollinger)
   {
      g_bbHandle = iBands(_Symbol, _Period, InpBbPeriod, 0, InpBbDeviation, PRICE_CLOSE);
      if(g_bbHandle == INVALID_HANDLE) { Print("BB failed"); return INIT_FAILED; }
   }
   if(InpUseTrendFilter)
   {
      g_emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaHandle == INVALID_HANDLE) { Print("EMA failed"); return INIT_FAILED; }
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_logHandle = FileOpen(InpLogFileName, FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON|FILE_SHARE_READ);
   if(g_logHandle != INVALID_HANDLE)
   {
      FileSeek(g_logHandle, 0, SEEK_END);
      WriteLog("=== EA Started ===");
   }

   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartTime   = StartOfDay(TimeCurrent());

   ResetRange();
   g_lastBarTime = 0;
   g_breakoutCD  = 0;

   if(InpShowDashboard) DashboardInit();
   EventSetTimer(1);  // ticking dashboard clock

   Print("XAU Range Scalper Pro v2.0 initialised on ", _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
}

//============================== ON DEINIT ===========================
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_atrHandle    != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle    != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_atrHtfHandle != INVALID_HANDLE) IndicatorRelease(g_atrHtfHandle);
   if(g_rsiHandle    != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_bbHandle     != INVALID_HANDLE) IndicatorRelease(g_bbHandle);
   if(g_emaHandle    != INVALID_HANDLE) IndicatorRelease(g_emaHandle);
   g_atrHandle = g_adxHandle = g_atrHtfHandle = INVALID_HANDLE;
   g_rsiHandle = g_bbHandle  = g_emaHandle    = INVALID_HANDLE;

   if(g_logHandle != INVALID_HANDLE)
   {
      WriteLog("=== EA Stopped ===");
      FileClose(g_logHandle);
      g_logHandle = INVALID_HANDLE;
   }
   if(InpShowDashboard) DashboardDeinit();
   ObjectDelete(0, "XRSP_SUP");
   ObjectDelete(0, "XRSP_RES");
}

//============================== ON TIMER ============================
void OnTimer()
{
   // keep dashboard responsive even when ticks are slow
   if(InpShowDashboard) DashboardUpdate();
}


//============================== ON TICK =============================
void OnTick()
{
   // daily anchor reset
   datetime today = StartOfDay(TimeCurrent());
   if(today != g_dayStartTime)
   {
      g_dayStartTime   = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   // always manage open positions (BE/trail)
   ManageOpenPositions();

   // daily loss guard
   if(DailyLossHit())
   {
      static bool closedOnce = false;
      if(!closedOnce)
      {
         CloseAllOurPositions("Daily loss limit");
         closedOnce = true;
      }
      g_filtersOK  = false;
      g_lastFilter = "Daily loss limit";
      if(InpShowDashboard) DashboardUpdate();
      return;
   }

   // run signal logic only on new bar
   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime)
   {
      if(InpShowDashboard) DashboardUpdate();
      return;
   }
   g_lastBarTime = curBarTime;

   RangeUpdate();
   DrawRangeOnChart();

   if(IsStrongBreakout())
   {
      g_breakoutCD = InpBreakoutCooldownBars;
      WriteLog("Strong breakout -> entries paused");
   }
   if(g_breakoutCD > 0) g_breakoutCD--;

   UpdateClosedTradeStats();

   string fr = "";
   g_filtersOK  = FiltersOK(fr);
   g_lastFilter = fr;

   if(CountOpenPositions() >= InpMaxOpenTrades)
   {
      g_lastSignal = SIG_NONE;
      DashboardUpdate();
      return;
   }
   if(g_breakoutCD > 0 || !g_filtersOK || !g_range.valid)
   {
      g_lastSignal = SIG_NONE;
      DashboardUpdate();
      return;
   }

   double rsi = 0.0;
   ENUM_SIGNAL sig = EvaluateSignal(rsi);
   g_lastSignal = sig;
   if(sig == SIG_NONE) { DashboardUpdate(); return; }

   double atr = (g_range.atr > 0) ? g_range.atr : 0.0;
   if(atr <= 0) { g_lastFilter = "ATR not ready"; g_filtersOK = false; DashboardUpdate(); return; }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = 0, tp = 0, entry = 0;
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(sig == SIG_BUY)
   {
      entry = ask;
      sl    = g_range.support - InpSlAtrMultiplier * atr;
      double slDist = entry - sl;
      tp    = entry + InpTpRRMultiplier * slDist;
      if(InpTpAtRangeOpposite) tp = MathMin(tp, g_range.resistance - 5 * pt);
   }
   else
   {
      entry = bid;
      sl    = g_range.resistance + InpSlAtrMultiplier * atr;
      double slDist = sl - entry;
      tp    = entry - InpTpRRMultiplier * slDist;
      if(InpTpAtRangeOpposite) tp = MathMax(tp, g_range.support + 5 * pt);
   }

   double slDistPrice = MathAbs(entry - sl);
   double tpDistPrice = MathAbs(tp - entry);
   if(slDistPrice <= 0 || tpDistPrice < slDistPrice * 0.8)
   {
      g_lastFilter = "RR too small"; g_filtersOK = false;
      DashboardUpdate(); return;
   }

   double lots = CalcLotByRisk(slDistPrice);
   if(lots <= 0)
   {
      g_lastFilter = "Lot calc failed"; g_filtersOK = false;
      DashboardUpdate(); return;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   string cmt = StringFormat("%s_%s_RSI%.0f_ADX%.0f", InpTradeComment,
                             (sig == SIG_BUY ? "B":"S"), rsi, g_range.adx);
   ENUM_ORDER_TYPE otype = (sig == SIG_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OpenTrade(otype, lots, sl, tp, cmt))
      DrawEntry(otype, entry, sl, tp);

   DashboardUpdate();
}

//+------------------------------------------------------------------+
