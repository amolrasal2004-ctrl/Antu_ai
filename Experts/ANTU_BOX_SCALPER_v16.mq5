//+------------------------------------------------------------------+
//|                                         ANTU_BOX_SCALPER_v16.mq5 |
//|                         Professional XAUUSD Scalping EA for MT5  |
//|       Strategy: SMART Box Breakout (Quality > Quantity)          |
//|                  Timeframe: M5 | Symbol: XAUUSD                  |
//|                       FINAL PRODUCTION BUILD                     |
//+------------------------------------------------------------------+
#property copyright   "Antu Trading"
#property link        ""
#property version     "16.00"
#property strict
#property description "SMART Box Breakout Scalper - Quality Trades Only"
#property description "Filters: Box Size + Body + EMA + ATR + Cooldown"
#property description "Dynamic ATR-based TP/SL | Break-Even | Trailing"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================//
//                          INPUT PARAMETERS                        //
//==================================================================//

input group "=== SECURITY ==="
input long     InpAccountLock    = 0;            // 0 = Any account
input string   InpExpiryDate     = "";           // YYYY.MM.DD HH:MM (blank = no expiry)

input group "=== IDENTIFICATION ==="
input int      InpMagicNumber    = 202416;
input string   InpEAComment      = "ANTU_BOX_V16";

input group "=== ALERTS & NOTIFICATIONS ==="
input bool     InpSendPush       = true;         // Mobile push notifications
input bool     InpSendTelegram   = false;        // Telegram bot alerts
input string   InpTelegramToken  = "YOUR_BOT_TOKEN_HERE";
input string   InpTelegramChatID = "YOUR_CHAT_ID_HERE";

input group "=== IMMORTAL SHIELD (News Filter) ==="
input bool     UseNewsFilter     = true;
input int      PauseBeforeNews   = 30;           // Minutes before news
input int      PauseAfterNews    = 30;           // Minutes after news
input bool     FilterHighImpact  = true;         // Only high-impact events

input group "=== Session Filter ==="
input bool     UseSessionTime    = true;         // Trade only in liquid hours
input int      StartHour         = 12;           // Server time (London open)
input int      EndHour           = 21;           // NY overlap end

input group "=== BOX BREAKOUT LOGIC ==="
input int      InpBoxCandles     = 12;           // Candles to form the box
input double   InpBoxBuffer      = 15.0;         // Buffer in points beyond box
input double   InpMinBoxSize     = 80.0;         // Min box range in points
input double   InpMaxBoxSize     = 500.0;        // Max box range in points
input bool     InpDrawBox        = true;         // Show box lines on chart

input group "=== QUALITY FILTERS (v16) ==="
input bool     InpUseBodyFilter  = true;         // Strong breakout candle required
input double   InpMinBodyPct     = 60.0;         // Min body % of total range
input bool     InpUseMomentum    = true;         // EMA trend confirmation
input int      InpEMAFast        = 8;
input int      InpEMASlow        = 21;
input bool     InpUseATRFilter   = true;         // Skip dead market
input int      InpATRPeriod      = 14;
input double   InpMinATRPoints   = 100.0;        // Min ATR in points
input int      InpCooldownMin    = 15;           // Cooldown minutes between trades

input group "=== DYNAMIC TP / SL ==="
input bool     InpDynamicTPSL    = true;         // ATR-based TP/SL
input double   InpTPMultiplier   = 2.0;          // TP = 2x ATR
input double   InpSLMultiplier   = 1.0;          // SL = 1x ATR
input double   InpTakeProfit     = 250.0;        // Static TP (points) - fallback
input double   InpStopLoss       = 120.0;        // Static SL (points) - fallback

input group "=== TRAILING & BREAK-EVEN ==="
input bool     InpTrailingStop   = true;
input double   InpTrailStart     = 80.0;         // Trail start (points profit)
input double   InpTrailStep      = 20.0;         // Min step to move SL
input double   InpTrailStop      = 30.0;         // Trail distance from price
input bool     InpBreakEven      = true;
input double   InpBreakEvenAt    = 50.0;         // Trigger BE at +50 points
input double   InpBreakEvenLock  = 10.0;         // Lock +10 points profit

input group "=== RISK MANAGEMENT ==="
input double   InpLotSize        = 0.01;
input int      InpMaxTradesDay   = 8;            // Max trades per day
input double   InpDailyProfitTgt = 30.0;         // Daily profit target ($)
input double   InpDailyLossLimit = 15.0;         // Daily loss limit ($)
input int      InpMaxConsecLoss  = 2;            // Stop after N losses
input double   InpEquityDDPct    = 10.0;         // Equity drawdown %

input group "=== SPREAD & SLIPPAGE ==="
input int      InpMaxSpread      = 35;           // Max spread (points)
input int      InpMaxSlippage    = 20;           // Max slippage (points)

input group "=== DAILY RESET ==="
input bool     InpAutoReset      = true;

//==================================================================//
//                         GLOBAL STATE                             //
//==================================================================//

CTrade         trade;
CPositionInfo  posInfo;
CAccountInfo   accountInfo;
CSymbolInfo    symInfo;

#define CLR_BG        C'18,18,22'
#define CLR_BORDER    C'35,35,40'
#define CLR_GOLD      C'212,175,55'
#define CLR_GOLD_DIM  C'150,120,40'
#define CLR_TXT_LBL   C'160,165,170'
#define CLR_TXT_VAL   C'240,240,245'
#define CLR_UP        C'0,230,118'
#define CLR_DOWN      C'255,82,82'

double         g_DayStartBalance  = 0;
double         g_DayProfit        = 0;
double         g_DayLoss          = 0;
int            g_TradesToday      = 0;
int            g_ConsecLoss       = 0;
datetime       g_LastBarTime      = 0;
datetime       g_LastTradeTime    = 0;

double         g_BoxHigh          = 0;
double         g_BoxLow           = 0;
double         g_BoxSize          = 0;

bool           g_EARunning        = true;
bool           g_EmergencyStop    = false;
string         g_StatusMsg        = "INITIALIZING";
bool           g_SecurityPassed   = false;

bool           isNewsTime         = false;
string         newsStatusTxt      = "CLEAR";

int            g_hEMAFast         = INVALID_HANDLE;
int            g_hEMASlow         = INVALID_HANDLE;
int            g_hATR             = INVALID_HANDLE;

//==================================================================//
//                          INITIALIZATION                          //
//==================================================================//

int OnInit()
{
   if(!CheckSecurity())
   {
      Alert("ANTU v16: Security check failed!");
      return INIT_FAILED;
   }

   if(!symInfo.Name(_Symbol))
   {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
   }
   symInfo.RefreshRates();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetAsyncMode(false);

   // Auto-detect filling mode
   ENUM_ORDER_TYPE_FILLING filling = ORDER_FILLING_RETURN;
   long fill_mode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill_mode & SYMBOL_FILLING_FOK) != 0)      filling = ORDER_FILLING_FOK;
   else if((fill_mode & SYMBOL_FILLING_IOC) != 0) filling = ORDER_FILLING_IOC;
   trade.SetTypeFilling(filling);

   // Initialize indicators
   g_hEMAFast = iMA(_Symbol, PERIOD_M5, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMASlow = iMA(_Symbol, PERIOD_M5, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hATR     = iATR(_Symbol, PERIOD_M5, InpATRPeriod);

   if(g_hEMAFast == INVALID_HANDLE || g_hEMASlow == INVALID_HANDLE || g_hATR == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }

   // Validate lot size
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(InpLotSize < minLot || InpLotSize > maxLot)
   {
      PrintFormat("Lot size %.2f out of range [%.2f, %.2f]", InpLotSize, minLot, maxLot);
      return INIT_FAILED;
   }

   InitDashboard();
   ResetDailyStats();

   g_EARunning  = true;
   g_StatusMsg  = "SMART BOX V16 READY";

   Print("ANTU BOX SCALPER v16 initialized successfully");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_hEMAFast != INVALID_HANDLE) IndicatorRelease(g_hEMAFast);
   if(g_hEMASlow != INVALID_HANDLE) IndicatorRelease(g_hEMASlow);
   if(g_hATR     != INVALID_HANDLE) IndicatorRelease(g_hATR);

   ObjectsDeleteAll(0, "UI_");
   ObjectsDeleteAll(0, "L_");
   ObjectsDeleteAll(0, "V_");
   ObjectsDeleteAll(0, "BOX_");
   ChartRedraw();
}

//==================================================================//
//                            MAIN LOOP                             //
//==================================================================//

void OnTick()
{
   if(g_EmergencyStop) { g_StatusMsg = "EMERGENCY STOP"; UpdateDashboard(); return; }
   if(!g_SecurityPassed) return;

   symInfo.RefreshRates();

   CheckDailyReset();
   if(!CheckDailyLimits()) { UpdateDashboard(); return; }

   // Manage existing positions every tick
   if(InpTrailingStop) ManageTrailingStop();
   if(InpBreakEven)    ManageBreakEven();

   isNewsTime = CheckNewsEvent();
   bool isTradingSession = IsTradingTime();

   // Recalculate box once per new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime != g_LastBarTime)
   {
      CalculateBox();
      g_LastBarTime = currentBarTime;
   }

   if(CountOpenTrades() > 0) { UpdateDashboard(); return; }

   if(!isTradingSession) { g_StatusMsg = "SLEEPING"; UpdateDashboard(); return; }
   if(isNewsTime)        { g_StatusMsg = "SHIELD UP"; UpdateDashboard(); return; }

   // Cooldown check
   if(g_LastTradeTime > 0 && (TimeCurrent() - g_LastTradeTime) < (InpCooldownMin * 60))
   {
      int remainSec = (int)(InpCooldownMin * 60 - (TimeCurrent() - g_LastTradeTime));
      g_StatusMsg = "COOLDOWN " + IntegerToString(remainSec / 60 + 1) + "m";
      UpdateDashboard();
      return;
   }

   // Spread check
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      g_StatusMsg = "SPREAD HIGH (" + IntegerToString((int)spread) + ")";
      UpdateDashboard();
      return;
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) { UpdateDashboard(); return; }

   // Box size filter
   double boxPts = g_BoxSize / point;
   if(boxPts < InpMinBoxSize) { g_StatusMsg = "BOX TIGHT"; UpdateDashboard(); return; }
   if(boxPts > InpMaxBoxSize) { g_StatusMsg = "BOX WIDE";  UpdateDashboard(); return; }

   // ATR filter
   double atr = GetATR();
   if(InpUseATRFilter && (atr / point) < InpMinATRPoints)
   {
      g_StatusMsg = "ATR LOW";
      UpdateDashboard();
      return;
   }

   double ask    = symInfo.Ask();
   double bid    = symInfo.Bid();
   double buffer = InpBoxBuffer * point;

   // Compute TP/SL
   double tp, sl;
   if(InpDynamicTPSL && atr > 0)
   {
      tp = atr * InpTPMultiplier;
      sl = atr * InpSLMultiplier;
   }
   else
   {
      tp = InpTakeProfit * point;
      sl = InpStopLoss   * point;
   }

   if(g_BoxHigh <= 0 || g_BoxLow <= 0) { UpdateDashboard(); return; }

   // ============== BREAKOUT UP ==============
   if(ask > (g_BoxHigh + buffer))
   {
      if(!ValidateBreakout(1))
      {
         g_StatusMsg = "FAKE FILTERED (UP)";
         UpdateDashboard();
         return;
      }

      double slPrice = NormalizeDouble(ask - sl, _Digits);
      double tpPrice = NormalizeDouble(ask + tp, _Digits);

      if(trade.Buy(InpLotSize, _Symbol, ask, slPrice, tpPrice, InpEAComment))
      {
         g_TradesToday++;
         g_LastTradeTime = TimeCurrent();
         g_StatusMsg = "BUY OK QUALITY";
         g_BoxHigh = 0; // Prevent re-entry on same box
         SendAlertMessage(BuildAlert("BUY", ask, tp, sl, atr, point));
      }
      else
      {
         PrintFormat("Buy failed: %d - %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
   // ============== BREAKOUT DOWN ==============
   else if(bid < (g_BoxLow - buffer))
   {
      if(!ValidateBreakout(-1))
      {
         g_StatusMsg = "FAKE FILTERED (DN)";
         UpdateDashboard();
         return;
      }

      double slPrice = NormalizeDouble(bid + sl, _Digits);
      double tpPrice = NormalizeDouble(bid - tp, _Digits);

      if(trade.Sell(InpLotSize, _Symbol, bid, slPrice, tpPrice, InpEAComment))
      {
         g_TradesToday++;
         g_LastTradeTime = TimeCurrent();
         g_StatusMsg = "SELL OK QUALITY";
         g_BoxLow = 0;
         SendAlertMessage(BuildAlert("SELL", bid, tp, sl, atr, point));
      }
      else
      {
         PrintFormat("Sell failed: %d - %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
   else
   {
      g_StatusMsg = "HUNTING QUALITY";
   }

   UpdateDashboard();
}

string BuildAlert(string side, double price, double tp, double sl, double atr, double point)
{
   string emoji = (side == "BUY") ? "[BUY]" : "[SELL]";
   return emoji + " ANTU v16 " + side + "\nSymbol: " + _Symbol +
          "\nPrice: "  + DoubleToString(price, _Digits) +
          "\nTP: "     + DoubleToString(tp / point, 0) + " pts" +
          "\nSL: "     + DoubleToString(sl / point, 0) + " pts" +
          "\nATR: "    + DoubleToString(atr / point, 0) + " pts" +
          "\nTrades: " + IntegerToString(g_TradesToday) + "/" + IntegerToString(InpMaxTradesDay);
}

//==================================================================//
//                       BREAKOUT VALIDATION                        //
//==================================================================//

bool ValidateBreakout(int direction)
{
   // Filter 1: Body Strength
   if(InpUseBodyFilter)
   {
      double openP  = iOpen (_Symbol, PERIOD_M5, 1);
      double closeP = iClose(_Symbol, PERIOD_M5, 1);
      double highP  = iHigh (_Symbol, PERIOD_M5, 1);
      double lowP   = iLow  (_Symbol, PERIOD_M5, 1);

      double totalRange = highP - lowP;
      if(totalRange <= 0) return false;

      double bodySize = MathAbs(closeP - openP);
      double bodyPct  = (bodySize / totalRange) * 100.0;

      if(bodyPct < InpMinBodyPct) return false;
      if(direction ==  1 && closeP <= openP) return false;
      if(direction == -1 && closeP >= openP) return false;
   }

   // Filter 2: EMA Momentum
   if(InpUseMomentum)
   {
      double emaFast[], emaSlow[];
      ArraySetAsSeries(emaFast, true);
      ArraySetAsSeries(emaSlow, true);

      if(CopyBuffer(g_hEMAFast, 0, 0, 2, emaFast) < 2) return false;
      if(CopyBuffer(g_hEMASlow, 0, 0, 2, emaSlow) < 2) return false;

      if(direction ==  1 && emaFast[0] <= emaSlow[0]) return false;
      if(direction == -1 && emaFast[0] >= emaSlow[0]) return false;
   }

   return true;
}

double GetATR()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_hATR, 0, 0, 1, atr) < 1) return 0;
   return atr[0];
}

//==================================================================//
//                         BOX CALCULATION                          //
//==================================================================//

void CalculateBox()
{
   double highest = 0;
   double lowest  = DBL_MAX;

   for(int i = 1; i <= InpBoxCandles; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      double l = iLow (_Symbol, PERIOD_M5, i);
      if(h > highest) highest = h;
      if(l < lowest)  lowest  = l;
   }

   g_BoxHigh = highest;
   g_BoxLow  = lowest;
   g_BoxSize = highest - lowest;

   if(InpDrawBox) DrawBoxOnChart();
}

void DrawBoxOnChart()
{
   datetime t1 = iTime(_Symbol, PERIOD_M5, InpBoxCandles);
   datetime t2 = iTime(_Symbol, PERIOD_M5, 0) + PeriodSeconds(PERIOD_M5) * 3;

   string nameH = "BOX_HIGH";
   string nameL = "BOX_LOW";

   if(ObjectFind(0, nameH) < 0)
      ObjectCreate(0, nameH, OBJ_TREND, 0, t1, g_BoxHigh, t2, g_BoxHigh);
   ObjectSetInteger(0, nameH, OBJPROP_COLOR, CLR_UP);
   ObjectSetInteger(0, nameH, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nameH, OBJPROP_RAY_RIGHT, true);
   ObjectMove(0, nameH, 0, t1, g_BoxHigh);
   ObjectMove(0, nameH, 1, t2, g_BoxHigh);

   if(ObjectFind(0, nameL) < 0)
      ObjectCreate(0, nameL, OBJ_TREND, 0, t1, g_BoxLow, t2, g_BoxLow);
   ObjectSetInteger(0, nameL, OBJPROP_COLOR, CLR_DOWN);
   ObjectSetInteger(0, nameL, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nameL, OBJPROP_RAY_RIGHT, true);
   ObjectMove(0, nameL, 0, t1, g_BoxLow);
   ObjectMove(0, nameL, 1, t2, g_BoxLow);
}

//==================================================================//
//                        SESSION & NEWS                            //
//==================================================================//

bool IsTradingTime()
{
   if(!UseSessionTime) return true;
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour >= StartHour && dt.hour < EndHour);
}

bool CheckNewsEvent()
{
   if(!UseNewsFilter) { newsStatusTxt = "OFF"; return false; }

   MqlCalendarValue values[];
   datetime start = TimeCurrent() - (PauseAfterNews  * 60);
   datetime end   = TimeCurrent() + (PauseBeforeNews * 60);

   newsStatusTxt = "CLEAR";
   bool newsFound = false;

   if(CalendarValueHistory(values, start, end))
   {
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id, ev))
         {
            if(FilterHighImpact && ev.importance < 2) continue;
            if(ev.importance < 1) continue;
            newsFound = true;
            newsStatusTxt = "PAUSED";
            break;
         }
      }
   }
   return newsFound;
}

//==================================================================//
//                            ALERTS                                //
//==================================================================//

void SendAlertMessage(string msg)
{
   if(InpSendPush) SendNotification(msg);

   if(InpSendTelegram && InpTelegramToken != "" && InpTelegramChatID != "" &&
      InpTelegramToken != "YOUR_BOT_TOKEN_HERE")
   {
      string url     = "https://api.telegram.org/bot" + InpTelegramToken + "/sendMessage";
      string headers = "Content-Type: application/json\r\n";
      string payload = "{\"chat_id\":\"" + InpTelegramChatID + "\",\"text\":\"" + msg + "\"}";

      char data[], result[];
      string result_headers;
      StringToCharArray(payload, data, 0, StringLen(payload), CP_UTF8);

      int res = WebRequest("POST", url, headers, 3000, data, result, result_headers);
      if(res != 200) PrintFormat("Telegram error: %d", res);
   }
}

//==================================================================//
//                       TRADE TRANSACTION                          //
//==================================================================//

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;

   if(!HistoryDealSelect(dealTicket)) return;
   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT) return;

   double netProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                      HistoryDealGetDouble(dealTicket, DEAL_SWAP)   +
                      HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

   if(netProfit >= 0) { g_DayProfit += netProfit;          g_ConsecLoss = 0; }
   else               { g_DayLoss   += MathAbs(netProfit); g_ConsecLoss++;   }

   g_LastTradeTime = TimeCurrent(); // Start cooldown after close
}

//==================================================================//
//                       POSITION MANAGEMENT                        //
//==================================================================//

void ManageTrailingStop()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      double openPrice = posInfo.PriceOpen();
      double curSL     = posInfo.StopLoss();
      double curTP     = posInfo.TakeProfit();
      ulong  ticket    = posInfo.Ticket();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double profitPts = (bid - openPrice) / point;
         if(profitPts >= InpTrailStart)
         {
            double newSL = NormalizeDouble(bid - InpTrailStop * point, _Digits);
            if(newSL > curSL + InpTrailStep * point)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double profitPts = (openPrice - ask) / point;
         if(profitPts >= InpTrailStart)
         {
            double newSL = NormalizeDouble(ask + InpTrailStop * point, _Digits);
            if(curSL == 0 || newSL < curSL - InpTrailStep * point)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}

void ManageBreakEven()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      double openPrice = posInfo.PriceOpen();
      double curSL     = posInfo.StopLoss();
      double curTP     = posInfo.TakeProfit();
      ulong  ticket    = posInfo.Ticket();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double profitPts = (bid - openPrice) / point;
         double bePrice   = NormalizeDouble(openPrice + InpBreakEvenLock * point, _Digits);
         if(profitPts >= InpBreakEvenAt && curSL < bePrice)
            trade.PositionModify(ticket, bePrice, curTP);
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double profitPts = (openPrice - ask) / point;
         double bePrice   = NormalizeDouble(openPrice - InpBreakEvenLock * point, _Digits);
         if(profitPts >= InpBreakEvenAt && (curSL == 0 || curSL > bePrice))
            trade.PositionModify(ticket, bePrice, curTP);
      }
   }
}

int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
            count++;
   }
   return count;
}

void CloseAllTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
            trade.PositionClose(posInfo.Ticket(), InpMaxSlippage);
   }
}

//==================================================================//
//                         DAILY STATS                              //
//==================================================================//

void CheckDailyReset()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   static int lastDay = -1;
   if(lastDay == -1) { lastDay = dt.day; return; }

   if(dt.day != lastDay)
   {
      ResetDailyStats();
      lastDay = dt.day;
      if(InpAutoReset && !g_EmergencyStop)
      {
         g_EARunning = true;
         g_StatusMsg = "NEW DAY - ACTIVE";
      }
   }
}

void ResetDailyStats()
{
   g_DayStartBalance = accountInfo.Balance();
   g_DayProfit       = 0;
   g_DayLoss         = 0;
   g_TradesToday     = 0;
   g_ConsecLoss      = 0;
   g_BoxHigh         = 0;
   g_BoxLow          = 0;
   g_LastTradeTime   = 0;
}

bool CheckDailyLimits()
{
   if(!g_EARunning) return false;

   if(g_TradesToday >= InpMaxTradesDay)
   { g_EARunning = false; g_StatusMsg = "MAX TRADES HIT"; return false; }

   if(g_DayProfit >= InpDailyProfitTgt)
   { g_EARunning = false; g_StatusMsg = "TARGET HIT"; CloseAllTrades(); return false; }

   if(g_DayLoss >= InpDailyLossLimit)
   { g_EARunning = false; g_StatusMsg = "LOSS LIMIT HIT"; CloseAllTrades(); return false; }

   if(g_ConsecLoss >= InpMaxConsecLoss)
   { g_EARunning = false; g_StatusMsg = "CONSEC LOSS STOP"; return false; }

   double balance = accountInfo.Balance();
   if(balance > 0)
   {
      double ddPct = ((balance - accountInfo.Equity()) / balance) * 100.0;
      if(ddPct >= InpEquityDDPct)
      { g_EARunning = false; g_StatusMsg = "EQUITY DD STOP"; CloseAllTrades(); return false; }
   }
   return true;
}

bool CheckSecurity()
{
   if(InpAccountLock != 0 && AccountInfoInteger(ACCOUNT_LOGIN) != InpAccountLock)
   {
      Print("Account lock mismatch");
      return false;
   }
   if(StringLen(InpExpiryDate) > 0)
   {
      datetime exp = StringToTime(InpExpiryDate);
      if(exp > 0 && TimeCurrent() > exp)
      {
         Print("EA expired on ", InpExpiryDate);
         return false;
      }
   }
   g_SecurityPassed = true;
   return true;
}

//==================================================================//
//                          DASHBOARD                               //
//==================================================================//

void InitDashboard()
{
   ObjectsDeleteAll(0, "UI_");
   ObjectsDeleteAll(0, "L_");
   ObjectsDeleteAll(0, "V_");
}

void DrawRect(string name, int x, int y, int w, int h, color bg, color brd)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, brd);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawText(string name, int x, int y, string txt, int sz, color clr,
              string fontName="Segoe UI", bool bold=false)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString (0, name, OBJPROP_FONT, bold ? fontName + " Bold" : fontName);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void UpdateDashboard()
{
   double netPnL = g_DayProfit - g_DayLoss;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double atr    = GetATR();

   DrawRect("UI_Outer",  15, 25, 290, 340, CLR_GOLD_DIM, CLR_GOLD_DIM);
   DrawRect("UI_BG",     16, 26, 288, 338, CLR_BG, CLR_BG);
   DrawRect("UI_Header", 16, 26, 288, 35,  CLR_GOLD, CLR_GOLD);
   DrawText("UI_Title",  30, 33, "ANTU SMART BOX V16", 9, C'10,10,10', "Segoe UI Black", true);

   DrawRect("UI_Line1", 30, 95,  260, 1, CLR_BORDER, CLR_BORDER);
   DrawRect("UI_Line2", 30, 150, 260, 1, CLR_BORDER, CLR_BORDER);
   DrawRect("UI_Line3", 30, 245, 260, 1, CLR_BORDER, CLR_BORDER);

   string st;
   color  stC;
   if(g_EmergencyStop)        { st = "LOCKED";    stC = CLR_DOWN; }
   else if(!g_EARunning)      { st = "STOPPED";   stC = CLR_DOWN; }
   else if(isNewsTime)        { st = "SHIELD UP"; stC = CLR_GOLD; }
   else if(!IsTradingTime())  { st = "SLEEPING";  stC = CLR_TXT_LBL; }
   else                       { st = "ACTIVE";    stC = CLR_UP; }

   DrawText("L_Status", 30, 72, "System Status", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_Status", 165, 72, st, 8, stC, "Segoe UI", true);

   DrawText("L_Net", 30, 107, "Daily Net P/L", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_Net", 165, 107, "$" + DoubleToString(netPnL, 2), 10,
            netPnL >= 0 ? CLR_UP : CLR_DOWN, "Consolas", true);

   DrawText("L_Trades", 30, 127, "Trades Today", 8, CLR_GOLD, "Segoe UI", true);
   DrawText("V_Trades", 165, 127,
            IntegerToString(g_TradesToday) + " / " + IntegerToString(InpMaxTradesDay),
            10, CLR_TXT_VAL, "Consolas", true);

   DrawText("L_BoxHigh", 30, 162, "Box High", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_BoxHigh", 165, 162, DoubleToString(g_BoxHigh, _Digits), 9, CLR_UP, "Consolas", true);

   DrawText("L_BoxLow", 30, 182, "Box Low", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_BoxLow", 165, 182, DoubleToString(g_BoxLow, _Digits), 9, CLR_DOWN, "Consolas", true);

   double boxPts = (point > 0) ? g_BoxSize / point : 0;
   DrawText("L_BoxSize", 30, 202, "Box Size (pts)", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_BoxSize", 165, 202, DoubleToString(boxPts, 0), 9, CLR_GOLD, "Consolas", true);

   double atrPts = (point > 0) ? atr / point : 0;
   DrawText("L_ATR", 30, 222, "ATR (pts)", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_ATR", 165, 222, DoubleToString(atrPts, 0), 9, CLR_GOLD, "Consolas", true);

   DrawText("L_Limits", 30, 257, "Target / Loss", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_Limits", 165, 257,
            "$" + DoubleToString(InpDailyProfitTgt, 0) + " / -$" + DoubleToString(InpDailyLossLimit, 0),
            8, CLR_TXT_VAL, "Consolas", true);

   DrawText("L_News", 30, 277, "News Shield", 8, CLR_TXT_LBL, "Segoe UI", true);
   color newsClr = (newsStatusTxt == "CLEAR" || newsStatusTxt == "OFF") ? CLR_UP : CLR_DOWN;
   DrawText("V_News", 165, 277, newsStatusTxt, 8, newsClr, "Consolas", true);

   DrawText("L_SubStatus", 30, 297, "Bot Log", 8, CLR_TXT_LBL, "Segoe UI", true);
   DrawText("V_SubStatus", 165, 297, g_StatusMsg, 8, CLR_TXT_VAL, "Consolas", true);

   DrawText("UI_Footer", 70, 335, "POWERED BY ANTU TRADING", 7, CLR_GOLD_DIM, "Segoe UI", true);
   ChartRedraw();
}

//==================================================================//
//                       KEYBOARD SHORTCUTS                         //
//==================================================================//

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id != CHARTEVENT_KEYDOWN) return;

   if(lparam == 69) // E - Emergency Stop toggle
   {
      g_EmergencyStop = !g_EmergencyStop;
      g_EARunning     = !g_EmergencyStop;
      g_StatusMsg     = g_EmergencyStop ? "EMERGENCY STOP" : "RESUMED";
      if(g_EmergencyStop) CloseAllTrades();
      UpdateDashboard();
   }
   else if(lparam == 82) // R - Reset stats
   {
      ResetDailyStats();
      g_EARunning = true;
      g_StatusMsg = "MANUAL RESET";
      UpdateDashboard();
   }
   else if(lparam == 67) // C - Close all trades
   {
      CloseAllTrades();
      g_StatusMsg = "ALL CLOSED";
      UpdateDashboard();
   }
}
//+------------------------------------------------------------------+
