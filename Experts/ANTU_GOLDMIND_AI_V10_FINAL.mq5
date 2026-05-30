//+------------------------------------------------------------------+
//| ANTU GOLDMIND AI v10 — FINAL EDITION                             |
//| Strategy  : UT Bot + RSI + EMA + ICT Displacement Filter         |
//| Features  : License, MaxSL Cap, Notifications, DD Guard          |
//| COPYRIGHT : ANTU Trading                                         |
//+------------------------------------------------------------------+
#property copyright "ANTU Trading"
#property version   "10.00"
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//================ LICENSE & PASSWORD =================//
input group "=== License & Security ==="
input string   InpPassword          = "";        // EA Password (required)
input string   InpLicenseKey        = "";        // License Key (from ANTU Trading)
input int      InpTrialDays         = 7;         // Trial days (0=no trial)
input string   InpAdminPassword     = "";        // Admin Password (key generator)

//================ MONEY MANAGEMENT =================//
input group "=== Money Management ==="
input double   RiskPercent          = 1.0;       // % of equity risk per trade
input double   FixLotSize           = 0.01;      // Fixed lot (if risk% gives 0)
input double   MaxSLDollar          = 5.0;       // MAX SL $ per trade (hard cap)
input double   MaxLotCap            = 0.20;      // Max lot cap

//================ DAILY GOALS =====================//
input group "=== Daily Goals ==="
input bool     UseDailyLimit        = true;
input double   DailyProfitUSD       = 15.0;
input double   DailyLossUSD         = 15.0;

//================ MONTHLY SALARY =================//
input group "=== Monthly Salary ==="
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

//================ AI STRATEGY (ICT) ==============//
input group "=== AI Strategy Engine ==="
input bool     UseDisplacement      = true;
input double   Displacement_Mult    = 0.8;
input bool     UseTrendFilter       = true;      // EMA 200
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
input group "=== Partial TP ==="
input bool     UsePartialTP         = true;
input double   TP1_ATR_Mult         = 3.5;
input double   TP2_ATR_Mult         = 5.0;
input double   TP1_ClosePct         = 50.0;

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
input group "=== Notifications ==="
input bool     InpSendPushNotify    = true;
input bool     InpSendAlert         = false;
input bool     InpNotifyOnTrade     = true;
input bool     InpNotifyOnBlock     = false;

input int      MagicNumber          = 889900;

//================ CONSTANTS =======================//
#define LICENSE_MASTER_PASS   "ANTU2024PRO"
#define LICENSE_ADMIN_PASS    "ANTUADMIN99"
#define LICENSE_SALT          "ANTU_GOLD_"

//================ GLOBALS =========================//
int      atrHandle=INVALID_HANDLE, emaHandle=INVALID_HANDLE, rsiHandle=INVALID_HANDLE;
double   dayBalance=0, trailStop=0, gMonthBalance=0, gMonthlyProfit=0;
datetime lastBarTime=0, gLastBlink=0;
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
void NotifyTradeOpen(string dir, double lot){
   if(!InpNotifyOnTrade) return;
   SendNotify("ANTU AI: "+dir+" Lot="+DoubleToString(lot,2)+" "+_Symbol);
}
void NotifyBlock(string reason){
   if(!InpNotifyOnBlock) return;
   static string last=""; if(reason==last) return; last=reason;
   SendNotify("ANTU AI: BLOCKED - "+reason);
}

//+------------------------------------------------------------------+
//| LICENSE SYSTEM                                                    |
//+------------------------------------------------------------------+
string GenerateLicenseKey(long acc){
   string raw=LICENSE_SALT+IntegerToString(acc); int hash=0;
   for(int i=0;i<StringLen(raw);i++){hash=hash*31+StringGetCharacter(raw,i);hash=hash%999999;}
   if(hash<0) hash=-hash;
   return "ANTU-"+IntegerToString(hash,6,'0');
}
bool ValidatePassword(){
   if(InpAdminPassword==LICENSE_ADMIN_PASS){admin_mode=true;return true;}
   if(StringLen(InpPassword)==0){Print("ERROR: Password required!");return false;}
   if(InpPassword!=LICENSE_MASTER_PASS){Print("ERROR: Invalid password!");return false;}
   return true;
}
bool ValidateLicense(){
   if(admin_mode) return true;
   long acc=AccountInfoInteger(ACCOUNT_LOGIN);
   if(StringLen(InpLicenseKey)>0 && InpLicenseKey==GenerateLicenseKey(acc)){license_valid=true;return true;}
   if(InpTrialDays>0){
      string gv="ANTU_AI_"+IntegerToString(acc);
      datetime fr=(datetime)GlobalVariableGet(gv);
      if(fr==0){fr=TimeCurrent();GlobalVariableSet(gv,(double)fr);trial_start_time=fr;return true;}
      trial_start_time=fr;
      if(InpTrialDays-(int)((TimeCurrent()-fr)/86400)>0) return true;
      else{SendNotify("ANTU AI: Trial EXPIRED!");return false;}
   }
   return false;
}
void ShowKeyGeneratorPanel(){
   long acc=AccountInfoInteger(ACCOUNT_LOGIN);
   string key=GenerateLicenseKey(acc);
   Alert("Account: "+IntegerToString(acc)+"\nKey: "+key);
   Comment("ANTU KEY GENERATOR\nAccount: "+IntegerToString(acc)+"\nKey: "+key);
}

//+------------------------------------------------------------------+
//| COUNT MY POSITIONS (magic + symbol filtered)                     |
//+------------------------------------------------------------------+
int CountMyPositions(){
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong t=PositionGetTicket(i); if(t==0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)==MagicNumber && PositionGetString(POSITION_SYMBOL)==_Symbol) c++;
   }
   return c;
}

//+------------------------------------------------------------------+
//| LOT CALCULATOR with MAX SL $ CAP                                 |
//+------------------------------------------------------------------+
double ComputeLot(double slDistPoints){
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSz==0||point==0) return FixLotSize;
   double lot=(equity*(RiskPercent/100.0))/(slDistPoints*(tickVal/(tickSz/point)));
   // MAX SL $ CAP
   if(MaxSLDollar>0){
      double maxLot=MaxSLDollar/(slDistPoints*(tickVal/(tickSz/point)));
      lot=MathMin(lot,maxLot);
   }
   double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxL=MathMin(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),MaxLotCap);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lot=MathMax(minL,MathMin(maxL,MathFloor(lot/step)*step));
   return lot;
}



//+------------------------------------------------------------------+
//| TRADE MANAGEMENT (Partial TP + BE + Trail)                       |
//+------------------------------------------------------------------+
void ManageOpenTrades(){
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      double openP=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      double curPrice=PositionGetDouble(POSITION_PRICE_CURRENT);
      double curLot=PositionGetDouble(POSITION_VOLUME);
      double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      long posType=PositionGetInteger(POSITION_TYPE);
      string comment=PositionGetString(POSITION_COMMENT);

      // PARTIAL TP
      if(UsePartialTP && StringFind(comment,"PTP1")<0){
         double atrArr[];
         if(CopyBuffer(atrHandle,0,1,1,atrArr)>0){
            double tp1Dist=atrArr[0]*TP1_ATR_Mult; bool tp1Hit=false;
            if(posType==POSITION_TYPE_BUY && curPrice>=openP+tp1Dist) tp1Hit=true;
            if(posType==POSITION_TYPE_SELL && curPrice<=openP-tp1Dist) tp1Hit=true;
            if(tp1Hit){
               double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
               double closeLot=MathFloor((curLot*TP1_ClosePct/100.0)/lotStep)*lotStep;
               if(closeLot>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN) && closeLot<curLot){
                  trade.PositionClosePartial(ticket,closeLot);
                  NotifyTradeOpen("PARTIAL CLOSE",closeLot);
               }
            }
         }
      }

      if(!PositionSelectByTicket(ticket)) continue;
      curSL=PositionGetDouble(POSITION_SL); curPrice=PositionGetDouble(POSITION_PRICE_CURRENT);

      // BREAKEVEN
      if(UseBreakeven){
         if(posType==POSITION_TYPE_BUY && curPrice>openP+BE_TriggerPoints*point){
            double newSL=openP+BE_LockPoints*point;
            if(curSL<newSL) trade.PositionModify(ticket,newSL,curTP);
         }
         if(posType==POSITION_TYPE_SELL && curPrice<openP-BE_TriggerPoints*point){
            double newSL=openP-BE_LockPoints*point;
            if(curSL>newSL||curSL==0) trade.PositionModify(ticket,newSL,curTP);
         }
      }

      // TRAILING
      if(UseTrailing){
         if(posType==POSITION_TYPE_BUY && curPrice>openP+Trail_Start*point){
            double newSL=curPrice-Trail_Step*point;
            if(newSL>curSL) trade.PositionModify(ticket,newSL,curTP);
         }
         if(posType==POSITION_TYPE_SELL && curPrice<openP-Trail_Start*point){
            double newSL=curPrice+Trail_Step*point;
            if(newSL<curSL||curSL==0) trade.PositionModify(ticket,newSL,curTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION (track wins/losses)                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result){
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal) && HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==MagicNumber){
      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
      if(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_INOUT){
         double pr=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
         gMonthlyProfit+=pr; gMonthTrades++;
         if(pr>0){gMonthWins++;gConsecLosses=0;if(gEmergencyLocked){gEmergencyLocked=false;gLockBarsRemain=0;}}
         else if(pr<0){gConsecLosses++;if(UseEmergencyLock&&gConsecLosses>=MaxConsecLosses&&!gEmergencyLocked){gEmergencyLocked=true;gLockBarsRemain=LockDurationBars;}}
         if(UseMonthlySalary&&(gMonthlyProfit>=MonthlySalaryTarget||gMonthlyProfit<=-MonthlyMaxLoss)) gMonthHit=true;
      }
   }
}



//+------------------------------------------------------------------+
//| UTILITIES                                                        |
//+------------------------------------------------------------------+
bool IsNewDay(){
   MqlDateTime dt;TimeCurrent(dt);static int prevDay=-1;
   if(dt.day!=prevDay){prevDay=dt.day;dailyTargetHit=false;gConsecLosses=0;gEmergencyLocked=false;return true;}
   return false;
}
bool IsNewMonth(){
   MqlDateTime dt;TimeCurrent(dt);
   if(dt.mon!=gCurMonth){gCurMonth=dt.mon;gMonthlyProfit=0;gMonthTrades=0;gMonthWins=0;gMonthHit=false;gMonthBalance=AccountInfoDouble(ACCOUNT_BALANCE);return true;}
   return false;
}
bool IsTradingTime(){
   if(!UseSessionTime) return true;
   MqlDateTime dt;TimeCurrent(dt);return(dt.hour>=StartHour&&dt.hour<EndHour);
}
bool CheckHighImpactNews(){
   if(!UseNewsFilter||MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)) return false;
   MqlCalendarValue values[];datetime tNow=TimeCurrent();
   if(CalendarValueHistory(values,tNow-(PauseAfterNews*60),tNow+(PauseBeforeNews*60))){
      for(int i=0;i<ArraySize(values);i++){
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id,ev)&&ev.importance>=CALENDAR_IMPORTANCE_HIGH) return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| DASHBOARD (Neon)                                                 |
//+------------------------------------------------------------------+
void DrawDashboard(double pnl,double floatPL){
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   string stMsg="HUNTING...";color stClr=C'0,255,100';
   if(floatPL<-MaxDrawdownStop){stMsg="DD STOP!";stClr=C'255,50,50';}
   else if(gMonthHit){stMsg="MONTH DONE!";stClr=C'255,215,0';}
   else if(dailyTargetHit){stMsg="TARGET HIT!";stClr=C'255,215,0';}
   else if(gEmergencyLocked){stMsg="EMRG LOCKED";stClr=C'255,50,50';}
   else if(isNewsTime){stMsg="NEWS SHIELD";stClr=C'255,100,0';}
   else if(!IsTradingTime()){stMsg="SLEEPING";stClr=C'165,165,165';}
   else if(CountMyPositions()>0){stMsg="IN TRADE";stClr=C'0,200,255';}

   datetime now=TimeCurrent();
   if(now-gLastBlink>=2){gBlinkPhase=!gBlinkPhase;gLastBlink=now;}

   // Panel
   if(ObjectFind(0,"BG")<0) ObjectCreate(0,"BG",OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,"BG",OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,"BG",OBJPROP_XDISTANCE,5);ObjectSetInteger(0,"BG",OBJPROP_YDISTANCE,5);
   ObjectSetInteger(0,"BG",OBJPROP_XSIZE,235);ObjectSetInteger(0,"BG",OBJPROP_YSIZE,280);
   ObjectSetInteger(0,"BG",OBJPROP_BGCOLOR,C'10,12,20');
   ObjectSetInteger(0,"BG",OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,"BG",OBJPROP_COLOR,gBlinkPhase?C'0,255,255':C'0,150,200');
   ObjectSetInteger(0,"BG",OBJPROP_WIDTH,2);ObjectSetInteger(0,"BG",OBJPROP_BACK,false);

   DrawLabel("Ttl",15,12,"ANTU GOLDMIND AI v10",9,clrCyan,true);
   DrawLabel("S1",15,40,"STATUS :",8,C'150,200,255',false);
   DrawLabel("S2",80,40,stMsg,8,stClr,true);
   DrawLabel("P1",15,60,"Daily P&L :",8,C'150,200,255',false);
   DrawLabel("P2",90,60,"$"+DoubleToString(pnl,2),9,pnl>=0?C'0,255,100':C'255,50,50',true);
   DrawLabel("F1",15,80,"Float P&L :",8,C'150,200,255',false);
   DrawLabel("F2",90,80,"$"+DoubleToString(floatPL,2),9,floatPL>=0?C'0,255,100':C'255,100,25',true);
   DrawLabel("M1",15,105,"MAX SL CAP: $"+DoubleToString(MaxSLDollar,2),7,C'255,180,50',true);
   DrawLabel("M2",15,125,"Consec Loss: "+IntegerToString(gConsecLosses)+"/"+IntegerToString(MaxConsecLosses),7,gEmergencyLocked?C'255,50,50':C'200,220,255',false);
   DrawLabel("M3",15,145,"Monthly: $"+DoubleToString(gMonthlyProfit,2),7,gMonthlyProfit>=0?C'0,255,100':C'255,50,50',false);
   DrawLabel("N1",15,170,isNewsTime?"NEWS SHIELD ACTIVE":"News Filter "+(UseNewsFilter?"ON":"OFF"),7,isNewsTime?C'255,100,0':C'0,255,100',isNewsTime);
   DrawLabel("N2",15,190,"Positions: "+IntegerToString(CountMyPositions()),7,C'220,230,255',false);

   string licInfo=license_valid?"LICENSED":"TRIAL";
   if(trial_start_time>0&&!license_valid){int dl=InpTrialDays-(int)((TimeCurrent()-trial_start_time)/86400);licInfo="TRIAL: "+IntegerToString(dl)+"d left";}
   DrawLabel("LC",15,215,licInfo,7,license_valid?C'0,255,100':C'255,180,50',false);
   DrawLabel("FT",50,255,"POWERED BY ANTU TRADING",7,C'0,150,200',true);
   ChartRedraw();
}

void DrawLabel(string name,int x,int y,string txt,int sz,color clr,bool bold){
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,name,OBJPROP_FONT,bold?"Arial Black":"Calibri");
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}



//+------------------------------------------------------------------+
//| INIT / DEINIT                                                    |
//+------------------------------------------------------------------+
int OnInit(){
   if(!ValidatePassword()){Alert("ANTU AI: Invalid Password!");return(INIT_FAILED);}
   if(admin_mode){ShowKeyGeneratorPanel();return(INIT_SUCCEEDED);}
   if(!ValidateLicense()){Alert("ANTU AI: License expired!");return(INIT_FAILED);}

   trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(10);
   dayBalance=AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt0;TimeCurrent(dt0);gCurMonth=dt0.mon;gMonthBalance=AccountInfoDouble(ACCOUNT_BALANCE);

   atrHandle=iATR(_Symbol,PERIOD_M5,ATRPeriod);
   emaHandle=iMA(_Symbol,PERIOD_M5,200,0,MODE_EMA,PRICE_CLOSE);
   rsiHandle=iRSI(_Symbol,PERIOD_M5,RSIPeriod,PRICE_CLOSE);

   if(atrHandle==INVALID_HANDLE||emaHandle==INVALID_HANDLE||rsiHandle==INVALID_HANDLE){
      Print("ERROR: Indicator creation failed!");return(INIT_FAILED);
   }

   SendNotify("ANTU AI v10 started! MaxSL:$"+DoubleToString(MaxSLDollar,2));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   Comment("");ObjectsDeleteAll(0);
   IndicatorRelease(atrHandle);IndicatorRelease(emaHandle);IndicatorRelease(rsiHandle);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| ON TICK — MAIN LOGIC (UT Bot + ICT — ORIGINAL)                   |
//+------------------------------------------------------------------+
void OnTick(){
   if(admin_mode) return;

   if(IsNewDay()) dayBalance=AccountInfoDouble(ACCOUNT_EQUITY);
   IsNewMonth();

   double pnl=AccountInfoDouble(ACCOUNT_EQUITY)-dayBalance;
   double floatPL=0;
   if(UseDailyLimit&&(pnl>=DailyProfitUSD||pnl<=-DailyLossUSD)) dailyTargetHit=true;

   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionSelectByTicket(PositionGetTicket(i))&&PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         floatPL+=PositionGetDouble(POSITION_PROFIT);

   isNewsTime=CheckHighImpactNews();
   ManageOpenTrades();

   // Dashboard 1x per second
   static datetime lastUI=0;
   if(TimeCurrent()-lastUI>=1){DrawDashboard(pnl,floatPL);lastUI=TimeCurrent();}

   // BLOCK CONDITIONS
   if(floatPL<-MaxDrawdownStop||dailyTargetHit||gMonthHit||isNewsTime||!IsTradingTime()||(int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>MaxSpreadPoints) return;

   // NEW BAR ONLY (M5)
   datetime timeArr[];
   if(CopyTime(_Symbol,PERIOD_M5,0,1,timeArr)<=0||timeArr[0]==lastBarTime) return;
   lastBarTime=timeArr[0];

   // EMERGENCY LOCK
   if(gEmergencyLocked&&UseEmergencyLock){
      if(gLockBarsRemain>0) gLockBarsRemain--;
      if(gLockBarsRemain<=0){gEmergencyLocked=false;gConsecLosses=0;} else return;
   }

   // GET DATA
   double atr[],ema[],close[],open[],rsiArr[];
   if(CopyBuffer(atrHandle,0,1,1,atr)<=0) return;
   if(CopyBuffer(emaHandle,0,1,1,ema)<=0) return;
   if(CopyBuffer(rsiHandle,0,0,1,rsiArr)<=0) return;
   if(CopyClose(_Symbol,PERIOD_M5,1,2,close)<=0) return;
   if(CopyOpen(_Symbol,PERIOD_M5,1,2,open)<=0) return;

   double c1=close[1],c2=close[0],nLoss=UT_Multiplier*atr[0];

   // ICT DISPLACEMENT FILTER
   bool hasDisplacement=!UseDisplacement||(MathAbs(c1-open[1])>(atr[0]*Displacement_Mult));

   // UT BOT TRAIL STOP
   if(trailStop==0) trailStop=c1;
   if(c1>trailStop&&c2>trailStop) trailStop=MathMax(trailStop,c1-nLoss);
   else if(c1<trailStop&&c2<trailStop) trailStop=MathMin(trailStop,c1+nLoss);
   else if(c1>trailStop&&c2<trailStop) trailStop=c1-nLoss;
   else if(c1<trailStop&&c2>trailStop) trailStop=c1+nLoss;

   // SIGNALS
   bool buySignal=(c1>trailStop&&c2<=trailStop);
   bool sellSignal=(c1<trailStop&&c2>=trailStop);

   // EMA TREND FILTER
   if(UseTrendFilter){
      if(buySignal&&c1<ema[0]) buySignal=false;
      if(sellSignal&&c1>ema[0]) sellSignal=false;
   }
   // RSI FILTER
   if(UseRSIFilter){
      if(buySignal&&rsiArr[0]>RSI_Overbought) buySignal=false;
      if(sellSignal&&rsiArr[0]<RSI_Oversold) sellSignal=false;
   }

   // ENTRY
   if(CountMyPositions()==0&&hasDisplacement&&(buySignal||sellSignal)){
      double slDist=atr[0]*SL_ATR_Mult;
      double tpDist=atr[0]*(UsePartialTP?TP2_ATR_Mult:TP_ATR_Mult);
      double tradeLot=ComputeLot(slDist/SymbolInfoDouble(_Symbol,SYMBOL_POINT));

      // Reduce lot after losses
      if(gConsecLosses>0) tradeLot=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),tradeLot*0.8);

      // MAX SL $ FINAL CHECK
      if(MaxSLDollar>0){
         double tVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
         double tSz=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
         if(tSz>0&&pt>0&&(tradeLot*(slDist/pt)*(tVal/(tSz/pt)))>MaxSLDollar) return;
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
