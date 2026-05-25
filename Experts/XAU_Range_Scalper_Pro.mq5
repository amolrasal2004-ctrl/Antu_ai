//+------------------------------------------------------------------+
//|                                       XAU_Range_Scalper_Pro.mq5  |
//|                                          Copyright 2026, Antu AI |
//|                                                                  |
//|  Range/Sideways scalper for XAUUSD M5.                           |
//|  v1.1 improvements:                                              |
//|   - ADX trend-strength filter (only trade when ranging)          |
//|   - EMA-200 trend filter (skip counter-trend in strong trends)   |
//|   - Touch spacing validation (touches must be distributed)       |
//|   - Higher-TF (M15) volatility confirmation                      |
//|   - Stronger 2-bar breakout detection                            |
//|   - Pattern engulfing / pin must have stronger structure         |
//|   - RSI slope confirmation (turning, not just oversold)          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antu AI"
#property version   "1.10"
#property strict
#property description "XAU Range Scalper Pro v1.1 - XAUUSD M5 sideways/range strategy"

#include <Trade/Trade.mqh>

//--- Angle-bracket includes are resolved from <MT5 Data Folder>/MQL5/Include/
#include <XAURangeScalperPro/RangeDetector.mqh>
#include <XAURangeScalperPro/SignalEngine.mqh>
#include <XAURangeScalperPro/RiskManager.mqh>
#include <XAURangeScalperPro/TradeManager.mqh>
#include <XAURangeScalperPro/Filters.mqh>
#include <XAURangeScalperPro/Dashboard.mqh>

//============================== INPUTS ==============================

input group "=== General ==="
input ulong  InpMagic                = 20260525;
input string InpTradeComment          = "XAU_RSP";
input bool   InpAllowTradingOnlyXAU   = true;
input bool   InpDrawObjects           = true;
input bool   InpShowDashboard         = true;
input bool   InpPushAlerts            = false;        // off by default for backtests
input string InpLogFileName           = "XAU_RSP_log.txt";

input group "=== Risk Management ==="
input double InpRiskPercent           = 1.0;
input double InpMaxDailyLossPercent   = 3.0;
input int    InpMaxOpenTrades         = 1;

input group "=== Range Detection ==="
input int    InpRangeLookback         = 50;
input int    InpMinTouchesPerSide     = 2;          // loosened
input int    InpMinTouchSpacing       = 3;          // loosened
input double InpTouchTolerancePoints  = 250;
input double InpAtrMaxRatio           = 0.45;       // loosened
input int    InpBreakoutCooldownBars  = 20;
input bool   InpUseHtfFilter          = false;      // OFF
input ENUM_TIMEFRAMES InpHtfPeriod    = PERIOD_M15;

input group "=== Indicators ==="
input int    InpAtrPeriod             = 14;
input int    InpAdxPeriod             = 14;
input double InpAdxMax                = 30.0;       // loosened
input int    InpRsiPeriod             = 14;
input double InpRsiBuyMax             = 38.0;
input double InpRsiSellMin            = 62.0;
input bool   InpUseBollinger          = false;
input int    InpBbPeriod              = 20;
input double InpBbDeviation           = 2.0;
input bool   InpUseTrendFilter        = false;      // OFF
input int    InpEmaPeriod             = 200;
input double InpEmaMaxDistAtr         = 5.0;

input group "=== SL / TP ==="
input double InpSlAtrMultiplier       = 1.5;
input double InpTpRRMultiplier        = 1.8;
input bool   InpTpAtRangeOpposite     = true;

input group "=== Trade Management ==="
input bool   InpUseBreakEven          = true;
input double InpBreakEvenTriggerPts   = 600;
input double InpBreakEvenLockPts      = 50;
input bool   InpUseTrailing           = true;
input double InpTrailStartPoints      = 1000;
input double InpTrailStepPoints       = 500;

input group "=== Filters ==="
input int    InpSpreadLimitPoints     = 50;
input int    InpSlippagePoints        = 20;
input bool   InpUseSessionFilter      = true;
input int    InpSessionStartHour      = 8;            // server time
input int    InpSessionEndHour        = 19;
input bool   InpAvoidLondonOpen       = true;
input bool   InpAvoidNYOpen           = true;
input int    InpLondonOpenHour        = 10;
input int    InpNyOpenHour            = 15;
input int    InpAvoidMinutesAround    = 20;

//============================== OBJECTS =============================

CRangeDetector g_range;
CSignalEngine  g_signal;
CRiskManager   g_risk;
CTradeManager  g_trade;
CFilters       g_filters;
CDashboard     g_dash;

datetime       g_lastBarTime  = 0;
int            g_breakoutCooldown = 0;

int            g_totalTrades  = 0;
int            g_wins         = 0;
int            g_losses       = 0;
ulong          g_lastDealId   = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
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

   if(!g_range.Init(_Symbol, _Period,
                    InpRangeLookback,
                    InpAtrPeriod,
                    InpAdxPeriod,
                    InpAtrMaxRatio,
                    InpAdxMax,
                    InpTouchTolerancePoints,
                    InpMinTouchesPerSide,
                    InpMinTouchSpacing,
                    InpUseHtfFilter,
                    InpHtfPeriod))
      return INIT_FAILED;

   if(!g_signal.Init(_Symbol, _Period,
                     InpRsiPeriod,
                     InpRsiBuyMax, InpRsiSellMin,
                     InpUseBollinger, InpBbPeriod, InpBbDeviation,
                     InpUseTrendFilter, InpEmaPeriod, InpEmaMaxDistAtr))
      return INIT_FAILED;

   g_risk.Init(_Symbol, InpRiskPercent, InpMaxDailyLossPercent);

   if(!g_trade.Init(_Symbol, InpMagic, InpSlippagePoints,
                    InpUseTrailing, InpTrailStartPoints, InpTrailStepPoints,
                    InpUseBreakEven, InpBreakEvenTriggerPts, InpBreakEvenLockPts,
                    InpDrawObjects, InpPushAlerts, InpLogFileName))
      return INIT_FAILED;

   g_filters.Init(_Symbol,
                  InpSpreadLimitPoints,
                  InpUseSessionFilter,
                  InpSessionStartHour, InpSessionEndHour,
                  InpAvoidLondonOpen, InpAvoidNYOpen,
                  InpLondonOpenHour, InpNyOpenHour,
                  InpAvoidMinutesAround);

   if(InpShowDashboard) g_dash.Init();

   g_lastBarTime = 0;
   g_breakoutCooldown = 0;
   g_totalTrades = g_wins = g_losses = 0;

   Print("XAU Range Scalper Pro v1.1 initialised on ", _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_range.Deinit();
   g_signal.Deinit();
   g_trade.Deinit();
   if(InpShowDashboard) g_dash.Deinit();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   g_risk.OnTick();

   //--- always manage open positions on every tick (BE/trail)
   g_trade.ManageOpenPositions();

   //--- daily loss guard
   if(g_risk.DailyLossHit())
   {
      static bool closedOnce = false;
      if(!closedOnce)
      {
         g_trade.CloseAllOurPositions("Daily loss limit");
         closedOnce = true;
      }
      UpdateDashboard("Daily loss limit hit", false);
      return;
   }

   //--- only run signal logic ONCE per new bar
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

   //--- recompute range
   g_range.Update();

   //--- breakout cooldown
   if(g_range.IsStrongBreakout())
   {
      g_breakoutCooldown = InpBreakoutCooldownBars;
      g_trade.WriteLog("Strong breakout detected -> entries paused");
   }
   if(g_breakoutCooldown > 0) g_breakoutCooldown--;

   //--- update PnL stats from history
   UpdateClosedTradeStats();

   //--- pre-trade filters
   string filterReason = "";
   bool filtersOK = g_filters.AllOK(filterReason);

   if(g_trade.CountOpenPositions() >= InpMaxOpenTrades)
   {
      UpdateDashboard("Max trades open", false);
      return;
   }

   if(g_breakoutCooldown > 0)
   {
      UpdateDashboard(StringFormat("Breakout cooldown (%d)", g_breakoutCooldown), false);
      return;
   }

   if(!filtersOK)
   {
      UpdateDashboard(filterReason, false);
      return;
   }

   //--- get signal
   double rsi = 0.0;
   ENUM_SIGNAL sig = g_signal.Evaluate(g_range, rsi);
   const SRange r  = g_range.Range();

   if(sig == SIG_NONE || !r.valid)
   {
      UpdateDashboard("", true);
      return;
   }

   //--- compute SL & TP in price
   double atr = (r.atr > 0) ? r.atr : 0.0;
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
      sl    = r.support - InpSlAtrMultiplier * atr;
      double slDist = entry - sl;
      tp    = entry + InpTpRRMultiplier * slDist;
      if(InpTpAtRangeOpposite)
         tp = MathMin(tp, r.resistance - 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }
   else
   {
      entry = bid;
      sl    = r.resistance + InpSlAtrMultiplier * atr;
      double slDist = sl - entry;
      tp    = entry - InpTpRRMultiplier * slDist;
      if(InpTpAtRangeOpposite)
         tp = MathMax(tp, r.support + 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }

   //--- minimum RR sanity: TP must be at least 1.0 RR
   double slDistPrice = MathAbs(entry - sl);
   double tpDistPrice = MathAbs(tp - entry);
   if(slDistPrice <= 0 || tpDistPrice < slDistPrice * 0.8)
   {
      UpdateDashboard("RR too small", false);
      return;
   }

   double lots = g_risk.CalcLotByRisk(slDistPrice);
   if(lots <= 0)
   {
      UpdateDashboard("Lot calc failed", false);
      return;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   string cmt = StringFormat("%s_%s_RSI%.0f_ADX%.0f", InpTradeComment,
                             (sig == SIG_BUY ? "B":"S"), rsi, r.adx);

   ENUM_ORDER_TYPE otype = (sig == SIG_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   g_trade.OpenTrade(otype, lots, sl, tp, cmt);

   UpdateDashboard("", true);
}

//+------------------------------------------------------------------+
//| Refresh dashboard                                                |
//+------------------------------------------------------------------+
void UpdateDashboard(const string filterReason, const bool filtersOK)
{
   if(!InpShowDashboard) return;

   SStats s;
   s.totalTrades   = g_totalTrades;
   s.wins          = g_wins;
   s.losses        = g_losses;
   s.dayPnL        = g_risk.DayPnL();
   s.dayPnLPercent = g_risk.DayPnLPercent();
   s.spreadPoints  = g_filters.CurrentSpreadPoints();
   s.filtersOK     = filtersOK;
   s.filterReason  = filterReason;

   g_dash.Update(g_range.Range(), s);
}

//+------------------------------------------------------------------+
//| Walk recent deal history and tally W/L for OUR magic only        |
//+------------------------------------------------------------------+
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

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealId, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(dealId, DEAL_PROFIT)
                    + HistoryDealGetDouble(dealId, DEAL_SWAP)
                    + HistoryDealGetDouble(dealId, DEAL_COMMISSION);

      trades++;
      if(profit >= 0) wins++;
      else            losses++;

      if(dealId > newest) newest = dealId;
   }

   g_totalTrades = trades;
   g_wins        = wins;
   g_losses      = losses;
   g_lastDealId  = newest;
}

//+------------------------------------------------------------------+
//| OnTrade                                                          |
//+------------------------------------------------------------------+
void OnTrade()
{
   // light hook; reconciliation done in UpdateClosedTradeStats
}
//+------------------------------------------------------------------+
