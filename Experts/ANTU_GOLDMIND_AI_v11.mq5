//+------------------------------------------------------------------+
//| ANTU GOLDMIND AI v11 — SMART AGGRESSIVE EDITION                  |
//| Strategy  : UT Bot + RSI + EMA + ICT Displacement Filter         |
//| v11 Fix   : Smart News Filter (USD/EUR/XAU only)                 |
//|             More Trade Opportunities, Tight Loss Control         |
//| COPYRIGHT : Antu Trading                                         |
//+------------------------------------------------------------------+
#property copyright "Antu Trading"
#property version   "11.00"
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//================ OWNER SETTINGS =================//
long   Licensed_Account_ID = 0;
const  string MY_SECRET_PASS = "AMSE@1988";

//================ INPUTS =================//
input group "Security"
input string EA_Password         = "";

input group "Money Management"
input bool   UseAutoLot          = false;
input double FixLotSize          = 0.01;
input double RiskPercent         = 1.0;

input group "Daily Goals"
input bool   UseDailyLimit       = true;
input double DailyProfitUSD      = 15.0;
input double DailyLossUSD        = 12.0;     // v11: Tighter loss cap (was 15)

input group "Deposit Settings"
input double ActualDeposit       = 300.0;

input group "Monthly Salary System"
input bool   UseMonthlySalary    = false;
input double MonthlySalaryTarget = 100.0;
input double MonthlyMaxLoss      = 100.0;

input group "Smart News Filter (v11)"
input bool   UseNewsFilter       = true;
// v11: Smart filter only blocks news for traded currencies (XAU/USD/EUR)
input bool   SmartNewsFilter     = true;     // NEW: Only block relevant currency news
input int    PauseBeforeNews     = 15;       // v11: Reduced from 30
input int    PauseAfterNews      = 15;       // v11: Reduced from 30
input bool   BlockMediumImpact   = false;    // NEW: Only HIGH news by default

input group "Session Filter"
input bool   UseSessionTime      = true;
input int    StartHour           = 8;
input int    EndHour             = 20;

input group "AI Strategy Engine (ICT) - v11 Tuned"
input bool   UseDisplacement     = true;
input double Displacement_Mult   = 0.55;     // v11: Lower (was 0.8) = more signals
input bool   UseTrendFilter      = true;
input double UT_Multiplier       = 1.0;
input int    ATRPeriod           = 14;
input bool   UseRSIFilter        = true;
input int    RSIPeriod           = 14;
input double RSI_Overbought      = 78.0;     // v11: Slightly tighter (was 80)
input double RSI_Oversold        = 22.0;     // v11: Slightly tighter (was 20)

input group "Trade Execution - v11 Tighter Risk"
input double SL_ATR_Mult         = 0.7;      // v11: Tighter SL (was 0.8)
input double TP_ATR_Mult         = 4.5;      // v11: Slightly closer TP (was 5.0)

input group "Max SL Filter (Hard Loss Cap)"
input bool   UseMaxSLFilter      = true;
input double MaxSLDollar         = 18.0;     // v11: Tighter (was 25)

input group "Partial TP System"
input bool   UsePartialTP        = true;
input double TP1_ATR_Mult        = 2.5;      // v11: Faster partial (was 3.5)
input double TP2_ATR_Mult        = 4.5;      // v11: Match TP_ATR_Mult
input double TP1_ClosePct        = 60.0;     // v11: Lock more profit (was 50)

input group "Step Compounding"
input bool   UseCompounding      = true;
input double StepBalance         = 200.0;
input double BaseLot             = 0.01;
input double MaxCompoundLot      = 0.20;

input group "Emergency Lock"
input bool   UseEmergencyLock    = true;
input int    MaxConsecLosses     = 3;
input int    LockDurationBars    = 8;        // v11: Reduced from 10

input group "Profit Protection"
input bool   UseBreakeven        = true;
input double BE_TriggerPoints    = 70;       // v11: Faster BE (was 90)
input double BE_LockPoints       = 15;       // v11: Slightly more (was 10)
input bool   UseTrailing         = true;
input double Trail_Start         = 90;       // v11: Earlier trail (was 100)
input double Trail_Step          = 25;       // v11: Wider step (was 20)

input group "Emergency Guard"
input double MaxDrawdownStop     = 10.0;     // v11: Tighter (was 12)
input double MaxSpreadPoints     = 350;

input group "Trading Frequency (NEW v11)"
input int    MaxTradesPerDay     = 8;        // NEW: Cap to control risk
input int    MinBarsBetweenTrades = 3;       // NEW: Cooldown between entries

input int    MagicNumber         = 889900;

//================ GLOBALS =================//
int      atrHandle=INVALID_HANDLE, emaHandle=INVALID_HANDLE, rsiHandle=INVALID_HANDLE;
double   dayBalance=0, trailStop=0, gMonthBalance=0, gMonthlyProfit=0;
datetime lastBarTime=0, gLastBlink=0, gLockStartTime=0, gLastApiPush=0, gLastTradeBar=0;
bool     dailyTargetHit=false, isNewsTime=false, gMonthHit=false, gBlinkPhase=false;
bool     gEmergencyLocked=false, gRemoteStopped=false;
int      gCurMonth=-1, gMonthTrades=0, gMonthWins=0, gConsecLosses=0, gLockBarsRemain=0;
int      gTradesToday=0;
string   API_URL = "http://13.220.15.179/goldmind/api/mt5_data.php";
int      API_INTERVAL_SEC = 5;

//================ LOT CALCULATION =================//
double ComputeLot(double slDistPoints)
  {
   if(!UseAutoLot) return FixLotSize;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize==0 || point==0) return FixLotSize;

   double lot = (equity * (RiskPercent/100.0)) / (slDistPoints * (tickValue/(tickSize/point)));
   double maxLotBySL = MaxSLDollar / (slDistPoints * (tickValue/(tickSize/point)));
   lot = MathMin(lot, maxLotBySL);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), MaxCompoundLot);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, MathFloor(lot/step)*step));
   return lot;
  }

//================ DRAW UI =================//
void R(string n,int x,int y,int w,int h,color bg,color brd,int bw=1)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w); ObjectSetInteger(0,n,OBJPROP_YSIZE,h); ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT); ObjectSetInteger(0,n,OBJPROP_COLOR,brd); ObjectSetInteger(0,n,OBJPROP_WIDTH,bw);
   ObjectSetInteger(0,n,OBJPROP_BACK,false); ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
  }
void L(string n,int x,int y,string txt,int sz,color clr,bool bold=false)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,n,OBJPROP_TEXT,txt); ObjectSetInteger(0,n,OBJPROP_COLOR,clr); ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,n,OBJPROP_FONT,bold?"Arial Black":"Calibri"); ObjectSetInteger(0,n,OBJPROP_BACK,false); ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
  }

void DrawUI(bool blink, string stMsg, color stClr, double pnl, double floatPL)
  {
   R("BG", 5, 5, 230, 295, C'10,12,20', blink ? C'0,255,255' : C'0,150,200', 2);
   L("Ttl", 15, 12, "ANTU GOLDMIND AI v11", 9, clrCyan, true);
   R("L1", 10, 35, 220, 1, C'0,100,150', C'0,100,150', 0);

   L("S1", 15, 45, "STATUS :", 8, C'150,200,255');
   L("S2", 75, 45, stMsg, 8, stClr, true);

   L("P1", 15, 65, "Daily P&L :", 8, C'150,200,255');
   L("P2", 85, 65, "$"+DoubleToString(pnl,2), 9, pnl>=0?C'0,255,100':C'255,50,50', true);
   L("F1", 15, 85, "Float P&L :", 8, C'150,200,255');
   L("F2", 85, 85, "$"+DoubleToString(floatPL,2), 9, floatPL>=0?C'0,255,100':C'255,100,25', true);

   R("L2", 10, 110, 220, 1, C'0,100,150', C'0,100,150', 0);

   double mpct = (MonthlySalaryTarget>0)?MathMax(0,MathMin(100,gMonthlyProfit/MonthlySalaryTarget*100.0)):0;
   L("M1", 15, 120, "MONTHLY PROGRESS", 7, C'255,215,0', true);
   R("MBG", 15, 135, 200, 10, C'20,30,50', C'30,50,90', 1);
   R("MFL", 16, 136, (int)MathMax(2, (200 * mpct / 100.0)), 8, mpct>=100?C'0,255,100':C'0,200,255', mpct>=100?C'0,255,100':C'0,200,255', 0);
   L("M2", 15, 150, "Earned: $"+DoubleToString(gMonthlyProfit,2)+" ("+IntegerToString((int)mpct)+"%)", 7, clrWhite);

   R("L3", 10, 175, 220, 1, C'0,100,150', C'0,100,150', 0);

   string nwStr = isNewsTime ? "NEWS SHIELD ACTIVE" : (UseNewsFilter ? "Smart News ON" : "News Filter OFF");
   L("N1", 15, 185, nwStr, 7, isNewsTime?C'255,100,15':C'0,255,100', isNewsTime);

   string elStr = gEmergencyLocked ? "LOCKED! Bars left: "+IntegerToString(gLockBarsRemain) : "Emrg Guard: "+IntegerToString(gConsecLosses)+"/"+IntegerToString(MaxConsecLosses);
   L("E1", 15, 205, elStr, 7, gEmergencyLocked?C'255,50,50':C'150,200,255');

   L("T1", 15, 222, "Trades Today: "+IntegerToString(gTradesToday)+"/"+IntegerToString(MaxTradesPerDay), 7, C'200,200,255');

   R("L4", 10, 248, 220, 1, C'0,100,150', C'0,100,150', 0);
   L("I1", 15, 258, _Symbol+" | M5 | Magic: "+IntegerToString(MagicNumber), 7, C'100,150,200');
  }

void UpdateDashboard(double pnl, double floatPL)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   string stMsg="HUNTING..."; color stClr=C'0,255,100';
   if(floatPL < -MaxDrawdownStop) { stMsg="DD STOP!"; stClr=C'255,50,50'; }
   else if(gMonthHit) { stMsg="MONTH DONE!"; stClr=C'255,215,0'; }
   else if(dailyTargetHit) { stMsg="TARGET HIT!"; stClr=C'255,215,0'; }
   else if(gTradesToday >= MaxTradesPerDay) { stMsg="DAILY MAX HIT"; stClr=C'255,215,0'; }
   else if(gEmergencyLocked) { stMsg="EMRG LOCKED"; stClr=C'255,50,50'; }
   else if(isNewsTime) { stMsg="NEWS SHIELD"; stClr=C'255,100,0'; }
   else if(!IsTradingTime()) { stMsg="SLEEPING"; stClr=C'165,165,165'; }
   else if(PositionsTotal()>0) { stMsg="IN TRADE"; stClr=C'0,200,255'; }

   datetime now=TimeCurrent();
   if(now-gLastBlink>=2) { gBlinkPhase=!gBlinkPhase; gLastBlink=now; }
   DrawUI(gBlinkPhase, stMsg, stClr, pnl, floatPL); ChartRedraw();
  }

//================ TRADE MANAGEMENT =================//
void ManageOpenTrades()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN), currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP), currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double currentLot = PositionGetDouble(POSITION_VOLUME), point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      long posType = PositionGetInteger(POSITION_TYPE); string comment = PositionGetString(POSITION_COMMENT);

      // Partial TP
      if(UsePartialTP && comment != "PTP1")
        {
         double atrArr[]; if(CopyBuffer(atrHandle,0,1,1,atrArr)>0)
           {
            double tp1Dist = atrArr[0] * TP1_ATR_Mult; bool tp1Hit = false;
            if((posType==POSITION_TYPE_BUY && currentPrice >= openPrice + tp1Dist) ||
               (posType==POSITION_TYPE_SELL && currentPrice <= openPrice - tp1Dist)) tp1Hit=true;
            if(tp1Hit)
              {
               double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               double closeLot = MathFloor((currentLot * TP1_ClosePct/100.0)/lotStep)*lotStep;
               if(closeLot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) && closeLot < currentLot)
                  trade.PositionClosePartial(ticket, closeLot);
              }
           }
        }

      if(!PositionSelectByTicket(ticket)) continue;
      currentSL = PositionGetDouble(POSITION_SL); currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

      // Breakeven
      if(UseBreakeven)
        {
         if(posType==POSITION_TYPE_BUY && currentPrice > openPrice + BE_TriggerPoints*point)
           {
            double newSL = openPrice + BE_LockPoints*point;
            if(currentSL < newSL) trade.PositionModify(ticket, newSL, currentTP);
           }
         if(posType==POSITION_TYPE_SELL && currentPrice < openPrice - BE_TriggerPoints*point)
           {
            double newSL = openPrice - BE_LockPoints*point;
            if(currentSL > newSL || currentSL == 0) trade.PositionModify(ticket, newSL, currentTP);
           }
        }

      // Trailing
      if(UseTrailing)
        {
         if(posType==POSITION_TYPE_BUY && currentPrice > openPrice + Trail_Start*point)
           {
            double newSL = currentPrice - Trail_Step*point;
            if(newSL > currentSL) trade.PositionModify(ticket, newSL, currentTP);
           }
         if(posType==POSITION_TYPE_SELL && currentPrice < openPrice - Trail_Start*point)
           {
            double newSL = currentPrice + Trail_Step*point;
            if(newSL < currentSL || currentSL == 0) trade.PositionModify(ticket, newSL, currentTP);
           }
        }
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal) && HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber)
     {
      ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_INOUT)
        {
         double pr = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         gMonthlyProfit += pr; gMonthTrades++;
         if(pr > 0) { gMonthWins++; gConsecLosses = 0; if(gEmergencyLocked){ gEmergencyLocked=false; gLockBarsRemain=0; } }
         else if(pr < 0) { gConsecLosses++; if(UseEmergencyLock && gConsecLosses >= MaxConsecLosses && !gEmergencyLocked){ gEmergencyLocked=true; gLockBarsRemain=LockDurationBars; } }
         if(UseMonthlySalary && (gMonthlyProfit >= MonthlySalaryTarget || gMonthlyProfit <= -MonthlyMaxLoss)) gMonthHit = true;
        }
     }
  }

//================ LIVE DATA PUSH =================//
void PushLiveData()
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if(TimeCurrent() - gLastApiPush < API_INTERVAL_SEC) return;
   gLastApiPush = TimeCurrent();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY), balance = AccountInfoDouble(ACCOUNT_BALANCE), dailyPnl = equity - dayBalance;
   int openTrades = 0; double openProfit = 0, lotSize = 0, positionSL = 0, positionTP = 0; string tradeSide = "NONE";
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      openTrades++; openProfit += PositionGetDouble(POSITION_PROFIT); lotSize = PositionGetDouble(POSITION_VOLUME);
      positionSL = PositionGetDouble(POSITION_SL); positionTP = PositionGetDouble(POSITION_TP);
      tradeSide = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
     }

   string status = "HUNTING";
   if(gEmergencyLocked) status = "LOCKED"; else if(dailyTargetHit) status = "TARGET HIT"; else if(gMonthHit) status = "MONTH DONE";
   else if(isNewsTime) status = "NEWS SHIELD"; else if(!IsTradingTime()) status = "OFF SESSION"; else if(openTrades > 0) status = tradeSide + " ACTIVE";

   string json = StringFormat("{\"magic\":%d,\"symbol\":\"%s\",\"equity\":%.2f,\"balance\":%.2f,\"daily_pnl\":%.2f,\"open_trades\":%d,\"open_profit\":%.2f,\"trade_side\":\"%s\",\"lot_size\":%.2f,\"sl\":%.5f,\"tp\":%.5f,\"monthly_profit\":%.2f,\"month_trades\":%d,\"month_wins\":%d,\"consec_losses\":%d,\"status\":\"%s\"}",
      MagicNumber, _Symbol, equity, balance, dailyPnl, openTrades, openProfit, tradeSide, lotSize, positionSL, positionTP, gMonthlyProfit, gMonthTrades, gMonthWins, gConsecLosses, status);

   char post[], result[]; string headers = "Content-Type: application/json\r\n"; StringToCharArray(json, post, 0, StringLen(json)); ResetLastError();
   if(WebRequest("POST", API_URL + "?action=push", headers, 5000, post, result, headers) != -1)
     {
      string resp = CharArrayToString(result);
      if(StringFind(resp, "\"STOP\"") >= 0 && !gRemoteStopped) { gRemoteStopped = true; Alert("ANTU GOLDMIND AI — REMOTE STOP!"); }
      else if(StringFind(resp, "\"START\"") >= 0 && gRemoteStopped) { gRemoteStopped = false; Alert("ANTU GOLDMIND AI — REMOTE START!"); }
     }
  }

//================ INIT / DEINIT =================//
int OnInit()
  {
   if(EA_Password != MY_SECRET_PASS) return INIT_FAILED;
   trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(10);
   dayBalance = AccountInfoDouble(ACCOUNT_EQUITY); MqlDateTime dt0; TimeCurrent(dt0); gCurMonth = dt0.mon; gMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   atrHandle = iATR(_Symbol, PERIOD_M5, ATRPeriod); emaHandle = iMA(_Symbol, PERIOD_M5, 200, 0, MODE_EMA, PRICE_CLOSE); rsiHandle = iRSI(_Symbol, PERIOD_M5, RSIPeriod, PRICE_CLOSE);
   if(atrHandle==INVALID_HANDLE || emaHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE) return INIT_FAILED;
   ObjectsDeleteAll(0,"BG"); ObjectsDeleteAll(0,"Ttl");
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason) { IndicatorRelease(atrHandle); IndicatorRelease(emaHandle); IndicatorRelease(rsiHandle); ObjectsDeleteAll(0); ChartRedraw(); }

//================ ON TICK =================//
void OnTick()
  {
   PushLiveData();
   if(IsNewDay()) { dayBalance = AccountInfoDouble(ACCOUNT_EQUITY); gTradesToday = 0; }
   IsNewMonth();
   double pnl = AccountInfoDouble(ACCOUNT_EQUITY) - dayBalance, floatPL = 0;
   if(UseDailyLimit && (pnl >= DailyProfitUSD || pnl <= -DailyLossUSD)) dailyTargetHit = true;
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         floatPL += PositionGetDouble(POSITION_PROFIT);

   isNewsTime = CheckHighImpactNews();
   ManageOpenTrades();

   static datetime lastUIDraw = 0;
   datetime current_time = TimeCurrent();
   if(current_time - lastUIDraw >= 1) { UpdateDashboard(pnl, floatPL); lastUIDraw = current_time; }

   if(gRemoteStopped || floatPL < -MaxDrawdownStop || dailyTargetHit || gMonthHit || isNewsTime || !IsTradingTime() || (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpreadPoints) return;

   // v11: Daily trade cap
   if(gTradesToday >= MaxTradesPerDay) return;

   datetime timeArr[]; if(CopyTime(_Symbol, PERIOD_M5, 0, 1, timeArr)<=0 || timeArr[0] == lastBarTime) return; lastBarTime = timeArr[0];

   // v11: Cooldown between trades
   if(gLastTradeBar > 0 && (lastBarTime - gLastTradeBar) < (MinBarsBetweenTrades * PeriodSeconds(PERIOD_M5))) return;

   if(gEmergencyLocked && UseEmergencyLock) { if(gLockBarsRemain > 0) gLockBarsRemain--; if(gLockBarsRemain <= 0) { gEmergencyLocked = false; gConsecLosses = 0; } else return; }

   double atr[], ema[], close[], open[], rsiArr[];
   if(CopyBuffer(atrHandle, 0, 1, 1, atr)<=0 || CopyBuffer(emaHandle, 0, 1, 1, ema)<=0 || CopyBuffer(rsiHandle, 0, 0, 1, rsiArr)<=0 || CopyClose(_Symbol, PERIOD_M5, 1, 2, close)<=0 || CopyOpen(_Symbol, PERIOD_M5, 1, 2, open)<=0) return;

   double c1 = close[1], c2 = close[0], nLoss = UT_Multiplier * atr[0];
   bool hasDisplacement = !UseDisplacement || (MathAbs(c1 - open[1]) > (atr[0] * Displacement_Mult));

   if(trailStop == 0) trailStop = c1;
   if(c1 > trailStop && c2 > trailStop) trailStop = MathMax(trailStop, c1 - nLoss);
   else if(c1 < trailStop && c2 < trailStop) trailStop = MathMin(trailStop, c1 + nLoss);
   else if(c1 > trailStop && c2 < trailStop) trailStop = c1 - nLoss;
   else if(c1 < trailStop && c2 > trailStop) trailStop = c1 + nLoss;

   bool buySignal = (c1 > trailStop && c2 <= trailStop), sellSignal = (c1 < trailStop && c2 >= trailStop);
   if(UseTrendFilter) { if(buySignal && c1 < ema[0]) buySignal = false; if(sellSignal && c1 > ema[0]) sellSignal = false; }
   if(UseRSIFilter) { if(buySignal && rsiArr[0] > RSI_Overbought) buySignal = false; if(sellSignal && rsiArr[0] < RSI_Oversold) sellSignal = false; }

   if(PositionsTotal() == 0 && hasDisplacement && (buySignal || sellSignal))
     {
      double slDist = atr[0] * SL_ATR_Mult;
      double tpDist = atr[0] * (UsePartialTP ? TP2_ATR_Mult : TP_ATR_Mult);
      double tradeLot = ComputeLot(slDist / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      // Reduce size after consecutive losses
      if(gConsecLosses > 0) tradeLot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), tradeLot * 0.7); // v11: more aggressive cut

      if(UseMaxSLFilter)
        {
         double tVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), tSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         if(tSz > 0 && pt > 0 && (tradeLot * (slDist / pt) * (tVal / (tSz / pt))) > MaxSLDollar) return;
        }

      bool sent = false;
      if(buySignal)  sent = trade.Buy(tradeLot, _Symbol, 0, NormalizeDouble(c1 - slDist, _Digits), NormalizeDouble(c1 + tpDist, _Digits), "ANTU AI v11");
      if(sellSignal) sent = trade.Sell(tradeLot, _Symbol, 0, NormalizeDouble(c1 + slDist, _Digits), NormalizeDouble(c1 - tpDist, _Digits), "ANTU AI v11");

      if(sent) { gTradesToday++; gLastTradeBar = lastBarTime; }
     }
  }

//================ UTILS =================//
bool IsNewDay()
  {
   MqlDateTime dt; TimeCurrent(dt); static int prevDay = -1;
   if(dt.day != prevDay) { prevDay = dt.day; dailyTargetHit = false; gConsecLosses = 0; gEmergencyLocked = false; return true; }
   return false;
  }
bool IsNewMonth()
  {
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.mon != gCurMonth) { gCurMonth = dt.mon; gMonthlyProfit = 0; gMonthTrades = 0; gMonthWins = 0; gMonthHit = false; gMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE); return true; }
   return false;
  }
bool IsTradingTime()
  {
   if(!UseSessionTime) return true;
   MqlDateTime dt; TimeCurrent(dt); return (dt.hour >= StartHour && dt.hour < EndHour);
  }

//================ SMART NEWS FILTER (v11) =================//
// Only blocks news for currencies relevant to the traded symbol.
// For XAUUSD: USD + EUR (major drivers). For other symbols, derives from symbol name.
bool IsRelevantCurrency(string country)
  {
   string sym = _Symbol;
   StringToUpper(sym);
   StringToUpper(country);

   // XAU/Gold is highly sensitive to USD and EUR news
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
     {
      if(country == "US" || country == "EU" || country == "USD" || country == "EUR") return true;
      return false;
     }

   // Generic: extract base/quote from symbol (e.g., EURUSD -> EUR, USD)
   if(StringLen(sym) >= 6)
     {
      string base  = StringSubstr(sym, 0, 3);
      string quote = StringSubstr(sym, 3, 3);
      if(country == base || country == quote) return true;
      // Country-code mapping
      if((country=="US" && (base=="USD" || quote=="USD")) ||
         (country=="EU" && (base=="EUR" || quote=="EUR")) ||
         (country=="GB" && (base=="GBP" || quote=="GBP")) ||
         (country=="JP" && (base=="JPY" || quote=="JPY"))) return true;
      return false;
     }
   return true; // fallback: block everything if we can't identify
  }

bool CheckHighImpactNews()
  {
   if(!UseNewsFilter || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return false;
   MqlCalendarValue values[]; datetime tNow = TimeCurrent();
   if(CalendarValueHistory(values, tNow - (PauseAfterNews*60), tNow + (PauseBeforeNews*60)))
     {
      for(int i=0; i<ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;

         // v11: Importance check (HIGH always, MEDIUM only if enabled)
         bool importanceMatch = (ev.importance >= CALENDAR_IMPORTANCE_HIGH) ||
                                (BlockMediumImpact && ev.importance >= CALENDAR_IMPORTANCE_MODERATE);
         if(!importanceMatch) continue;

         // v11: Smart filter — only block if currency is relevant
         if(SmartNewsFilter)
           {
            MqlCalendarCountry country;
            if(CalendarCountryById(ev.country_id, country))
              {
               if(!IsRelevantCurrency(country.code)) continue;
              }
           }
         return true;
        }
     }
   return false;
  }
