//+------------------------------------------------------------------+
//|                                       XAU_Range_Scalper_Pro.mq5  |
//|                                          Copyright 2026, Antu AI |
//|                                                                  |
//|  Range/Sideways scalper for XAUUSD M5.                           |
//|  - Detects valid ranges using last N candles + ATR vol filter    |
//|  - Trades S/R reversals confirmed by candlestick patterns + RSI  |
//|  - Optional Bollinger Bands confirmation                         |
//|  - Auto SL by ATR multiplier; TP by RR multiplier (or opposite   |
//|    side of the range, whichever is closer)                       |
//|  - 1% risk-based lot sizing, daily loss limit, max 1 trade       |
//|  - Spread, session, London/NY open volatility filters            |
//|  - Break-even, trailing stop                                     |
//|  - Pauses entries on strong breakout, resumes on new range       |
//|  - On-chart dashboard, push notifications, trade log file        |
//|  - Backtest-ready, optimization-ready inputs                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antu AI"
#property version   "1.00"
#property strict
#property description "XAU Range Scalper Pro - XAUUSD M5 sideways/range strategy"

#include <Trade/Trade.mqh>

#include "..\\Include\\XAURangeScalperPro\\RangeDetector.mqh"
#include "..\\Include\\XAURangeScalperPro\\SignalEngine.mqh"
#include "..\\Include\\XAURangeScalperPro\\RiskManager.mqh"
#include "..\\Include\\XAURangeScalperPro\\TradeManager.mqh"
#include "..\\Include\\XAURangeScalperPro\\Filters.mqh"
#include "..\\Include\\XAURangeScalperPro\\Dashboard.mqh"

//============================== INPUTS ==============================

input group "=== General ==="
input ulong  InpMagic               = 20260525;       // Magic Number
input string InpTradeComment         = "XAU_RSP";      // Trade comment
input bool   InpAllowTradingOnlyXAU  = true;           // Refuse to attach to non-XAUUSD
input bool   InpDrawObjects          = true;           // Draw entry arrows + SL/TP lines
input bool   InpShowDashboard        = true;           // Show on-chart dashboard
input bool   InpPushAlerts           = true;           // Push notifications + Alerts
input string InpLogFileName          = "XAU_RSP_log.txt";

input group "=== Risk Management ==="
input double InpRiskPercent          = 1.0;            // Risk % per trade
input double InpMaxDailyLossPercent  = 3.0;            // Max daily loss % (0=off)
input int    InpMaxOpenTrades        = 1;              // Max simultaneous trades

input group "=== Range Detection ==="
input int    InpRangeLookback        = 50;             // Candles for range
input int    InpMinTouchesPerSide    = 2;              // Min S/R rejections per side
input double InpTouchTolerancePoints = 200;            // Tolerance to count a touch (points)
input double InpAtrMaxRatio          = 0.35;           // ATR/RangeWidth max (low vol)
input int    InpBreakoutCooldownBars = 20;             // Pause entries after strong breakout

input group "=== Indicators ==="
input int    InpAtrPeriod            = 14;             // ATR period
input int    InpRsiPeriod            = 14;             // RSI period
input double InpRsiBuyMax            = 35.0;           // Max RSI for BUY
input double InpRsiSellMin           = 65.0;           // Min RSI for SELL
input bool   InpUseBollinger         = false;          // Use Bollinger confirmation
input int    InpBbPeriod             = 20;
input double InpBbDeviation          = 2.0;

input group "=== SL / TP ==="
input double InpSlAtrMultiplier      = 1.5;            // SL = ATR * x (beyond level)
input double InpTpRRMultiplier       = 1.8;            // TP = SL * RR
input bool   InpTpAtRangeOpposite    = true;           // Cap TP at opposite side of range

input group "=== Trade Management ==="
input bool   InpUseBreakEven         = true;
input double InpBreakEvenTriggerPts  = 800;            // start BE at +X points
input double InpBreakEvenLockPts     = 50;             // lock +X points beyond entry
input bool   InpUseTrailing          = true;
input double InpTrailStartPoints     = 1200;           // begin trail when +X points
input double InpTrailStepPoints      = 600;            // distance to keep

input group "=== Filters ==="
input int    InpSpreadLimitPoints    = 50;             // Max allowed spread (points)
input int    InpSlippagePoints       = 20;             // Order deviation
input bool   InpUseSessionFilter     = true;
input int    InpSessionStartHour     = 7;              // server time
input int    InpSessionEndHour       = 20;             // server time
input bool   InpAvoidLondonOpen      = true;
input bool   InpAvoidNYOpen          = true;
input int    InpLondonOpenHour       = 10;             // server time approx
input int    InpNyOpenHour           = 15;             // server time approx
input int    InpAvoidMinutesAround   = 15;

//============================== OBJECTS =============================

CRangeDetector g_range;
CSignalEngine  g_signal;
CRiskManager   g_risk;
CTradeManager  g_trade;
CFilters       g_filters;
CDashboard     g_dash;

datetime       g_lastBarTime  = 0;
int            g_breakoutCooldown = 0;

// stats
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
                    InpAtrMaxRatio,
                    InpTouchTolerancePoints,
                    InpMinTouchesPerSide))
      return INIT_FAILED;

   if(!g_signal.Init(_Symbol, _Period,
                     InpRsiPeriod,
                     InpRsiBuyMax, InpRsiSellMin,
                     InpUseBollinger, InpBbPeriod, InpBbDeviation))
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

   Print("XAU Range Scalper Pro initialised on ", _Symbol, " ", EnumToString(_Period));
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

   //--- only run signal logic ONCE per new bar (no repaint, low CPU)
   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime)
   {
      // still update the dashboard occasionally so spread/PnL stay live
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

   //--- if we already have max trades, just refresh the dashboard
   if(g_trade.CountOpenPositions() >= InpMaxOpenTrades)
   {
      UpdateDashboard("Max trades open", false);
      return;
   }

   //--- if breakout cooldown active, skip entries
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
   double atr      = (r.atr > 0) ? r.atr : 0.0;
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
      if(InpTpAtRangeOpposite) tp = MathMin(tp, r.resistance - 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }
   else // SELL
   {
      entry = bid;
      sl    = r.resistance + InpSlAtrMultiplier * atr;
      double slDist = sl - entry;
      tp    = entry - InpTpRRMultiplier * slDist;
      if(InpTpAtRangeOpposite) tp = MathMax(tp, r.support + 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }

   //--- sanity checks
   double slDistPrice = MathAbs(entry - sl);
   if(slDistPrice <= 0)
   {
      UpdateDashboard("Invalid SL distance", false);
      return;
   }

   double lots = g_risk.CalcLotByRisk(slDistPrice);
   if(lots <= 0)
   {
      UpdateDashboard("Lot calc failed", false);
      return;
   }

   //--- normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   string cmt = StringFormat("%s_%s_RSI%.1f", InpTradeComment,
                             (sig == SIG_BUY ? "B":"S"), rsi);

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
   datetime from = TimeCurrent() - 60 * 60 * 24 * 30;   // last 30 days
   if(!HistorySelect(from, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   int trades = 0, wins = 0, losses = 0;
   ulong lastSeen = g_lastDealId;
   ulong newest   = g_lastDealId;

   for(int i = 0; i < total; i++)
   {
      ulong dealId = HistoryDealGetTicket(i);
      if(dealId == 0) continue;

      if((ulong)HistoryDealGetInteger(dealId, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(dealId, DEAL_SYMBOL) != _Symbol) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealId, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;   // only closing deals

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
//| OnTrade - log fill events                                        |
//+------------------------------------------------------------------+
void OnTrade()
{
   // light hook; full reconciliation done in UpdateClosedTradeStats
}
//+------------------------------------------------------------------+
