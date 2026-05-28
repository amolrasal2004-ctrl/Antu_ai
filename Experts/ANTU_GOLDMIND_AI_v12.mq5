//+------------------------------------------------------------------+
//| ANTU GOLDMIND AI v12 — DD CONTROL EDITION                        |
//| Strategy  : UT Bot + RSI + EMA + ICT Displacement Filter         |
//| v12 Fix   : Tight DD Control, Anti-Curve-Fit, Equity Guard       |
//|             Backtest Forward Gap minimized                       |
//| COPYRIGHT : Antu Trading                                         |
//+------------------------------------------------------------------+
#property copyright "Antu Trading"
#property version   "12.00"
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
input double RiskPercent         = 0.8;       // v12: Reduced from 1.0

input group "Daily Goals (v12 Tighter)"
input bool   UseDailyLimit       = true;
input double DailyProfitUSD      = 12.0;      // v12: Realistic (was 15)
input double DailyLossUSD        = 8.0;       // v12: Tight stop (was 12)
input double DailyDD_Percent     = 4.0;       // NEW: Stop if balance DD > 4%

input group "Equity Guard (NEW v12)"
input bool   UseEquityGuard      = true;       // NEW: Live floating DD check
input double EquityDD_Percent    = 3.5;        // NEW: Close all if floating DD > 3.5%

input group "Deposit Settings"
input double ActualDeposit       = 300.0;

input group "Monthly Salary System"
input bool   UseMonthlySalary    = false;
input double MonthlySalaryTarget = 100.0;
input double MonthlyMaxLoss      = 60.0;       // v12: Tighter (was 100)

input group "Smart News Filter"
input bool   UseNewsFilter       = true;
input bool   SmartNewsFilter     = true;
input int    PauseBeforeNews     = 15;
input int    PauseAfterNews      = 15;
input bool   BlockMediumImpact   = false;

input group "Session Filter"
input bool   UseSessionTime      = true;
input int    StartHour           = 8;
input int    EndHour             = 20;

input group "AI Strategy Engine (ICT) - v12 Robust"
input bool   UseDisplacement     = true;
input double Displacement_Mult   = 0.65;       // v12: Slightly stricter (was 0.55) for quality
input bool   UseTrendFilter      = true;
input double UT_Multiplier       = 1.0;
input int    ATRPeriod           = 14;
input bool   UseRSIFilter        = true;
input int    RSIPeriod           = 14;
input double RSI_Overbought      = 75.0;       // v12: Stricter (was 78) - avoid late entries
input double RSI_Oversold        = 25.0;       // v12: Stricter (was 22)

input group "Trade Execution - v12 Tight Risk"
input double SL_ATR_Mult         = 0.6;        // v12: Tighter (was 0.7)
input double TP_ATR_Mult         = 4.0;        // v12: Closer (was 4.5)

input group "Max SL Filter (HARD Loss Cap)"
input bool   UseMaxSLFilter      = true;
input double MaxSLDollar         = 12.0;       // v12: TIGHT cap (was 18)

input group "Partial TP System"
input bool   UsePartialTP        = true;
input double TP1_ATR_Mult        = 2.0;        // v12: Lock faster (was 2.5)
input double TP2_ATR_Mult        = 4.0;
input double TP1_ClosePct        = 70.0;       // v12: Lock 70% profit (was 60)

input group "Step Compounding"
input bool   UseCompounding      = true;
input double StepBalance         = 200.0;
input double BaseLot             = 0.01;
input double MaxCompoundLot      = 0.20;

input group "Emergency Lock (v12 Aggressive)"
input bool   UseEmergencyLock    = true;
input int    MaxConsecLosses     = 2;          // v12: Lock after 2 losses (was 3)
input int    LockDurationBars    = 15;         // v12: Longer cooldown (was 8)

input group "Profit Protection (v12 Tighter Trail)"
input bool   UseBreakeven        = true;
input double BE_TriggerPoints    = 60;         // v12: Faster BE (was 70)
input double BE_LockPoints       = 20;         // v12: More lock (was 15)
input bool   UseTrailing         = true;
input double Trail_Start         = 80;         // v12: Earlier (was 90)
input double Trail_Step          = 15;         // v12: Tighter (was 25)

input group "Emergency Guard"
input double MaxDrawdownStop     = 8.0;        // v12: Tighter (was 10)
input double MaxSpreadPoints     = 300;        // v12: Stricter (was 350)

input group "Trading Frequency"
input int    MaxTradesPerDay     = 6;          // v12: Less exposure (was 8)
input int    MinBarsBetweenTrades = 5;         // v12: Longer cooldown (was 3)

input int    MagicNumber         = 889900;

//================ GLOBALS =================//
int      atrHandle=INVALID_HANDLE, emaHandle=INVALID_HANDLE, rsiHandle=INVALID_HANDLE;
double   dayBalance=0, trailStop=0, gMonthBalance=0, gMonthlyProfit=0;
double   dayStartBalance=0, peakDayEquity=0;   // v12: For DD tracking
datetime lastBarTime=0, gLastBlink=0, gLockStartTime=0, gLastApiPush=0, gLastTradeBar=0;
bool     dailyTargetHit=false, isNewsTime=false, gMonthHit=false, gBlinkPhase=false;
bool     gEmergencyLocked=false, gRemoteStopped=false, gDailyDDHit=false; // NEW v12
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

//================ EMERGENCY EQUITY GUARD (NEW v12) =================//
void CloseAllPositions(string reason)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         trade.PositionClose(ticket);
     }
   Print("[v12 GUARD] All positions closed: ", reason);
  }

bool CheckEquityGuard()
  {
   if(!UseEquityGuard) return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return false;
   double floatingDD = (balance - equity) / balance * 100.0;
   if(floatingDD >= EquityDD_Percent)
     {
      CloseAllPositions("Equity DD " + DoubleToString(floatingDD,2) + "% hit");
      return true;
     }
   return false;
  }

bool CheckDailyDD()
  {
   if(DailyDD_Percent <= 0 || dayStartBalance <= 0) return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayDD = (dayStartBalance - equity) / dayStartBalance * 100.0;
   if(dayDD >= DailyDD_Percent)
     {
      gDailyDDHit = true;
      CloseAllPositions("Daily DD " + DoubleToString(dayDD,2) + "% hit");
      return true;
     }
   return false;
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

void DrawUI(bool blink, string stMsg, color stClr, double pnl, double floatPL, double ddPct)
  {
   R("BG", 5, 5, 230, 315, C'10,12,20', blink ? C'0,255,255' : C'0,150,200', 2);
   L("Ttl", 15, 12, "ANTU GOLDMIND AI v12", 9, clrCyan, true);
   R("L1", 10, 35, 220, 1, C'0,100,150', C'0,100,150', 0);

   L("S1", 15, 45, "STATUS :", 8, C'150,200,255');
   L("S2", 75, 45, stMsg, 8, stClr, true);

   L("P1", 15, 65, "Daily P&L :", 8, C'150,200,255');
   L("P2", 85, 65, "$"+DoubleToString(pnl,2), 9, pnl>=0?C'0,255,100':C'255,50,50', true);
   L("F1", 15, 85, "Float P&L :", 8, C'150,200,255');
   L("F2", 85, 85, "$"+DoubleToString(floatPL,2), 9, floatPL>=0?C'0,255,100':C'255,100,25', true);
   L("D1", 15, 105, "Day DD %  :", 8, C'150,200,255');
   L("D2", 85, 105, DoubleToString(ddPct,2)+"%", 9, ddPct<2.0?C'0,255,100':(ddPct<3.5?C'255,200,0':C'255,50,50'), true);

   R("L2", 10, 125, 220, 1, C'0,100,150', C'0,100,150', 0);

   double mpct = (MonthlySalaryTarget>0)?MathMax(0,MathMin(100,gMonthlyProfit/MonthlySalaryTarget*100.0)):0;
   L("M1", 15, 135, "MONTHLY PROGRESS", 7, C'255,215,0', true);
   R("MBG", 15, 150, 200, 10, C'20,30,50', C'30,50,90', 1);
   R("MFL", 16, 151, (int)MathMax(2, (200 * mpct / 100.0)), 8, mpct>=100?C'0,255,100':C'0,200,255', mpct>=100?C'0,255,100':C'0,200,255', 0);
   L("M2", 15, 165, "Earned: $"+DoubleToString(gMonthlyProfit,2)+" ("+IntegerToString((int)mpct)+"%)", 7, clrWhite);

   R("L3", 10, 190, 220, 1, C'0,100,150', C'0,100,150', 0);

   string nwStr = isNewsTime ? "NEWS SHIELD ACTIVE" : (UseNewsFilter ? "Smart News ON" : "News Filter OFF");
   L("N1", 15, 200, nwStr, 7, isNewsTime?C'255,100,15':C'0,255,100', isNewsTime);

   string elStr = gEmergencyLocked ? "LOCKED! Bars left: "+IntegerToString(gLockBarsRemain) : "Emrg Guard: "+IntegerToString(gConsecLosses)+"/"+IntegerToString(MaxConsecLosses);
   L("E1", 15, 220, elStr, 7, gEmergencyLocked?C'255,50,50':C'150,200,255');

   L("T1", 15, 240, "Trades Today: "+IntegerToString(gTradesToday)+"/"+IntegerToString(MaxTradesPerDay), 7, C'200,200,255');

   R("L4", 10, 270, 220, 1, C'0,100,150', C'0,100,150', 0);
   L("I1", 15, 280, _Symbol+" | M5 | Magic: "+IntegerToString(MagicNumber), 7, C'100,150,200');
  }

void UpdateDashboard(double pnl, double floatPL, double ddPct)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   string stMsg="HUNTING..."; color stClr=C'0,255,100';
   if(gDailyDDHit) { stMsg="DAILY DD STOP"; stClr=C'255,50,50'; }
   else if(floatPL < -MaxDrawdownStop) { stMsg="DD STOP!"; stClr=C'255,50,50'; }
   else if(gMonthHit) { stMsg="MONTH DONE!"; stClr=C'255,215,0'; }
   else if(dailyTargetHit) { stMsg="TARGET HIT!"; stClr=C'255,215,0'; }
   else if(gTradesToday >= MaxTradesPerDay) { stMsg="DAILY MAX HIT"; stClr=C'255,215,0'; }
   else if(gEmergencyLocked) { stMsg="EMRG LOCKED"; stClr=C'255,50,50'; }
   else if(isNewsTime) { stMsg="NEWS SHIELD"; stClr=C'255,100,0'; }
   else if(!IsTradingTime()) { stMsg="SLEEPING"; stClr=C'165,165,165'; }
   else if(PositionsTotal()>0) { stMsg="IN TRADE"; stClr=C'0,200,255'; }

   datetime now=TimeCurrent();
   if(now-gLastBlink>=2) { gBlinkPhase=!gBlinkPhase; gLastBlink=now; }
   DrawUI(gBlinkPhase, stMsg, stClr, pnl, floatPL, ddPct); ChartRedraw();
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
   dayBalance = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);  // v12
   peakDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);     // v12
   MqlDateTime dt0; TimeCurrent(dt0); gCurMonth = dt0.mon; gMonthBalance = AccountInfoDouble(ACCOUNT_BALANCE);
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
   if(IsNewDay())
     {
      dayBalance = AccountInfoDouble(ACCOUNT_EQUITY);
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);  // v12 reset
      peakDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);     // v12 reset
      gTradesToday = 0;
      gDailyDDHit = false;                                   // v12 reset
     }
   IsNewMonth();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > peakDayEquity) peakDayEquity = equity;
   double pnl = equity - dayBalance, floatPL = 0;
   double dayDDPct = (dayStartBalance > 0) ? MathMax(0, (dayStartBalance - equity) / dayStartBalance * 100.0) : 0;

   if(UseDailyLimit && (pnl >= DailyProfitUSD || pnl <= -DailyLossUSD)) dailyTargetHit = true;

   for(int i=PositionsTotal()-1; i>=0; i--)
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         floatPL += PositionGetDouble(POSITION_PROFIT);

   isNewsTime = CheckHighImpactNews();
   ManageOpenTrades();

   // v12: Equity guard runs every tick
   CheckEquityGuard();
   CheckDailyDD();

   static datetime lastUIDraw = 0;
   datetime current_time = TimeCurrent();
   if(current_time - lastUIDraw >= 1) { UpdateDashboard(pnl, floatPL, dayDDPct); lastUIDraw = current_time; }

   if(gRemoteStopped || gDailyDDHit || floatPL < -MaxDrawdownStop || dailyTargetHit || gMonthHit || isNewsTime || !IsTradingTime() || (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpreadPoints) return;

   if(gTradesToday >= MaxTradesPerDay) return;

   datetime timeArr[]; if(CopyTime(_Symbol, PERIOD_M5, 0, 1, timeArr)<=0 || timeArr[0] == lastBarTime) return; lastBarTime = timeArr[0];

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
      // v12: Aggressive lot reduction after losses (50% cut)
      if(gConsecLosses > 0) tradeLot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), tradeLot * 0.5);

      if(UseMaxSLFilter)
        {
         double tVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), tSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         if(tSz > 0 && pt > 0 && (tradeLot * (slDist / pt) * (tVal / (tSz / pt))) > MaxSLDollar) return;
        }

      bool sent = false;
      if(buySignal)  sent = trade.Buy(tradeLot, _Symbol, 0, NormalizeDouble(c1 - slDist, _Digits), NormalizeDouble(c1 + tpDist, _Digits), "ANTU AI v12");
      if(sellSignal) sent = trade.Sell(tradeLot, _Symbol, 0, NormalizeDouble(c1 + slDist, _Digits), NormalizeDouble(c1 - tpDist, _Digits), "ANTU AI v12");

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

//================ SMART NEWS FILTER =================//
bool IsRelevantCurrency(string country)
  {
   string sym = _Symbol;
   StringToUpper(sym);
   StringToUpper(country);

   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
     {
      if(country == "US" || country == "EU" || country == "USD" || country == "EUR") return true;
      return false;
     }

   if(StringLen(sym) >= 6)
     {
      string base  = StringSubstr(sym, 0, 3);
      string quote = StringSubstr(sym, 3, 3);
      if(country == base || country == quote) return true;
      if((country=="US" && (base=="USD" || quote=="USD")) ||
         (country=="EU" && (base=="EUR" || quote=="EUR")) ||
         (country=="GB" && (base=="GBP" || quote=="GBP")) ||
         (country=="JP" && (base=="JPY" || quote=="JPY"))) return true;
      return false;
     }
   return true;
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

         bool importanceMatch = (ev.importance >= CALENDAR_IMPORTANCE_HIGH) ||
                                (BlockMediumImpact && ev.importance >= CALENDAR_IMPORTANCE_MODERATE);
         if(!importanceMatch) continue;

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
