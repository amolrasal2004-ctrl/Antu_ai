//+------------------------------------------------------------------+
//| ANTU GOLDMIND AI v10 — PROFESSIONAL EDITION                      |
//| Strategy  : UT Bot + RSI + EMA + ICT Displacement Filter         |
//| Features  : License, MaxSL Cap, Notifications, DD Guard          |
//| COPYRIGHT : ANTU Trading                                         |
//+------------------------------------------------------------------+
#property copyright "ANTU Trading"
#property version   "10.10"
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//================ LICENSE & PASSWORD SYSTEM =========//
input group "=== License & Security ==="
input string   InpPassword           = "";       // EA Password (required)
input string   InpLicenseKey         = "";       // License Key (get from ANTU Trading)
input int      InpTrialDays          = 7;        // Trial period days (0=no trial)
input string   InpAdminPassword      = "";       // Admin Password (key generator)

//================ MONEY MANAGEMENT =================//
input group "=== Money Management ==="
input bool     UseAutoLot           = false;
input double   FixLotSize           = 0.01;
input double   RiskPercent          = 1.0;      // % of equity risk per trade
input double   MaxSLDollar          = 5.0;      // Max SL $ per trade (hard cap)

//================ DAILY GOALS =====================//
input group "=== Daily Goals ==="
input bool     UseDailyLimit        = true;
input double   DailyProfitUSD       = 15.0;
input double   DailyLossUSD         = 15.0;

//================ MONTHLY SALARY =================//
input group "=== Monthly Salary System ==="
input bool     UseMonthlySalary     = false;
input double   MonthlySalaryTarget  = 100.0;
input double   MonthlyMaxLoss       = 100.0;


//================ NEWS FILTER =====================//
input group "=== News Filter ==="
input bool     UseNewsFilter        = true;
input int      PauseBeforeNews      = 30;
input int      PauseAfterNews       = 30;

//================ SESSION FILTER ==================//
input group "=== Session Filter ==="
input bool     UseSessionTime       = true;
input int      StartHour            = 8;
input int      EndHour              = 20;

//================ AI STRATEGY ENGINE (ICT) ========//
input group "=== AI Strategy Engine (ICT) ==="
input bool     UseDisplacement      = true;
input double   Displacement_Mult    = 0.8;
input bool     UseTrendFilter       = true;
input double   UT_Multiplier        = 1.0;
input int      ATRPeriod            = 14;
input bool     UseRSIFilter         = true;
input int      RSIPeriod            = 14;
input double   RSI_Overbought       = 80.0;
input double   RSI_Oversold         = 20.0;

//================ TRADE EXECUTION =================//
input group "=== Trade Execution ==="
input double   SL_ATR_Mult          = 0.8;
input double   TP_ATR_Mult          = 5.0;

//================ PARTIAL TP ======================//
input group "=== Partial TP System ==="
input bool     UsePartialTP         = true;
input double   TP1_ATR_Mult         = 3.5;
input double   TP2_ATR_Mult         = 5.0;
input double   TP1_ClosePct         = 50.0;

//================ STEP COMPOUNDING ================//
input group "=== Step Compounding ==="
input bool     UseCompounding       = true;
input double   StepBalance          = 200.0;
input double   BaseLot              = 0.01;
input double   MaxCompoundLot       = 0.20;


//================ EMERGENCY LOCK ==================//
input group "=== Emergency Lock ==="
input bool     UseEmergencyLock     = true;
input int      MaxConsecLosses      = 3;
input int      LockDurationBars     = 10;

//================ PROFIT PROTECTION ===============//
input group "=== Profit Protection ==="
input bool     UseBreakeven         = true;
input double   BE_TriggerPoints     = 90;
input double   BE_LockPoints        = 10;
input bool     UseTrailing          = true;
input double   Trail_Start          = 100;
input double   Trail_Step           = 20;

//================ EMERGENCY GUARD =================//
input group "=== Emergency Guard ==="
input double   MaxDrawdownStop      = 12.0;
input double   MaxSpreadPoints      = 350;

//================ NOTIFICATIONS ===================//
input group "=== Mobile Notifications ==="
input bool     InpSendPushNotify    = true;
input bool     InpSendAlert         = false;
input bool     InpNotifyOnTrade     = true;
input bool     InpNotifyOnBlock     = false;

input int      MagicNumber          = 889900;

//================ DASHBOARD COLORS ================//
#define CLR_BG_OUTER  C'150,120,40'
#define CLR_BG_INNER  C'10,12,20'
#define CLR_HEADER    C'0,200,255'
#define CLR_TXT_MUTED C'150,200,255'
#define CLR_TXT_WHITE C'250,250,255'
#define CLR_PROFIT    C'0,255,100'
#define CLR_LOSS      C'255,50,50'
#define CLR_WARN      C'255,100,0'

//--- LICENSE CONSTANTS
#define LICENSE_MASTER_PASS   "ANTU2024PRO"
#define LICENSE_ADMIN_PASS    "ANTUADMIN99"
#define LICENSE_SALT          "ANTU_GOLD_"


//================ GLOBALS =================//
int      atrHandle=INVALID_HANDLE, emaHandle=INVALID_HANDLE, rsiHandle=INVALID_HANDLE;
double   dayBalance=0, trailStop=0, gMonthBalance=0, gMonthlyProfit=0;
datetime lastBarTime=0, gLastBlink=0, gLockStartTime=0;
bool     dailyTargetHit=false, isNewsTime=false, gMonthHit=false, gBlinkPhase=false;
bool     gEmergencyLocked=false;
int      gCurMonth=-1, gMonthTrades=0, gMonthWins=0, gConsecLosses=0, gLockBarsRemain=0;
bool     license_valid=false;
datetime trial_start_time=0;
bool     admin_mode=false;

//+------------------------------------------------------------------+
//| NOTIFICATION SYSTEM                                              |
//+------------------------------------------------------------------+
void SendNotify(string msg){
   if(InpSendPushNotify) SendNotification(msg);
   if(InpSendAlert) Alert(msg);
   Print(msg);
}

void NotifyTradeOpen(string direction, double lot){
   if(!InpNotifyOnTrade) return;
   SendNotify("ANTU AI: "+direction+" | Lot="+DoubleToString(lot,2)+" | "+_Symbol);
}

void NotifyBlock(string reason){
   if(!InpNotifyOnBlock) return;
   static string lastReason="";
   if(reason==lastReason) return;
   lastReason=reason;
   SendNotify("ANTU AI: BLOCKED - "+reason);
}

//+------------------------------------------------------------------+
//| LICENSE & PASSWORD SYSTEM                                        |
//+------------------------------------------------------------------+
string GenerateLicenseKey(long accountNum){
   string raw = LICENSE_SALT + IntegerToString(accountNum);
   int hash = 0;
   for(int i=0; i<StringLen(raw); i++){
      hash = hash * 31 + StringGetCharacter(raw, i);
      hash = hash % 999999;
   }
   if(hash < 0) hash = -hash;
   return "ANTU-" + IntegerToString(hash, 6, '0');
}

void ShowKeyGeneratorPanel(){
   long accNum = AccountInfoInteger(ACCOUNT_LOGIN);
   string key = GenerateLicenseKey(accNum);
   Alert("Account: "+IntegerToString(accNum)+"\nLicense Key: "+key);
   Print("=== KEY: Account=",accNum," Key=",key," ===");
   Comment("ANTU KEY GENERATOR\nAccount: "+IntegerToString(accNum)+"\nKey: "+key);
}

bool ValidatePassword(){
   if(InpAdminPassword == LICENSE_ADMIN_PASS){ admin_mode=true; return true; }
   if(StringLen(InpPassword)==0){ Print("ERROR: Password required!"); return false; }
   if(InpPassword != LICENSE_MASTER_PASS){ Print("ERROR: Invalid password!"); return false; }
   return true;
}

bool ValidateLicense(){
   if(admin_mode) return true;
   long accNum = AccountInfoInteger(ACCOUNT_LOGIN);
   if(StringLen(InpLicenseKey)>0){
      if(InpLicenseKey == GenerateLicenseKey(accNum)){ license_valid=true; return true; }
   }
   if(InpTrialDays > 0){
      string gvName = "ANTU_AI_RUN_" + IntegerToString(accNum);
      datetime firstRun = (datetime)GlobalVariableGet(gvName);
      if(firstRun == 0){
         firstRun = TimeCurrent();
         GlobalVariableSet(gvName, (double)firstRun);
         trial_start_time = firstRun;
         SendNotify("ANTU AI: Trial started! "+IntegerToString(InpTrialDays)+" days free.");
         return true;
      }
      trial_start_time = firstRun;
      int daysLeft = InpTrialDays - (int)((TimeCurrent()-firstRun)/86400);
      if(daysLeft > 0) return true;
      else { SendNotify("ANTU AI: Trial EXPIRED!"); return false; }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Count OUR positions                                              |
//+------------------------------------------------------------------+
int CountMyPositions(){
   int count=0;
   for(int i=PositionsTotal()-1; i>=0; i--){
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)==MagicNumber && PositionGetString(POSITION_SYMBOL)==_Symbol)
         count++;
   }
   return count;
}


//+------------------------------------------------------------------+
//| LOT CALCULATOR with $ SL CAP                                     |
//+------------------------------------------------------------------+
double ComputeLot(double slDistPoints){
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize==0 || point==0) return FixLotSize;

   double lot = (equity * (RiskPercent/100.0)) / (slDistPoints * (tickValue/(tickSize/point)));
   // MAX SL $ CAP
   double maxLotBySL = MaxSLDollar / (slDistPoints * (tickValue/(tickSize/point)));
   lot = MathMin(lot, maxLotBySL);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), MaxCompoundLot);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, MathFloor(lot/step)*step));
   return lot;
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT (BE + Trail + Partial)                          |
//+------------------------------------------------------------------+
void ManageOpenTrades(){
   for(int i=PositionsTotal()-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN), currentSL=PositionGetDouble(POSITION_SL);
      double currentTP=PositionGetDouble(POSITION_TP), currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);
      double currentLot=PositionGetDouble(POSITION_VOLUME), point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      long posType=PositionGetInteger(POSITION_TYPE); string comment=PositionGetString(POSITION_COMMENT);

      // Partial TP
      if(UsePartialTP && comment!="PTP1"){
         double atrArr[]; if(CopyBuffer(atrHandle,0,1,1,atrArr)>0){
            double tp1Dist = atrArr[0]*TP1_ATR_Mult; bool tp1Hit=false;
            if((posType==POSITION_TYPE_BUY && currentPrice>=openPrice+tp1Dist) ||
               (posType==POSITION_TYPE_SELL && currentPrice<=openPrice-tp1Dist)) tp1Hit=true;
            if(tp1Hit){
               double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
               double closeLot=MathFloor((currentLot*TP1_ClosePct/100.0)/lotStep)*lotStep;
               if(closeLot>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN) && closeLot<currentLot){
                  trade.PositionClosePartial(ticket, closeLot);
                  if(InpNotifyOnTrade) SendNotify("ANTU AI: PARTIAL CLOSE +profit locked");
               }
            }
         }
      }

      if(!PositionSelectByTicket(ticket)) continue;
      currentSL=PositionGetDouble(POSITION_SL); currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);

      // Breakeven
      if(UseBreakeven){
         if(posType==POSITION_TYPE_BUY && currentPrice>openPrice+BE_TriggerPoints*point){
            double newSL=openPrice+BE_LockPoints*point;
            if(currentSL<newSL) trade.PositionModify(ticket, newSL, currentTP);
         }
         if(posType==POSITION_TYPE_SELL && currentPrice<openPrice-BE_TriggerPoints*point){
            double newSL=openPrice-BE_LockPoints*point;
            if(currentSL>newSL || currentSL==0) trade.PositionModify(ticket, newSL, currentTP);
         }
      }

      // Trailing
      if(UseTrailing){
         if(posType==POSITION_TYPE_BUY && currentPrice>openPrice+Trail_Start*point){
            double newSL=currentPrice-Trail_Step*point;
            if(newSL>currentSL) trade.PositionModify(ticket, newSL, currentTP);
         }
         if(posType==POSITION_TYPE_SELL && currentPrice<openPrice-Trail_Start*point){
            double newSL=currentPrice+Trail_Step*point;
            if(newSL<currentSL || currentSL==0) trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION                                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result){
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal) && HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==MagicNumber){
      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
      if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_INOUT){
         double pr=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
         gMonthlyProfit+=pr; gMonthTrades++;
         if(pr>0){ gMonthWins++; gConsecLosses=0; if(gEmergencyLocked){gEmergencyLocked=false;gLockBarsRemain=0;} }
         else if(pr<0){ gConsecLosses++; if(UseEmergencyLock && gConsecLosses>=MaxConsecLosses && !gEmergencyLocked){gEmergencyLocked=true;gLockBarsRemain=LockDurationBars;} }
         if(UseMonthlySalary && (gMonthlyProfit>=MonthlySalaryTarget || gMonthlyProfit<=-MonthlyMaxLoss)) gMonthHit=true;
      }
   }
}


//+------------------------------------------------------------------+
//| DASHBOARD (Neon Style)                                           |
//+------------------------------------------------------------------+
void R(string n,int x,int y,int w,int h,color bg,color brd,int bw=1){
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w); ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,n,OBJPROP_COLOR,brd); ObjectSetInteger(0,n,OBJPROP_WIDTH,bw);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
}
void L(string n,int x,int y,string txt,int sz,color clr,bool bold=false){
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,n,OBJPROP_TEXT,txt); ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,n,OBJPROP_FONT,bold?"Arial Black":"Calibri");
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
}

void UpdateDashboard(double pnl, double floatPL){
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   string stMsg="HUNTING..."; color stClr=CLR_PROFIT;
   if(floatPL<-MaxDrawdownStop){stMsg="DD STOP!";stClr=CLR_LOSS;}
   else if(gMonthHit){stMsg="MONTH DONE!";stClr=CLR_WARN;}
   else if(dailyTargetHit){stMsg="TARGET HIT!";stClr=CLR_WARN;}
   else if(gEmergencyLocked){stMsg="EMRG LOCKED";stClr=CLR_LOSS;}
   else if(isNewsTime){stMsg="NEWS SHIELD";stClr=CLR_WARN;}
   else if(!IsTradingTime()){stMsg="SLEEPING";stClr=CLR_TXT_MUTED;}
   else if(CountMyPositions()>0){stMsg="IN TRADE";stClr=C'0,200,255';}

   datetime now=TimeCurrent();
   if(now-gLastBlink>=2){gBlinkPhase=!gBlinkPhase;gLastBlink=now;}

   R("BG",5,5,240,290,CLR_BG_INNER,gBlinkPhase?C'0,255,255':C'0,150,200',2);
   L("Ttl",15,12,"ANTU GOLDMIND AI v10",9,clrCyan,true);
   R("L1",10,35,230,1,C'0,100,150',C'0,100,150',0);

   L("S1",15,45,"STATUS :",8,CLR_TXT_MUTED);
   L("S2",80,45,stMsg,8,stClr,true);
   L("P1",15,65,"Daily P&L :",8,CLR_TXT_MUTED);
   L("P2",90,65,"$"+DoubleToString(pnl,2),9,pnl>=0?CLR_PROFIT:CLR_LOSS,true);
   L("F1",15,85,"Float P&L :",8,CLR_TXT_MUTED);
   L("F2",90,85,"$"+DoubleToString(floatPL,2),9,floatPL>=0?CLR_PROFIT:CLR_WARN,true);

   R("L2",10,110,230,1,C'0,100,150',C'0,100,150',0);
   L("M1",15,120,"MAX SL CAP: $"+DoubleToString(MaxSLDollar,2),7,CLR_WARN,true);
   L("M2",15,140,"Consec Loss: "+IntegerToString(gConsecLosses)+"/"+IntegerToString(MaxConsecLosses),7,
     gEmergencyLocked?CLR_LOSS:CLR_TXT_WHITE);
   L("M3",15,160,"Monthly: $"+DoubleToString(gMonthlyProfit,2),7,gMonthlyProfit>=0?CLR_PROFIT:CLR_LOSS);

   R("L3",10,185,230,1,C'0,100,150',C'0,100,150',0);
   string nwStr=isNewsTime?"NEWS SHIELD ACTIVE":(UseNewsFilter?"News Filter ON":"News Filter OFF");
   L("N1",15,195,nwStr,7,isNewsTime?CLR_WARN:CLR_PROFIT,isNewsTime);
   L("N2",15,215,"Positions: "+IntegerToString(CountMyPositions()),7,CLR_TXT_WHITE);

   // License
   string licInfo=license_valid?"LICENSED":"TRIAL";
   if(trial_start_time>0 && !license_valid){
      int daysLeft=InpTrialDays-(int)((TimeCurrent()-trial_start_time)/86400);
      licInfo="TRIAL: "+IntegerToString(daysLeft)+"d left";
   }
   R("L4",10,240,230,1,C'0,100,150',C'0,100,150',0);
   L("LC",15,250,licInfo,7,license_valid?CLR_PROFIT:CLR_WARN);
   L("FT",60,270,"POWERED BY ANTU TRADING",7,C'0,150,200',true);
   ChartRedraw();
}


//+------------------------------------------------------------------+
//| INIT / DEINIT                                                    |
//+------------------------------------------------------------------+
int OnInit(){
   if(!ValidatePassword()){Alert("ANTU AI: Invalid Password!");return(INIT_FAILED);}
   if(admin_mode){ShowKeyGeneratorPanel();return(INIT_SUCCEEDED);}
   license_valid=false;
   if(!ValidateLicense()){Alert("ANTU AI: License expired!");return(INIT_FAILED);}

   trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(10);
   dayBalance = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt0; TimeCurrent(dt0); gCurMonth=dt0.mon; gMonthBalance=AccountInfoDouble(ACCOUNT_BALANCE);

   atrHandle = iATR(_Symbol, PERIOD_M5, ATRPeriod);
   emaHandle = iMA(_Symbol, PERIOD_M5, 200, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M5, RSIPeriod, PRICE_CLOSE);

   if(atrHandle==INVALID_HANDLE || emaHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE){
      Print("ERROR: Indicator creation failed!"); return(INIT_FAILED);
   }

   long accNum=AccountInfoInteger(ACCOUNT_LOGIN);
   SendNotify("ANTU AI v10 started! Acc:"+IntegerToString(accNum)+" MaxSL:$"+DoubleToString(MaxSLDollar,2));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   Comment("");
   IndicatorRelease(atrHandle); IndicatorRelease(emaHandle); IndicatorRelease(rsiHandle);
   ObjectsDeleteAll(0); ChartRedraw();
}

//+------------------------------------------------------------------+
//| UTILITIES                                                        |
//+------------------------------------------------------------------+
bool IsNewDay(){
   MqlDateTime dt; TimeCurrent(dt); static int prevDay=-1;
   if(dt.day!=prevDay){prevDay=dt.day;dailyTargetHit=false;gConsecLosses=0;gEmergencyLocked=false;return true;}
   return false;
}
bool IsNewMonth(){
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.mon!=gCurMonth){gCurMonth=dt.mon;gMonthlyProfit=0;gMonthTrades=0;gMonthWins=0;gMonthHit=false;gMonthBalance=AccountInfoDouble(ACCOUNT_BALANCE);return true;}
   return false;
}
bool IsTradingTime(){
   if(!UseSessionTime) return true;
   MqlDateTime dt; TimeCurrent(dt); return(dt.hour>=StartHour && dt.hour<EndHour);
}
bool CheckHighImpactNews(){
   if(!UseNewsFilter || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return false;
   MqlCalendarValue values[]; datetime tNow=TimeCurrent();
   if(CalendarValueHistory(values, tNow-(PauseAfterNews*60), tNow+(PauseBeforeNews*60))){
      for(int i=0;i<ArraySize(values);i++){
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id, ev) && ev.importance>=CALENDAR_IMPORTANCE_HIGH) return true;
      }
   }
   return false;
}


//+------------------------------------------------------------------+
//| ON TICK — Main Logic (SAME as original v10)                      |
//+------------------------------------------------------------------+
void OnTick(){
   if(admin_mode) return;

   if(IsNewDay()) dayBalance=AccountInfoDouble(ACCOUNT_EQUITY); IsNewMonth();
   double pnl=AccountInfoDouble(ACCOUNT_EQUITY)-dayBalance, floatPL=0;
   if(UseDailyLimit && (pnl>=DailyProfitUSD || pnl<=-DailyLossUSD)) dailyTargetHit=true;

   for(int i=PositionsTotal()-1; i>=0; i--)
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         floatPL += PositionGetDouble(POSITION_PROFIT);

   isNewsTime = CheckHighImpactNews();
   ManageOpenTrades();

   // UI update once per second
   static datetime lastUIDraw=0;
   if(TimeCurrent()-lastUIDraw>=1){UpdateDashboard(pnl,floatPL);lastUIDraw=TimeCurrent();}

   if(floatPL<-MaxDrawdownStop || dailyTargetHit || gMonthHit || isNewsTime || !IsTradingTime() || (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>MaxSpreadPoints) return;

   datetime timeArr[]; if(CopyTime(_Symbol,PERIOD_M5,0,1,timeArr)<=0 || timeArr[0]==lastBarTime) return; lastBarTime=timeArr[0];

   if(gEmergencyLocked && UseEmergencyLock){
      if(gLockBarsRemain>0) gLockBarsRemain--;
      if(gLockBarsRemain<=0){gEmergencyLocked=false;gConsecLosses=0;} else return;
   }

   double atr[], ema[], close[], open[], rsiArr[];
   if(CopyBuffer(atrHandle,0,1,1,atr)<=0 || CopyBuffer(emaHandle,0,1,1,ema)<=0 ||
      CopyBuffer(rsiHandle,0,0,1,rsiArr)<=0 || CopyClose(_Symbol,PERIOD_M5,1,2,close)<=0 ||
      CopyOpen(_Symbol,PERIOD_M5,1,2,open)<=0) return;

   double c1=close[1], c2=close[0], nLoss=UT_Multiplier*atr[0];
   bool hasDisplacement = !UseDisplacement || (MathAbs(c1-open[1])>(atr[0]*Displacement_Mult));

   if(trailStop==0) trailStop=c1;
   if(c1>trailStop && c2>trailStop) trailStop=MathMax(trailStop, c1-nLoss);
   else if(c1<trailStop && c2<trailStop) trailStop=MathMin(trailStop, c1+nLoss);
   else if(c1>trailStop && c2<trailStop) trailStop=c1-nLoss;
   else if(c1<trailStop && c2>trailStop) trailStop=c1+nLoss;

   bool buySignal=(c1>trailStop && c2<=trailStop), sellSignal=(c1<trailStop && c2>=trailStop);
   if(UseTrendFilter){if(buySignal && c1<ema[0]) buySignal=false; if(sellSignal && c1>ema[0]) sellSignal=false;}
   if(UseRSIFilter){if(buySignal && rsiArr[0]>RSI_Overbought) buySignal=false; if(sellSignal && rsiArr[0]<RSI_Oversold) sellSignal=false;}

   if(CountMyPositions()==0 && hasDisplacement && (buySignal || sellSignal)){
      double slDist=atr[0]*SL_ATR_Mult;
      double tpDist=atr[0]*(UsePartialTP?TP2_ATR_Mult:TP_ATR_Mult);
      double tradeLot=ComputeLot(slDist/SymbolInfoDouble(_Symbol,SYMBOL_POINT));

      // Lot reduction after loss streak
      if(gConsecLosses>0) tradeLot=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), tradeLot*0.8);

      // Max SL $ filter
      if(MaxSLDollar>0){
         double tVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
         double tSz=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
         if(tSz>0 && pt>0 && (tradeLot*(slDist/pt)*(tVal/(tSz/pt)))>MaxSLDollar) return;
      }

      if(buySignal){
         trade.Buy(tradeLot,_Symbol,0,NormalizeDouble(c1-slDist,_Digits),NormalizeDouble(c1+tpDist,_Digits),"ANTU AI v10");
         NotifyTradeOpen("BUY",tradeLot);
      }
      if(sellSignal){
         trade.Sell(tradeLot,_Symbol,0,NormalizeDouble(c1+slDist,_Digits),NormalizeDouble(c1-tpDist,_Digits),"ANTU AI v10");
         NotifyTradeOpen("SELL",tradeLot);
      }
   }
}
//+------------------------------------------------------------------+
