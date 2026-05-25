//+------------------------------------------------------------------+
//|                                XAU_Range_Scalper_Pro_DEBUG.mq5   |
//|                                          Copyright 2026, Antu AI |
//|                                                                  |
//|  DEBUG VERSION - ultra-loose filters + verbose logging.          |
//|  Use this to figure out why no trades are happening.             |
//|  - Almost ALL filters disabled                                   |
//|  - Logs WHY each bar didn't produce a trade                      |
//|  - Stats counter on dashboard: how many bars rejected and why    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antu AI"
#property version   "1.20"
#property strict
#property description "XAU RSP DEBUG - shows why no trades"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//============================== INPUTS ==============================

input group "=== General ==="
input ulong  InpMagic                = 20260525;
input string InpTradeComment          = "XAU_RSP_DBG";
input bool   InpDrawObjects           = true;
input bool   InpShowDashboard         = true;
input bool   InpVerboseLog            = true;     // print on every rejection
input string InpLogFileName           = "XAU_RSP_DEBUG_log.txt";

input group "=== Risk ==="
input double InpRiskPercent           = 1.0;
input double InpMaxDailyLossPercent   = 0;        // OFF
input int    InpMaxOpenTrades         = 1;

input group "=== Range (ULTRA LOOSE) ==="
input int    InpRangeLookback         = 30;
input int    InpMinTouchesPerSide     = 1;        // ultra loose
input int    InpMinTouchSpacing       = 1;        // ultra loose
input double InpTouchTolerancePoints  = 500;      // very wide
input double InpAtrMaxRatio           = 0.99;     // effectively OFF
input bool   InpRequireRangeValid     = false;    // trade even when range invalid

input group "=== Indicators (ULTRA LOOSE) ==="
input int    InpAtrPeriod             = 14;
input int    InpAdxPeriod             = 14;
input double InpAdxMax                = 100.0;    // OFF
input int    InpRsiPeriod             = 14;
input double InpRsiBuyMax             = 50.0;     // very wide
input double InpRsiSellMin            = 50.0;
input bool   InpUseRsiFilter          = false;    // OFF

input group "=== Patterns ==="
input bool   InpRequirePattern        = false;    // OFF -> any S/R touch trades

input group "=== SL / TP ==="
input double InpSlAtrMultiplier       = 1.5;
input double InpTpRRMultiplier        = 1.5;

input group "=== Filters (ALL OFF) ==="
input int    InpSpreadLimitPoints     = 1000;     // huge
input int    InpSlippagePoints        = 50;
input bool   InpUseSessionFilter      = false;
input bool   InpAvoidLondonOpen       = false;
input bool   InpAvoidNYOpen           = false;
input bool   InpUseBreakoutCooldown   = false;

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
   string   reason;
};

//============================== GLOBALS =============================

CTrade         g_trade;
CPositionInfo  g_pos;

int            g_atrHandle = INVALID_HANDLE;
int            g_adxHandle = INVALID_HANDLE;
int            g_rsiHandle = INVALID_HANDLE;

SRange         g_range;
datetime       g_lastBarTime = 0;

// diagnostic counters
int g_barsProcessed     = 0;
int g_barsRangeValid    = 0;
int g_barsNearSR        = 0;
int g_barsPatternOK     = 0;
int g_barsRsiOK         = 0;
int g_barsTradesOpened  = 0;
int g_barsRejectedBy[10]; // by reason index

string LastRejectReason = "";

int g_logHandle = INVALID_HANDLE;

//============================== HELPERS =============================

void Log(const string msg)
{
   Print("[XAU DBG] ", msg);
   if(g_logHandle != INVALID_HANDLE)
   {
      string line = StringFormat("%s | %s\n",
                                 TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                                 msg);
      FileWriteString(g_logHandle, line);
      FileFlush(g_logHandle);
   }
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

double CalcLotByRisk(const double slDist)
{
   if(slDist <= 0) return 0;
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0) return 0;
   double lossPerLot = (slDist / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0;
   return NormalizeLot(riskMoney / lossPerLot);
}

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

//============================== RANGE ===============================

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
   if(CopyHigh(_Symbol, _Period, 1, InpRangeLookback, highs) <= 0) return false;
   if(CopyLow(_Symbol, _Period, 1, InpRangeLookback, lows) <= 0) return false;
   if(CopyClose(_Symbol, _Period, 1, InpRangeLookback, closes) <= 0) return false;

   double resistance = highs[ArrayMaximum(highs, 0, InpRangeLookback)];
   double support    = lows[ArrayMinimum(lows, 0, InpRangeLookback)];
   double width      = resistance - support;
   if(width <= 0) { g_range.reason = "no width"; return false; }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpTouchTolerancePoints * point;

   int sTouch = 0, rTouch = 0;
   for(int i = 0; i < InpRangeLookback; i++)
   {
      if(highs[i] >= resistance - tol) rTouch++;
      if(lows[i]  <= support + tol)    sTouch++;
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
   if(atr <= 0 || (atr / width) > InpAtrMaxRatio)
   {
      g_range.valid = false;
      g_range.reason = StringFormat("ATR/W=%.2f", atr/width);
      return true;
   }
   if(adx > InpAdxMax)
   {
      g_range.valid = false;
      g_range.reason = StringFormat("ADX=%.1f", adx);
      return true;
   }

   g_range.valid = true;
   g_range.reason = "OK";
   return true;
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

//============================== PATTERNS (LOOSE) ====================

bool BullishCandle(double op, double cl) { return cl > op; }
bool BearishCandle(double op, double cl) { return cl < op; }

bool LooseBullishPattern(double o0, double h0, double l0, double c0,
                         double o1, double c1)
{
   // any bullish close near support is enough in DEBUG mode
   if(InpRequirePattern == false) return true;
   bool engulf = (c1 < o1) && (c0 > o0) && (c0 >= o1);
   bool pin    = ((MathMin(o0,c0) - l0) >= MathAbs(c0-o0)) && (c0 > o0);
   return engulf || pin || BullishCandle(o0, c0);
}

bool LooseBearishPattern(double o0, double h0, double l0, double c0,
                         double o1, double c1)
{
   if(InpRequirePattern == false) return true;
   bool engulf = (c1 > o1) && (c0 < o0) && (c0 <= o1);
   bool pin    = ((h0 - MathMax(o0,c0)) >= MathAbs(c0-o0)) && (c0 < o0);
   return engulf || pin || BearishCandle(o0, c0);
}

//============================== SIGNAL ==============================

ENUM_SIGNAL EvaluateSignal(double &outRsi, string &outReason)
{
   outRsi = 0;
   outReason = "";

   if(InpRequireRangeValid && !g_range.valid)
   {
      outReason = "range invalid: " + g_range.reason;
      return SIG_NONE;
   }
   g_barsRangeValid++;

   double o[], h[], l[], c[];
   ArraySetAsSeries(o, true);
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   if(CopyOpen(_Symbol, _Period, 1, 2, o) <= 0)  { outReason = "no open data"; return SIG_NONE; }
   if(CopyHigh(_Symbol, _Period, 1, 2, h) <= 0)  { outReason = "no high data"; return SIG_NONE; }
   if(CopyLow(_Symbol, _Period, 1, 2, l) <= 0)   { outReason = "no low data"; return SIG_NONE; }
   if(CopyClose(_Symbol, _Period, 1, 2, c) <= 0) { outReason = "no close data"; return SIG_NONE; }

   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);
   if(CopyBuffer(g_rsiHandle, 0, 1, 1, rsiBuf) <= 0) { outReason = "no rsi data"; return SIG_NONE; }
   double rsiNow = rsiBuf[0];
   outRsi = rsiNow;

   bool nearSup = NearSupport(l[0]);
   bool nearRes = NearResistance(h[0]);

   if(!nearSup && !nearRes)
   {
      outReason = StringFormat("not near S/R: H=%.2f L=%.2f Sup=%.2f Res=%.2f",
                                h[0], l[0], g_range.support, g_range.resistance);
      return SIG_NONE;
   }
   g_barsNearSR++;

   if(nearSup)
   {
      bool patternOK = LooseBullishPattern(o[0], h[0], l[0], c[0], o[1], c[1]);
      bool rsiOK     = (!InpUseRsiFilter) || (rsiNow <= InpRsiBuyMax);
      if(!patternOK) { outReason = "BUY: no bullish pattern"; return SIG_NONE; }
      g_barsPatternOK++;
      if(!rsiOK)     { outReason = StringFormat("BUY: rsi=%.1f > %.1f", rsiNow, InpRsiBuyMax); return SIG_NONE; }
      g_barsRsiOK++;
      return SIG_BUY;
   }

   if(nearRes)
   {
      bool patternOK = LooseBearishPattern(o[0], h[0], l[0], c[0], o[1], c[1]);
      bool rsiOK     = (!InpUseRsiFilter) || (rsiNow >= InpRsiSellMin);
      if(!patternOK) { outReason = "SELL: no bearish pattern"; return SIG_NONE; }
      g_barsPatternOK++;
      if(!rsiOK)     { outReason = StringFormat("SELL: rsi=%.1f < %.1f", rsiNow, InpRsiSellMin); return SIG_NONE; }
      g_barsRsiOK++;
      return SIG_SELL;
   }
   return SIG_NONE;
}

//============================== DASHBOARD ===========================

void DrawLabel(int line, const string title, const string value, color clr)
{
   string name = StringFormat("XRSP_DBG_L%02d", line);
   string text = StringFormat("%-12s : %s", title, value);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20 + line * 16);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   int L = 0;
   DrawLabel(L++, "XAU DEBUG", _Symbol, clrGold);
   DrawLabel(L++, "Range",
             g_range.valid
                ? StringFormat("S=%.2f R=%.2f W=%.2f", g_range.support, g_range.resistance, g_range.width)
                : StringFormat("INVALID (%s)", g_range.reason),
             g_range.valid ? clrLime : clrOrangeRed);
   DrawLabel(L++, "Touches",
             StringFormat("S=%d R=%d ATR=%.2f ADX=%.1f",
                          g_range.supportTouches, g_range.resistanceTouches,
                          g_range.atr, g_range.adx),
             clrWhite);
   DrawLabel(L++, "Bars Proc.", StringFormat("%d", g_barsProcessed), clrWhite);
   DrawLabel(L++, "Range Valid", StringFormat("%d (%.1f%%)",
             g_barsRangeValid,
             g_barsProcessed > 0 ? 100.0*g_barsRangeValid/g_barsProcessed : 0),
             clrWhite);
   DrawLabel(L++, "Near S/R", StringFormat("%d", g_barsNearSR), clrWhite);
   DrawLabel(L++, "Pattern OK", StringFormat("%d", g_barsPatternOK), clrWhite);
   DrawLabel(L++, "RSI OK", StringFormat("%d", g_barsRsiOK), clrWhite);
   DrawLabel(L++, "Trades", StringFormat("%d", g_barsTradesOpened), clrLime);
   DrawLabel(L++, "Last Reject", LastRejectReason, clrOrange);
   DrawLabel(L++, "Spread",
             StringFormat("%d pts", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)),
             clrWhite);
}

//============================== ONINIT ==============================

int OnInit()
{
   g_atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   g_adxHandle = iADX(_Symbol, _Period, InpAdxPeriod);
   g_rsiHandle = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   if(g_atrHandle == INVALID_HANDLE ||
      g_adxHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE)
   {
      Print("Indicator init failed");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_logHandle = FileOpen(InpLogFileName,
                          FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON|FILE_SHARE_READ);
   if(g_logHandle != INVALID_HANDLE)
   {
      FileSeek(g_logHandle, 0, SEEK_END);
      Log("=== DEBUG EA Started ===");
   }

   Log(StringFormat("Symbol=%s Period=%s Digits=%d Point=%.5f",
                    _Symbol, EnumToString(_Period), _Digits,
                    SymbolInfoDouble(_Symbol, SYMBOL_POINT)));
   Log(StringFormat("MinLot=%.2f StepLot=%.2f Spread=%d",
                    SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                    SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
                    (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_logHandle != INVALID_HANDLE)
   {
      Log(StringFormat("=== STATS: bars=%d rangeValid=%d nearSR=%d patternOK=%d rsiOK=%d trades=%d ===",
                       g_barsProcessed, g_barsRangeValid, g_barsNearSR,
                       g_barsPatternOK, g_barsRsiOK, g_barsTradesOpened));
      FileClose(g_logHandle);
   }
   ObjectsDeleteAll(0, "XRSP_DBG_");
}

//============================== ONTICK ==============================

void OnTick()
{
   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime) { UpdateDashboard(); return; }
   g_lastBarTime = curBarTime;

   g_barsProcessed++;

   RangeUpdate();

   if(CountOpenPositions() >= InpMaxOpenTrades)
   {
      LastRejectReason = "max trades open";
      UpdateDashboard();
      return;
   }

   double rsi = 0;
   string reason = "";
   ENUM_SIGNAL sig = EvaluateSignal(rsi, reason);

   if(sig == SIG_NONE)
   {
      LastRejectReason = reason;
      if(InpVerboseLog && g_barsProcessed % 50 == 0)
         Log(StringFormat("Bar #%d: %s | range=%s",
                          g_barsProcessed, reason, g_range.reason));
      UpdateDashboard();
      return;
   }

   double atr = g_range.atr;
   if(atr <= 0)
   {
      LastRejectReason = "atr=0";
      UpdateDashboard();
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl, tp, entry;

   if(sig == SIG_BUY)
   {
      entry = ask;
      sl = entry - InpSlAtrMultiplier * atr;
      tp = entry + InpTpRRMultiplier * (entry - sl);
   }
   else
   {
      entry = bid;
      sl = entry + InpSlAtrMultiplier * atr;
      tp = entry - InpTpRRMultiplier * (sl - entry);
   }

   double slDist = MathAbs(entry - sl);
   double lots = CalcLotByRisk(slDist);
   if(lots <= 0)
   {
      LastRejectReason = "lots=0";
      Log(StringFormat("Lot calc failed: slDist=%.5f tickSize=%.5f tickValue=%.5f",
                       slDist,
                       SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                       SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)));
      UpdateDashboard();
      return;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool ok = (sig == SIG_BUY)
             ? g_trade.Buy(lots, _Symbol, entry, sl, tp, InpTradeComment)
             : g_trade.Sell(lots, _Symbol, entry, sl, tp, InpTradeComment);

   if(ok)
   {
      g_barsTradesOpened++;
      Log(StringFormat("OPEN %s lots=%.2f entry=%.2f sl=%.2f tp=%.2f rsi=%.1f",
                       (sig == SIG_BUY ? "BUY":"SELL"), lots, entry, sl, tp, rsi));
   }
   else
   {
      LastRejectReason = StringFormat("trade fail err=%d", g_trade.ResultRetcode());
      Log(StringFormat("OPEN FAIL err=%d %s",
                       g_trade.ResultRetcode(),
                       g_trade.ResultRetcodeDescription()));
   }

   UpdateDashboard();
}

void OnTrade() {}
//+------------------------------------------------------------------+
