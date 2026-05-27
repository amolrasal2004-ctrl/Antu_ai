//+------------------------------------------------------------------+
//|                                       ANTU_PROFITENGINE_v01.mq5  |
//|                                                                  |
//|  ANTU PROFIT ENGINE v01 - Sideways/Range Market EA               |
//|  Symbol:    XAUUSD (Gold)                                        |
//|  Broker:    Vantage                                              |
//|  Account:   $300 starter                                         |
//|  Target:    $15-20 daily profit (consistent)                     |
//|  Strategy:  Mean Reversion in Asian Session range                |
//|                                                                  |
//|  How it works (simple Hindi):                                    |
//|  1. Asian session (00:00-07:00 GMT) ka high/low yaad rakhta hai  |
//|  2. Agar market range me hai (ADX low, ATR low)                  |
//|  3. Range ke upar pe SELL, niche pe BUY karta hai (RSI confirm)  |
//|  4. $20 profit ya $10 loss ho gaya = aaj ke liye band            |
//|  5. Professional dashboard chart pe live status dikhata hai      |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property link      ""
#property version   "1.00"
#property strict
#property description "Sideways/Range XAUUSD scalper - $300 account, $15-20 daily target"

#include "../Include/ANTU_PROFITENGINE_v01/PE_RangeDetector.mqh"
#include "../Include/ANTU_PROFITENGINE_v01/PE_Filters.mqh"
#include "../Include/ANTU_PROFITENGINE_v01/PE_SignalEngine.mqh"
#include "../Include/ANTU_PROFITENGINE_v01/PE_RiskManager.mqh"
#include "../Include/ANTU_PROFITENGINE_v01/PE_TradeManager.mqh"
#include "../Include/ANTU_PROFITENGINE_v01/PE_Dashboard.mqh"

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
input double  InpRSIOversold       = 30.0;         // RSI Oversold (BUY)
input double  InpRSIOverbought     = 70.0;         // RSI Overbought (SELL)

input group "===== SAFETY FILTERS ====="
input double  InpMaxADX            = 22.0;         // Max ADX (above = trend)
input double  InpMaxATR            = 3.5;          // Max ATR (gold-tuned)
input int     InpMaxSpread         = 30;           // Max Spread (points)
input int     InpSessionStart      = 0;            // Trade Session Start (hr)
input int     InpSessionEnd        = 14;           // Trade Session End (hr)

input group "===== TRADE PARAMETERS ====="
input double  InpStopLossPips      = 18.0;         // Stop Loss (pips)
input double  InpTakeProfitPips    = 10.0;         // Take Profit (pips)
input bool    InpUseAutoLot        = true;         // Auto Lot from Risk %
input double  InpManualLot         = 0.01;         // Manual Lot (if Auto OFF)

input group "===== RISK MANAGEMENT ====="
input double  InpRiskPercent       = 1.0;          // Risk % per trade
input double  InpDailyProfitTarget = 20.0;         // Daily Profit Target ($)
input double  InpDailyLossLimit    = 10.0;         // Daily Loss Limit ($)
input int     InpMaxTradesPerDay   = 4;            // Max Trades per Day
input int     InpMaxConsecLosses   = 3;            // Max Consec Losses (pause)
input double  InpMaxDrawdownPct    = 5.0;          // Max DD % (lock)

input group "===== DASHBOARD ====="
input bool    InpShowDashboard     = true;         // Show Dashboard
input int     InpDashUpdateSec     = 1;            // Update interval (sec)

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
   
   // Initialize all modules
   g_range = new CRangeDetector(_Symbol, InpAsianStart, InpAsianEnd,
                                InpMinRangePips, InpMaxRangePips);
   
   g_filters = new CFilters(_Symbol, InpSignalTF, InpMaxADX, InpMaxATR,
                            InpMaxSpread, InpSessionStart, InpSessionEnd);
   
   g_signal = new CSignalEngine(_Symbol, InpSignalTF, 
                                InpRSIOversold, InpRSIOverbought);
   
   g_risk = new CRiskManager(InpDailyProfitTarget, InpDailyLossLimit,
                             InpRiskPercent, InpMaxTradesPerDay,
                             InpMaxConsecLosses, InpMaxDrawdownPct);
   
   g_trade = new CTradeManager(_Symbol, InpMagicNumber, InpComment);
   
   if(InpShowDashboard)
   {
      g_dash = new CDashboard("ANTU_DASH_");
      g_dash.Init();
   }
   
   // Initial range calculation
   g_range.CalculateRange();
   
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
   // Check new day - reset counters if needed
   g_risk.CheckNewDay();
   
   // Update dashboard frequently (every tick if enabled)
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
   
   // Process signals only on new bar (avoid noise)
   datetime curBarTime = (datetime)SeriesInfoInteger(_Symbol, InpSignalTF, 
                                                     SERIES_LASTBAR_DATE);
   if(curBarTime == g_lastBarTime) return;
   g_lastBarTime = curBarTime;
   
   // Refresh range data
   g_range.CalculateRange();
   
   // Risk gate: trading allowed?
   if(!g_risk.CanTrade()) return;
   
   // Already have open position? Skip new entries
   if(g_trade.CountOpenPositions() > 0) return;
   
   // Generate signal
   ENUM_SIGNAL sig = g_signal.CheckSignal(g_range, g_filters);
   if(sig == SIGNAL_NONE) return;
   
   // Calculate lot size
   double lot = InpManualLot;
   if(InpUseAutoLot)
   {
      lot = g_risk.CalculateLot(_Symbol, InpStopLossPips, g_range.PipValue());
   }
   
   // Execute trade
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
//| TRADE TRANSACTION HANDLER (track closed trades)                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Detect closed position - update risk manager P&L
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
