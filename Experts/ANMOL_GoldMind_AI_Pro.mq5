//+------------------------------------------------------------------+
//|                       ANMOL GOLDMIND AI Pro - MT5 EA             |
//|                                       Copyright "Antu Trading"   |
//|     Professional Supply/Demand + News EA with full DD control    |
//|                       v4.30 - Tuned defaults, fast backtest      |
//+------------------------------------------------------------------+
#property copyright "Antu Trading"
#property link      "https://github.com/amolrasal2004-ctrl/Antu_ai"
#property version   "4.30"
#property strict
#property description "ANMOL GOLDMIND AI Pro - Supply/Demand + News Reversal"
#property description "Tuned defaults: NEXT_BAR confirm + wick rej + RSI + H1 trend"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade         trade;
CPositionInfo  pos;
CSymbolInfo    sym;
CAccountInfo   acc;

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_NEWS_MODE
{
   NEWS_OFF      = 0,   // OFF - ignore news
   NEWS_BOOST    = 1,   // BOOST - take reversal trades after news spike
   NEWS_BLOCK    = 2    // BLOCK - skip trading in news window
};

enum ENUM_SL_MODE
{
   SL_FIXED_BUFFER = 0, // Fixed buffer (points beyond pivot)
   SL_ATR_DYNAMIC  = 1  // ATR-based dynamic SL
};

enum ENUM_CONFIRM_MODE
{
   CONFIRM_OFF       = 0, // OFF - immediate (early entries)
   CONFIRM_NEXT_BAR  = 1, // Wait 1 bar confirm (RECOMMENDED)
   CONFIRM_BOS       = 2, // Break of structure
   CONFIRM_STRICT    = 3  // BOTH next-bar + BOS (safest)
};

//+------------------------------------------------------------------+
//| INPUTS - all defaults are TUNED for XAUUSD M5                    |
//+------------------------------------------------------------------+
input group "=== STRATEGY ==="
input ENUM_TIMEFRAMES InpTF          = PERIOD_M5;     // Timeframe
input int      InpPivotLength        = 15;            // Pivot length
input ENUM_SL_MODE InpSLMode         = SL_FIXED_BUFFER;// Stop loss mode
input double   InpSLBufferPts        = 200.0;         // SL buffer (points) - fixed
input double   InpATRMultSL          = 1.5;           // ATR multiplier for SL
input double   InpMinRR              = 1.5;           // Min R:R required

input group "=== SIGNAL CONFIRMATION (anti-fake-signal) ==="
input ENUM_CONFIRM_MODE InpConfirmMode = CONFIRM_NEXT_BAR; // Confirmation mode
input bool     InpRequireWickRej     = true;          // Require wick rejection
input double   InpMinWickRatio       = 40.0;          // Min wick % of range
input double   InpMinBodyRatio       = 30.0;          // Min body % of range
input bool     InpRequireEngulf      = false;         // Require engulfing
input bool     InpUseRSIFilter       = true;          // RSI momentum filter
input int      InpRSIPeriod          = 14;            // RSI period
input double   InpRSIBuyMax          = 35.0;          // RSI <= for BUY (oversold)
input double   InpRSISellMin         = 65.0;          // RSI >= for SELL (overbought)
input bool     InpUseTrendFilter     = true;          // HTF EMA trend filter
input ENUM_TIMEFRAMES InpTrendTF     = PERIOD_H1;     // Trend timeframe
input int      InpTrendEMA           = 50;            // Trend EMA period
input double   InpZoneTolerancePts   = 50.0;          // Zone tap tolerance (pts)

input group "=== RISK MANAGEMENT ==="
input bool     InpAutoLot            = true;          // Auto lot from risk %
input double   InpRiskPercent        = 1.0;           // Risk % per trade
input double   InpFixedLot           = 0.01;          // Fixed lot
input double   InpMaxLot             = 1.00;          // Hard lot cap
input int      InpMaxOpenPositions   = 1;             // Max concurrent positions

input group "=== DRAWDOWN PROTECTION ==="
input bool     InpUseDailyLoss       = true;          // Daily loss lock
input double   InpMaxDailyLossPct    = 3.0;           // Max daily loss %
input bool     InpUseEquityDD        = true;          // Equity DD lock
input double   InpMaxEquityDDPct     = 8.0;           // Max equity DD %
input bool     InpCloseAllOnDDLock   = true;          // Close all on lock
input int      InpMaxLossesPerDay    = 4;             // Stop after N losses (0=off)
input int      InpCooldownAfterLossM = 30;            // Cooldown minutes

input group "=== TRAILING & BREAKEVEN ==="
input bool     InpUseTrailing        = true;          // Trailing stop
input double   InpBreakevenAtPts     = 100.0;         // BE at X pts profit
input double   InpBreakevenLockPts   = 10.0;          // BE lock pts
input double   InpTrailStartPts      = 150.0;         // Trail start pts
input double   InpTrailStepPts       = 50.0;          // Trail step pts

input group "=== PARTIAL PROFIT ==="
input bool     InpUsePartial         = true;          // Partial close
input double   InpP1Pts              = 150.0;         // 1st partial trigger
input double   InpP1Pct              = 40.0;          // 1st partial %
input double   InpP2Pts              = 300.0;         // 2nd partial trigger
input double   InpP2Pct              = 30.0;          // 2nd partial %

input group "=== FILTERS ==="
input double   InpMaxSpreadPts       = 50.0;          // Max spread (pts)
input bool     InpUseSessionFilter   = false;         // Session hours
input int      InpSessionStartHour   = 7;             // Start hour
input int      InpSessionEndHour     = 22;            // End hour
input bool     InpFridayCloseEarly   = true;          // Friday close
input int      InpFridayCloseHour    = 21;            // Friday close hour

input group "=== NEWS ==="
input ENUM_NEWS_MODE InpNewsMode     = NEWS_BLOCK;    // News mode (BLOCK is safer)
input double   InpATRMultSpike       = 2.0;           // ATR x for spike
input string   InpNewsTime1          = "08:30";       // News 1
input string   InpNewsTime2          = "14:00";       // News 2
input string   InpNewsTime3          = "15:00";       // News 3
input string   InpNewsTime4          = "18:30";       // News 4
input int      InpNewsWindowMin      = 15;            // Window minutes

input group "=== DASHBOARD & ALERTS ==="
input bool     InpShowDashboard      = true;          // Show dashboard (live only)
input bool     InpShowZones          = true;          // Draw zones (live only)
input bool     InpAlertPopup         = false;         // Popup (slow in tester)
input bool     InpAlertPush          = false;         // Push notif
input bool     InpAlertSound         = false;         // Sound
input color    InpClrBg              = clrBlack;
input color    InpClrText            = clrWhite;
input color    InpClrBuy             = clrLime;
input color    InpClrSell            = clrRed;
input color    InpClrWarn            = clrGold;
input color    InpClrSupply          = clrCrimson;
input color    InpClrDemand          = clrSeaGreen;

input group "=== GENERAL ==="
input long     InpMagic              = 202604;        // Magic number
input string   InpComment            = "ANMOL_GMIND"; // Trade comment
input bool     InpDebugLog           = false;         // Debug log (off for speed!)

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
const string PFX = "AGM_";

double   g_supplyTop = 0, g_supplyBot = 0;
double   g_demandTop = 0, g_demandBot = 0;

int      g_atrHandle = INVALID_HANDLE;
int      g_rsiHandle = INVALID_HANDLE;
int      g_emaHandle = INVALID_HANDLE;

string   g_lastSignal = "WAITING";
double   g_lastEntry = 0, g_lastSL = 0, g_lastTP = 0, g_lastRR = 0;
bool     g_newsBoost = false;
datetime g_lastBar   = 0;

double   g_dayStartBalance = 0;
datetime g_currentDay      = 0;
double   g_equityPeak      = 0;
bool     g_ddLocked        = false;
string   g_ddLockReason    = "";
int      g_lossesToday     = 0;
datetime g_lastLossTime    = 0;

int      g_totalTrades = 0, g_wins = 0, g_losses = 0;
double   g_grossProfit = 0, g_grossLoss = 0;

ulong    g_p1Tickets[];
ulong    g_p2Tickets[];

bool     g_isTester = false;          // skip dashboard/visuals when true
int      g_dashboardCounter = 0;      // throttle dashboard updates

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_isTester = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);

   if(!sym.Name(_Symbol)) { Print("Symbol init failed"); return INIT_FAILED; }
   sym.Refresh();
   sym.RefreshRates();

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);

   long fmode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fmode & SYMBOL_FILLING_FOK) != 0)        trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fmode & SYMBOL_FILLING_IOC) != 0)   trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                         trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_atrHandle = iATR(_Symbol, InpTF, 14);
   if(g_atrHandle == INVALID_HANDLE) { Print("ATR handle failed"); return INIT_FAILED; }

   if(InpUseRSIFilter)
   {
      g_rsiHandle = iRSI(_Symbol, InpTF, InpRSIPeriod, PRICE_CLOSE);
      if(g_rsiHandle == INVALID_HANDLE) { Print("RSI handle failed"); return INIT_FAILED; }
   }
   if(InpUseTrendFilter && InpTrendEMA > 0)
   {
      g_emaHandle = iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaHandle == INVALID_HANDLE) { Print("EMA handle failed"); return INIT_FAILED; }
   }

   ResetDay(true);
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);

   // Build dashboard only when not in tester (saves backtest time)
   if(InpShowDashboard && !g_isTester) BuildDashboard();

   PrintFormat("=== ANMOL GOLDMIND AI Pro v4.30 | %s %s | Magic:%I64d | Tester:%s ===",
               _Symbol, EnumToString(InpTF), InpMagic, g_isTester ? "YES" : "NO");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_emaHandle != INVALID_HANDLE) IndicatorRelease(g_emaHandle);
   if(!g_isTester) ObjectsDeleteAll(0, PFX);
   Comment("");
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   sym.RefreshRates();

   RolloverDayIfNeeded();
   UpdateEquityPeak();
   CheckDrawdownLocks();

   bool havePos = (CountOurPositions() > 0);

   if(havePos)
   {
      ManagePartial();
      ManageTrailing();
   }

   if(InpFridayCloseEarly && IsFridayCloseTime() && havePos)
      CloseAllOurPositions("Friday close");

   // Dashboard: live only, throttled to every 30 ticks for performance
   if(InpShowDashboard && !g_isTester)
   {
      if(++g_dashboardCounter >= 30) { g_dashboardCounter = 0; UpdateDashboard(); }
   }

   // entry guards
   if(g_ddLocked) return;
   if(!IsTradingAllowed()) return;
   if(havePos && CountOurPositions() >= InpMaxOpenPositions) return;
   if(InCooldown()) return;
   if(InpUseSessionFilter && !InSession()) return;
   if(InpNewsMode == NEWS_BLOCK && IsNewsTime()) return;
   if(GetSpreadPts() > InpMaxSpreadPts) return;

   // new bar gate (single-shot per candle)
   datetime curBar = iTime(_Symbol, InpTF, 0);
   if(curBar == g_lastBar) return;
   g_lastBar = curBar;

   UpdateZones();
   if(InpShowZones && !g_isTester) DrawZones();
   if(g_supplyTop <= 0 || g_demandBot <= 0) return;

   TryEntries();
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION (stats + cooldown)                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &t,
                        const MqlTradeRequest    &req,
                        const MqlTradeResult     &res)
{
   if(t.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(t.deal)) return;
   if((long)HistoryDealGetInteger(t.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(t.deal, DEAL_SYMBOL) != _Symbol)        return;

   long entry = HistoryDealGetInteger(t.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

   double profit = HistoryDealGetDouble(t.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(t.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(t.deal, DEAL_COMMISSION);

   g_totalTrades++;
   if(profit >= 0) { g_wins++; g_grossProfit += profit; }
   else { g_losses++; g_grossLoss += -profit; g_lossesToday++; g_lastLossTime = TimeCurrent(); }
}

//+------------------------------------------------------------------+
//| ZONE DETECTION                                                   |
//+------------------------------------------------------------------+
double GetPivotHigh(int length)
{
   int need = length * 2 + 2;
   double h[];
   ArraySetAsSeries(h, true);
   if(CopyHigh(_Symbol, InpTF, 0, need, h) < need) return 0;
   int mid = length + 1;
   double pv = h[mid];
   for(int i = 1; i <= length; i++)
   {
      if(h[mid - i] >= pv) return 0;
      if(h[mid + i] >= pv) return 0;
   }
   return pv;
}

double GetPivotLow(int length)
{
   int need = length * 2 + 2;
   double l[];
   ArraySetAsSeries(l, true);
   if(CopyLow(_Symbol, InpTF, 0, need, l) < need) return 0;
   int mid = length + 1;
   double pv = l[mid];
   for(int i = 1; i <= length; i++)
   {
      if(l[mid - i] <= pv) return 0;
      if(l[mid + i] <= pv) return 0;
   }
   return pv;
}

void UpdateZones()
{
   double ph = GetPivotHigh(InpPivotLength);
   if(ph > 0)
   {
      double c[], o[];
      ArraySetAsSeries(c, true); ArraySetAsSeries(o, true);
      if(CopyClose(_Symbol, InpTF, InpPivotLength + 1, 1, c) == 1 &&
         CopyOpen (_Symbol, InpTF, InpPivotLength + 1, 1, o) == 1)
      {
         g_supplyTop = ph;
         g_supplyBot = MathMax(c[0], o[0]);
      }
   }
   double pl = GetPivotLow(InpPivotLength);
   if(pl > 0)
   {
      double c[], o[];
      ArraySetAsSeries(c, true); ArraySetAsSeries(o, true);
      if(CopyClose(_Symbol, InpTF, InpPivotLength + 1, 1, c) == 1 &&
         CopyOpen (_Symbol, InpTF, InpPivotLength + 1, 1, o) == 1)
      {
         g_demandBot = pl;
         g_demandTop = MathMin(c[0], o[0]);
      }
   }
}

//+------------------------------------------------------------------+
//| TIME / SESSION HELPERS                                           |
//+------------------------------------------------------------------+
bool InSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
}

bool IsFridayCloseTime()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour);
}

bool IsNewsTime()
{
   if(InpNewsMode == NEWS_OFF) return false;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int cur = dt.hour * 60 + dt.min;
   string times[4] = {InpNewsTime1, InpNewsTime2, InpNewsTime3, InpNewsTime4};
   for(int i = 0; i < 4; i++)
   {
      if(StringLen(times[i]) < 5) continue;
      int h = (int)StringToInteger(StringSubstr(times[i], 0, 2));
      int m = (int)StringToInteger(StringSubstr(times[i], 3, 2));
      if(MathAbs(cur - (h * 60 + m)) <= InpNewsWindowMin) return true;
   }
   return false;
}

bool IsNewsSpike(int shift)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_atrHandle, 0, shift, 1, atr) < 1) return false;
   double o[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if(CopyOpen (_Symbol, InpTF, shift, 1, o) < 1) return false;
   if(CopyClose(_Symbol, InpTF, shift, 1, c) < 1) return false;
   return MathAbs(c[0] - o[0]) >= (atr[0] * InpATRMultSpike);
}

double GetATR(int shift)
{
   double a[]; ArraySetAsSeries(a, true);
   if(CopyBuffer(g_atrHandle, 0, shift, 1, a) < 1) return 0;
   return a[0];
}

double GetRSI(int shift)
{
   if(g_rsiHandle == INVALID_HANDLE) return 50.0;
   double r[]; ArraySetAsSeries(r, true);
   if(CopyBuffer(g_rsiHandle, 0, shift, 1, r) < 1) return 50.0;
   return r[0];
}

double GetEMA(int shift)
{
   if(g_emaHandle == INVALID_HANDLE) return 0;
   double e[]; ArraySetAsSeries(e, true);
   if(CopyBuffer(g_emaHandle, 0, shift, 1, e) < 1) return 0;
   return e[0];
}

//+------------------------------------------------------------------+
//| CANDLE PATTERNS                                                  |
//+------------------------------------------------------------------+
double CandleRange(double h, double l) { return MathMax(h - l, _Point); }
double CandleBody(double o, double c)  { return MathAbs(c - o); }
double UpperWick(double h, double o, double c) { return h - MathMax(o, c); }
double LowerWick(double l, double o, double c) { return MathMin(o, c) - l; }

bool IsBullishRejection(double o, double c, double h, double l, double zoneTop, double zoneBot)
{
   double rng = CandleRange(h, l), body = CandleBody(o, c), lwk = LowerWick(l, o, c);
   bool wickOk = (lwk / rng * 100.0) >= InpMinWickRatio;
   bool bodyOk = (body / rng * 100.0) >= InpMinBodyRatio;
   bool bullClose = c > o;
   bool wickedZone = l <= zoneTop;
   bool closedAbove = c > zoneBot;
   if(InpRequireWickRej) return wickOk && bodyOk && bullClose && wickedZone && closedAbove;
   return bodyOk && bullClose && wickedZone;
}

bool IsBearishRejection(double o, double c, double h, double l, double zoneTop, double zoneBot)
{
   double rng = CandleRange(h, l), body = CandleBody(o, c), uwk = UpperWick(h, o, c);
   bool wickOk = (uwk / rng * 100.0) >= InpMinWickRatio;
   bool bodyOk = (body / rng * 100.0) >= InpMinBodyRatio;
   bool bearClose = c < o;
   bool wickedZone = h >= zoneBot;
   bool closedBelow = c < zoneTop;
   if(InpRequireWickRej) return wickOk && bodyOk && bearClose && wickedZone && closedBelow;
   return bodyOk && bearClose && wickedZone;
}

bool IsBullEngulf(double o1, double c1, double o2, double c2)
{ return (c2 < o2) && (c1 > o1) && (c1 >= o2) && (o1 <= c2); }

bool IsBearEngulf(double o1, double c1, double o2, double c2)
{ return (c2 > o2) && (c1 < o1) && (c1 <= o2) && (o1 >= c2); }

bool BullishBOS(int signalShift)
{
   double h[], l[], c[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   if(CopyHigh (_Symbol, InpTF, signalShift - 1, 4, h) < 4) return false;
   if(CopyLow  (_Symbol, InpTF, signalShift - 1, 4, l) < 4) return false;
   if(CopyClose(_Symbol, InpTF, signalShift - 1, 1, c) < 1) return false;
   double prevHigh = MathMax(h[1], MathMax(h[2], h[3]));
   return c[0] > prevHigh;
}

bool BearishBOS(int signalShift)
{
   double h[], l[], c[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   if(CopyHigh (_Symbol, InpTF, signalShift - 1, 4, h) < 4) return false;
   if(CopyLow  (_Symbol, InpTF, signalShift - 1, 4, l) < 4) return false;
   if(CopyClose(_Symbol, InpTF, signalShift - 1, 1, c) < 1) return false;
   double prevLow = MathMin(l[1], MathMin(l[2], l[3]));
   return c[0] < prevLow;
}

bool TrendAllowsBuy()
{
   if(!InpUseTrendFilter || InpTrendEMA <= 0) return true;
   double ema = GetEMA(0);
   if(ema <= 0) return true;
   return SymbolInfoDouble(_Symbol, SYMBOL_BID) >= ema;
}

bool TrendAllowsSell()
{
   if(!InpUseTrendFilter || InpTrendEMA <= 0) return true;
   double ema = GetEMA(0);
   if(ema <= 0) return true;
   return SymbolInfoDouble(_Symbol, SYMBOL_BID) <= ema;
}

//+------------------------------------------------------------------+
//| GUARDS                                                           |
//+------------------------------------------------------------------+
double GetSpreadPts() { return (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

bool IsTradingAllowed()
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))            return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))  return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))     return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))    return false;
   return true;
}

bool InCooldown()
{
   if(InpCooldownAfterLossM <= 0)  return false;
   if(g_lastLossTime == 0)         return false;
   return (TimeCurrent() - g_lastLossTime) < (InpCooldownAfterLossM * 60);
}

//+------------------------------------------------------------------+
//| DAILY ROLLOVER & DD LOCK                                         |
//+------------------------------------------------------------------+
void ResetDay(bool firstInit = false)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   g_currentDay = StructToTime(dt);
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lossesToday = 0;
   g_lastLossTime = 0;
}

void RolloverDayIfNeeded()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(today != g_currentDay)
   {
      ResetDay(false);
      g_ddLocked = false;
      g_ddLockReason = "";
   }
}

void UpdateEquityPeak()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_equityPeak) g_equityPeak = eq;
}

void CheckDrawdownLocks()
{
   if(g_ddLocked) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpUseDailyLoss && g_dayStartBalance > 0)
   {
      double dayPnL = eq - g_dayStartBalance;
      double maxLoss = g_dayStartBalance * InpMaxDailyLossPct / 100.0;
      if(dayPnL <= -maxLoss) { LockDD(StringFormat("DAILY LOSS %.2f%%", InpMaxDailyLossPct)); return; }
   }
   if(InpUseEquityDD && g_equityPeak > 0)
   {
      double ddPct = (g_equityPeak - eq) / g_equityPeak * 100.0;
      if(ddPct >= InpMaxEquityDDPct) { LockDD(StringFormat("EQ DD %.2f%%", InpMaxEquityDDPct)); return; }
   }
   if(InpMaxLossesPerDay > 0 && g_lossesToday >= InpMaxLossesPerDay)
   { LockDD(StringFormat("MAX LOSSES %d", InpMaxLossesPerDay)); return; }
}

void LockDD(string reason)
{
   g_ddLocked = true;
   g_ddLockReason = reason;
   PrintFormat("DD LOCK: %s", reason);
   if(InpAlertPopup && !g_isTester) Alert("ANMOL EA LOCKED: ", reason);
   if(InpCloseAllOnDDLock) CloseAllOurPositions(reason);
}

//+------------------------------------------------------------------+
//| POSITION HELPERS                                                 |
//+------------------------------------------------------------------+
int CountOurPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() == InpMagic && pos.Symbol() == _Symbol) n++;
   }
   return n;
}

void CloseAllOurPositions(string why)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != InpMagic || pos.Symbol() != _Symbol) continue;
      ulong tk = pos.Ticket();
      if(trade.PositionClose(tk)) PrintFormat("Closed #%I64u (%s)", tk, why);
   }
}

double NormalizeVolume(double v, double mn, double mx, double step)
{
   if(step <= 0) step = 0.01;
   v = MathFloor(v / step) * step;
   if(v < mn) v = mn;
   if(v > mx) v = mx;
   return NormalizeDouble(v, 2);
}

double CalcLot(double slPoints)
{
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double cap = MathMin(volMax, InpMaxLot);
   if(!InpAutoLot || slPoints <= 0)
      return NormalizeVolume(InpFixedLot, volMin, cap, volStep);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * InpRiskPercent / 100.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tv <= 0 || ts <= 0 || pt <= 0) return volMin;
   double pvpl = tv * (pt / ts);
   if(pvpl <= 0) return volMin;
   double lots = risk / (slPoints * pvpl);
   return NormalizeVolume(lots, volMin, cap, volStep);
}

//+------------------------------------------------------------------+
//| ENTRY LOGIC                                                      |
//+------------------------------------------------------------------+
void TryEntries()
{
   double c[], o[], h[], l[];
   ArraySetAsSeries(c, true); ArraySetAsSeries(o, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if(CopyClose(_Symbol, InpTF, 0, 6, c) < 6) return;
   if(CopyOpen (_Symbol, InpTF, 0, 6, o) < 6) return;
   if(CopyHigh (_Symbol, InpTF, 0, 6, h) < 6) return;
   if(CopyLow  (_Symbol, InpTF, 0, 6, l) < 6) return;

   bool needConfirmBar = (InpConfirmMode == CONFIRM_NEXT_BAR || InpConfirmMode == CONFIRM_STRICT);
   bool needBOS        = (InpConfirmMode == CONFIRM_BOS      || InpConfirmMode == CONFIRM_STRICT);
   int  sigIdx         = needConfirmBar ? 2 : 1;
   int  confIdx        = 1;

   double oS = o[sigIdx], cS = c[sigIdx], hS = h[sigIdx], lS = l[sigIdx];
   double oP = o[sigIdx + 1], cP = c[sigIdx + 1];
   double oC = o[confIdx], cC = c[confIdx];

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tol   = InpZoneTolerancePts * point;

   bool tappedSupply = (hS >= g_supplyBot - tol) && (cS <= g_supplyTop + tol);
   bool tappedDemand = (lS <= g_demandTop + tol) && (cS >= g_demandBot - tol);

   bool bearRej = IsBearishRejection(oS, cS, hS, lS, g_supplyTop, g_supplyBot);
   bool bullRej = IsBullishRejection(oS, cS, hS, lS, g_demandTop, g_demandBot);

   bool engulfBuy  = !InpRequireEngulf || IsBullEngulf(oS, cS, oP, cP);
   bool engulfSell = !InpRequireEngulf || IsBearEngulf(oS, cS, oP, cP);

   bool confBuy   = !needConfirmBar || (cC > oC && cC > cS);
   bool confSell  = !needConfirmBar || (cC < oC && cC < cS);

   bool bosBuy    = !needBOS || BullishBOS(sigIdx);
   bool bosSell   = !needBOS || BearishBOS(sigIdx);

   double rsi = (InpUseRSIFilter ? GetRSI(sigIdx) : 50.0);
   bool rsiBuy  = !InpUseRSIFilter || rsi <= InpRSIBuyMax;
   bool rsiSell = !InpUseRSIFilter || rsi >= InpRSISellMin;

   bool trendBuy  = TrendAllowsBuy();
   bool trendSell = TrendAllowsSell();

   bool spikeBull = (InpNewsMode == NEWS_BOOST) && IsNewsSpike(sigIdx + 1) && (cP > oP);
   bool spikeBear = (InpNewsMode == NEWS_BOOST) && IsNewsSpike(sigIdx + 1) && (cP < oP);
   bool timeOk    = IsNewsTime();

   bool sellSig = tappedSupply && bearRej && engulfSell && confSell && bosSell && rsiSell && trendSell;
   bool buySig  = tappedDemand && bullRej && engulfBuy  && confBuy  && bosBuy  && rsiBuy  && trendBuy;

   // Optional debug log (only when enabled, only on tap, only once per bar)
   if(InpDebugLog && (tappedSupply || tappedDemand))
   {
      PrintFormat("[DBG] tapS=%d tapD=%d bearRej=%d bullRej=%d cnfB=%d cnfS=%d bosB=%d bosS=%d rsi=%.1f rsiB=%d rsiS=%d trB=%d trS=%d -> SELL=%d BUY=%d",
                  tappedSupply, tappedDemand, bearRej, bullRej,
                  confBuy, confSell, bosBuy, bosSell,
                  rsi, rsiBuy, rsiSell, trendBuy, trendSell,
                  sellSig, buySig);
   }

   bool isNewsSell = sellSig && spikeBull && timeOk;
   bool isNewsBuy  = buySig  && spikeBear && timeOk;

   if(sellSig)
   {
      double pivotHigh = MathMax(hS, h[sigIdx + 1]);
      ExecuteSell(pivotHigh, isNewsSell);
   }
   else if(buySig)
   {
      double pivotLow = MathMin(lS, l[sigIdx + 1]);
      ExecuteBuy(pivotLow, isNewsBuy);
   }
}

double ComputeSL(bool isBuy, double pivotPrice)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(InpSLMode == SL_FIXED_BUFFER)
   {
      return isBuy ? pivotPrice - InpSLBufferPts * point
                   : pivotPrice + InpSLBufferPts * point;
   }
   double atr = GetATR(1);
   if(atr <= 0) atr = InpSLBufferPts * point;
   return isBuy ? pivotPrice - atr * InpATRMultSL
                : pivotPrice + atr * InpATRMultSL;
}

bool ValidStopDistance(bool isBuy, double entry, double sl, double tp)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLvl * point;
   if(isBuy)
   {
      if((entry - sl) < minDist) return false;
      if((tp - entry) < minDist) return false;
   }
   else
   {
      if((sl - entry) < minDist) return false;
      if((entry - tp) < minDist) return false;
   }
   return true;
}

void ExecuteSell(double pivotHigh, bool isNews)
{
   sym.RefreshRates();
   double entry = sym.Bid();
   double sl    = NormalizeDouble(ComputeSL(false, pivotHigh), _Digits);
   double tp    = NormalizeDouble(g_demandTop, _Digits);
   double pt    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPts = (sl - entry) / pt;
   double tpPts = (entry - tp) / pt;
   if(slPts <= 0 || tpPts <= 0) return;
   if(!ValidStopDistance(false, entry, sl, tp)) return;
   double rr = tpPts / slPts;
   if(rr < InpMinRR) return;
   double lots = CalcLot(slPts);
   string cmt = InpComment + (isNews ? "_SELL_N" : "_SELL");
   if(trade.Sell(lots, _Symbol, entry, sl, tp, cmt))
   {
      RegisterEntry("SELL", entry, sl, tp, rr, isNews);
      AnnounceEntry("SELL", entry, sl, tp, rr, lots, isNews);
   }
}

void ExecuteBuy(double pivotLow, bool isNews)
{
   sym.RefreshRates();
   double entry = sym.Ask();
   double sl    = NormalizeDouble(ComputeSL(true, pivotLow), _Digits);
   double tp    = NormalizeDouble(g_supplyTop, _Digits);
   double pt    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPts = (entry - sl) / pt;
   double tpPts = (tp - entry) / pt;
   if(slPts <= 0 || tpPts <= 0) return;
   if(!ValidStopDistance(true, entry, sl, tp)) return;
   double rr = tpPts / slPts;
   if(rr < InpMinRR) return;
   double lots = CalcLot(slPts);
   string cmt = InpComment + (isNews ? "_BUY_N" : "_BUY");
   if(trade.Buy(lots, _Symbol, entry, sl, tp, cmt))
   {
      RegisterEntry("BUY", entry, sl, tp, rr, isNews);
      AnnounceEntry("BUY", entry, sl, tp, rr, lots, isNews);
   }
}

void RegisterEntry(string sig, double entry, double sl, double tp, double rr, bool isNews)
{
   g_lastSignal = sig;
   g_lastEntry  = entry; g_lastSL = sl; g_lastTP = tp; g_lastRR = rr;
   g_newsBoost  = isNews;
}

void AnnounceEntry(string sig, double entry, double sl, double tp, double rr, double lots, bool isNews)
{
   string msg = StringFormat("ANMOL %s | %s @ %.*f SL %.*f TP %.*f RR 1:%.2f Lots %.2f%s",
                             sig, _Symbol, _Digits, entry, _Digits, sl, _Digits, tp,
                             rr, lots, isNews ? " [NEWS]" : "");
   Print(msg);
   if(g_isTester) return;          // skip alerts in tester for speed
   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertSound) PlaySound("alert.wav");
}

//+------------------------------------------------------------------+
//| TRAILING + BE                                                    |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   if(!InpUseTrailing) return;
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist = MathMax(stopLvl, freeze) * pt;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != InpMagic || pos.Symbol() != _Symbol) continue;
      ulong ticket = pos.Ticket();
      double open  = pos.PriceOpen();
      double curSL = pos.StopLoss();
      double curTP = pos.TakeProfit();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = curSL;

      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         double profPts = (bid - open) / pt;
         if(profPts >= InpBreakevenAtPts && (curSL < open + InpBreakevenLockPts * pt))
            newSL = open + InpBreakevenLockPts * pt;
         if(profPts >= InpTrailStartPts)
         {
            double trail = bid - InpTrailStepPts * pt;
            if(trail > newSL) newSL = trail;
         }
         if(newSL > curSL && (bid - newSL) >= minDist)
            SafeModify(ticket, newSL, curTP);
      }
      else
      {
         double profPts = (open - ask) / pt;
         if(profPts >= InpBreakevenAtPts && (curSL == 0 || curSL > open - InpBreakevenLockPts * pt))
            newSL = open - InpBreakevenLockPts * pt;
         if(profPts >= InpTrailStartPts)
         {
            double trail = ask + InpTrailStepPts * pt;
            if(curSL == 0 || trail < newSL || newSL == curSL) newSL = trail;
         }
         if((curSL == 0 || newSL < curSL) && (newSL - ask) >= minDist)
            SafeModify(ticket, newSL, curTP);
      }
   }
}

void SafeModify(ulong ticket, double newSL, double curTP)
{
   newSL = NormalizeDouble(newSL, _Digits);
   if(!trade.PositionModify(ticket, newSL, curTP))
   {
      uint err = trade.ResultRetcode();
      if(err != TRADE_RETCODE_NO_CHANGES && !g_isTester)
         PrintFormat("Modify fail #%I64u rc=%u", ticket, err);
   }
}

//+------------------------------------------------------------------+
//| PARTIAL PROFIT                                                   |
//+------------------------------------------------------------------+
bool TicketArrayHas(ulong &arr[], ulong tk)
{
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++) if(arr[i] == tk) return true;
   return false;
}

void TicketArrayAdd(ulong &arr[], ulong tk)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = tk;
}

void PruneClosedTickets()
{
   ulong open[]; ArrayResize(open, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() == InpMagic && pos.Symbol() == _Symbol)
         TicketArrayAdd(open, pos.Ticket());
   }
   ulong tmp1[]; ArrayResize(tmp1, 0);
   int s1 = ArraySize(g_p1Tickets);
   for(int i = 0; i < s1; i++)
      if(TicketArrayHas(open, g_p1Tickets[i])) TicketArrayAdd(tmp1, g_p1Tickets[i]);
   ArrayFree(g_p1Tickets);
   int t1 = ArraySize(tmp1);
   ArrayResize(g_p1Tickets, t1);
   for(int i = 0; i < t1; i++) g_p1Tickets[i] = tmp1[i];

   ulong tmp2[]; ArrayResize(tmp2, 0);
   int s2 = ArraySize(g_p2Tickets);
   for(int i = 0; i < s2; i++)
      if(TicketArrayHas(open, g_p2Tickets[i])) TicketArrayAdd(tmp2, g_p2Tickets[i]);
   ArrayFree(g_p2Tickets);
   int t2 = ArraySize(tmp2);
   ArrayResize(g_p2Tickets, t2);
   for(int i = 0; i < t2; i++) g_p2Tickets[i] = tmp2[i];
}

void ManagePartial()
{
   if(!InpUsePartial) return;
   PruneClosedTickets();
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volStep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != InpMagic || pos.Symbol() != _Symbol) continue;
      ulong tk = pos.Ticket();
      double open = pos.PriceOpen();
      double vol  = pos.Volume();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profPts = (pos.PositionType() == POSITION_TYPE_BUY) ? (bid - open) / pt : (open - ask) / pt;

      if(!TicketArrayHas(g_p1Tickets, tk) && profPts >= InpP1Pts)
      {
         double cv = MathFloor((vol * InpP1Pct / 100.0) / volStep) * volStep;
         if(cv >= volMin && cv < vol)
            if(trade.PositionClosePartial(tk, cv))
               TicketArrayAdd(g_p1Tickets, tk);
      }
      if(TicketArrayHas(g_p1Tickets, tk) && !TicketArrayHas(g_p2Tickets, tk) && profPts >= InpP2Pts)
      {
         double remain = pos.Volume();
         double cv = MathFloor((remain * InpP2Pct / 100.0) / volStep) * volStep;
         if(cv >= volMin && cv < remain)
            if(trade.PositionClosePartial(tk, cv))
               TicketArrayAdd(g_p2Tickets, tk);
      }
   }
}

//+------------------------------------------------------------------+
//| VISUAL ZONES (live only)                                         |
//+------------------------------------------------------------------+
void DrawZones()
{
   string sName = PFX + "supply";
   string dName = PFX + "demand";
   datetime t1 = iTime(_Symbol, InpTF, InpPivotLength + 1);
   datetime t2 = iTime(_Symbol, InpTF, 0) + PeriodSeconds(InpTF) * 5;

   if(g_supplyTop > 0 && g_supplyBot > 0)
   {
      if(ObjectFind(0, sName) < 0)
         ObjectCreate(0, sName, OBJ_RECTANGLE, 0, t1, g_supplyTop, t2, g_supplyBot);
      else { ObjectMove(0, sName, 0, t1, g_supplyTop); ObjectMove(0, sName, 1, t2, g_supplyBot); }
      ObjectSetInteger(0, sName, OBJPROP_COLOR, InpClrSupply);
      ObjectSetInteger(0, sName, OBJPROP_FILL,  true);
      ObjectSetInteger(0, sName, OBJPROP_BACK,  true);
   }
   if(g_demandTop > 0 && g_demandBot > 0)
   {
      if(ObjectFind(0, dName) < 0)
         ObjectCreate(0, dName, OBJ_RECTANGLE, 0, t1, g_demandTop, t2, g_demandBot);
      else { ObjectMove(0, dName, 0, t1, g_demandTop); ObjectMove(0, dName, 1, t2, g_demandBot); }
      ObjectSetInteger(0, dName, OBJPROP_COLOR, InpClrDemand);
      ObjectSetInteger(0, dName, OBJPROP_FILL,  true);
      ObjectSetInteger(0, dName, OBJPROP_BACK,  true);
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD (live only, throttled)                                 |
//+------------------------------------------------------------------+
void MakeLabel(string name, int x, int y, string text, color clr, int size = 9)
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
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString (0, name, OBJPROP_TEXT, text);
}

void MakeBox(string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
}

void BuildDashboard()
{
   int x = 14, y = 22, w = 290, h = 410;
   MakeBox(PFX + "panel",  x, y, w, h, InpClrBg, clrSlateGray);
   MakeBox(PFX + "header", x, y, w, 28, clrDarkSlateGray, clrSlateGray);
   MakeLabel(PFX + "title", x + 10, y + 6, "ANMOL GOLDMIND AI Pro v4.30", InpClrText, 10);
   UpdateDashboard();
}

void UpdateDashboard()
{
   if(ObjectFind(0, PFX + "panel") < 0) BuildDashboard();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl = eq - bal;
   double dayPnL = (g_dayStartBalance > 0) ? (eq - g_dayStartBalance) : 0;
   double dayPct = (g_dayStartBalance > 0) ? (dayPnL / g_dayStartBalance * 100.0) : 0;
   double ddPct  = (g_equityPeak > 0) ? ((g_equityPeak - eq) / g_equityPeak * 100.0) : 0;
   double winRate = (g_totalTrades > 0) ? (100.0 * g_wins / g_totalTrades) : 0;
   double pf = (g_grossLoss > 0) ? (g_grossProfit / g_grossLoss) : (g_grossProfit > 0 ? 99.0 : 0);
   double spread = GetSpreadPts();
   color sigClr = (g_lastSignal == "BUY") ? InpClrBuy : (g_lastSignal == "SELL") ? InpClrSell : InpClrWarn;

   int x = 24, y = 60, lh = 18;
   MakeLabel(PFX + "l_sym",   x, y,           StringFormat("Symbol: %s %s", _Symbol, EnumToString(InpTF)), InpClrText);
   MakeLabel(PFX + "l_sig",   x, y + lh*1,    StringFormat("Signal: %s%s", g_newsBoost ? "[N] " : "", g_lastSignal), sigClr, 10);
   MakeLabel(PFX + "l_entry", x, y + lh*2,    StringFormat("Entry:  %s", g_lastEntry > 0 ? DoubleToString(g_lastEntry,_Digits) : "-"), InpClrText);
   MakeLabel(PFX + "l_sl",    x, y + lh*3,    StringFormat("SL:     %s", g_lastSL > 0 ? DoubleToString(g_lastSL,_Digits) : "-"), InpClrText);
   MakeLabel(PFX + "l_tp",    x, y + lh*4,    StringFormat("TP:     %s", g_lastTP > 0 ? DoubleToString(g_lastTP,_Digits) : "-"), InpClrText);
   MakeLabel(PFX + "l_rr",    x, y + lh*5,    StringFormat("R:R:    1:%.2f", g_lastRR), InpClrText);

   MakeLabel(PFX + "l_sup",   x, y + lh*7,    StringFormat("Supply: %s/%s", DoubleToString(g_supplyTop,_Digits), DoubleToString(g_supplyBot,_Digits)), InpClrSell);
   MakeLabel(PFX + "l_dem",   x, y + lh*8,    StringFormat("Demand: %s/%s", DoubleToString(g_demandTop,_Digits), DoubleToString(g_demandBot,_Digits)), InpClrBuy);

   MakeLabel(PFX + "l_bal",   x, y + lh*10,   StringFormat("Balance: %.2f", bal), InpClrText);
   MakeLabel(PFX + "l_eq",    x, y + lh*11,   StringFormat("Equity:  %.2f", eq), InpClrText);
   MakeLabel(PFX + "l_pnl",   x, y + lh*12,   StringFormat("PnL:     %s%.2f", pnl >= 0 ? "+" : "", pnl), pnl >= 0 ? InpClrBuy : InpClrSell);
   MakeLabel(PFX + "l_day",   x, y + lh*13,   StringFormat("Day:     %s%.2f (%.2f%%)", dayPnL >= 0 ? "+" : "", dayPnL, dayPct), dayPnL >= 0 ? InpClrBuy : InpClrSell);
   MakeLabel(PFX + "l_dd",    x, y + lh*14,   StringFormat("DD:      %.2f%%", ddPct), ddPct > InpMaxEquityDDPct * 0.7 ? InpClrWarn : InpClrText);

   MakeLabel(PFX + "l_stats", x, y + lh*16,   StringFormat("T:%d W:%d L:%d WR:%.1f%% PF:%.2f", g_totalTrades, g_wins, g_losses, winRate, pf), InpClrText);
   MakeLabel(PFX + "l_today", x, y + lh*17,   StringFormat("Today losses:%d/%d %s", g_lossesToday, InpMaxLossesPerDay, InCooldown() ? "COOLDOWN" : ""), InCooldown() ? InpClrWarn : InpClrText);

   MakeLabel(PFX + "l_news",  x, y + lh*19,   StringFormat("News:%s News-time:%s Spread:%.0f",
                          InpNewsMode == NEWS_OFF ? "OFF" : (InpNewsMode == NEWS_BLOCK ? "BLOCK" : "BOOST"),
                          IsNewsTime() ? "ACTIVE" : "no", spread),
             spread > InpMaxSpreadPts ? InpClrWarn : InpClrText);

   string status; color statusClr;
   if(g_ddLocked)             { status = "LOCKED: " + g_ddLockReason; statusClr = InpClrSell; }
   else if(InCooldown())      { status = "COOLDOWN";                  statusClr = InpClrWarn; }
   else if(spread > InpMaxSpreadPts) { status = "WIDE SPREAD";        statusClr = InpClrWarn; }
   else                       { status = "ARMED";                     statusClr = InpClrBuy;  }
   MakeLabel(PFX + "l_status", x, y + lh*21, "STATUS: " + status, statusClr, 10);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
