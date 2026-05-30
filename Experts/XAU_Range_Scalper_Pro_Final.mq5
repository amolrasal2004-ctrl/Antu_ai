//+------------------------------------------------------------------+
//| XAU_Range_Scalper_Pro_Final.mq5                                  |
//| Strategy: Donchian Channel Breakout + ATR Momentum               |
//| Timeframe: M15 | Target: XAUUSD                                 |
//| Style: BIG TRADE CAPTURE                                         |
//| COPYRIGHT: ANTU Trading                                          |
//+------------------------------------------------------------------+
#property copyright "ANTU Trading"
#property version   "2.00"
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//================ LICENSE =================//
input group "=== License & Security ==="
input string InpPassword="";
input string InpLicenseKey="";
input int    InpTrialDays=7;
input string InpAdminPassword="";

//================ MONEY =================//
input group "=== Money Management ==="
input double InpRiskPercent=1.0;
input double InpFixedLot=0.01;
input double InpMaxLotCap=0.50;
input double InpMaxSLDollar=5.0;

//================ CHANNEL =================//
input group "=== Channel Breakout ==="
input int    InpChannelPeriod=20;
input int    InpATRPeriod=14;
input double InpATRMinMult=0.8;

//================ SL/TP =================//
input group "=== Stop Loss / Take Profit ==="
input double InpSL_ATR_Mult=1.5;
input double InpTP_ATR_Mult=4.0;

//================ PROTECTION =================//
input group "=== Profit Protection ==="
input bool   InpUseBreakeven=true;
input double InpBE_ATR_Mult=1.0;
input double InpBE_LockPips=3.0;
input bool   InpUseTrailing=true;
input bool   InpTrailByChannel=true;
input double InpTrail_ATR_Mult=1.5;

//================ PARTIAL =================//
input group "=== Partial Close ==="
input bool   InpUsePartial=true;
input double InpPartialPct=50.0;
input double InpPartialMult=2.0;

//================ DAILY =================//
input group "=== Daily Guard ==="
input bool   InpUseDailyLimit=true;
input double InpDailyTarget=20.0;
input double InpDailyMaxLoss=10.0;
input int    InpMaxConsecLoss=3;
input int    InpMaxTrades=6;

//================ SESSION =================//
input group "=== Session & News ==="
input bool   InpUseSession=true;
input int    InpStartHour=7;
input int    InpEndHour=21;
input bool   InpAvoidFriday=true;
input bool   InpUseNews=true;
input int    InpNewsBlock=30;

//================ NOTIFY =================//
input group "=== Notifications ==="
input bool   InpPush=true;
input bool   InpAlert=false;
input bool   InpNotifyTrade=true;
input bool   InpNotifyBlock=false;

input group "=== System ==="
input int    InpMagic=777777;
input string InpComment="XAU Breakout";

//--- Constants
#define MASTER_PASS "ANTU2024PRO"
#define ADMIN_PASS  "ANTUADMIN99"
#define LIC_SALT    "ANTU_GOLD_"
#define CLR_GOLD    C'212,175,55'
#define CLR_BG      C'18,18,22'
#define CLR_LINE    C'35,35,42'
#define CLR_MUTED   C'140,145,150'
#define CLR_WHITE   C'250,250,255'
#define CLR_GREEN   C'0,220,110'
#define CLR_RED     C'255,70,70'
#define CLR_WARN    C'255,180,50'

//--- Globals
int atrHandle=INVALID_HANDLE;
double dayBal=0;
datetime lastBar=0;
bool dailyHit=false,locked=false,licValid=false,adminMode=false;
int consecLoss=0,dailyTrades=0;
datetime trialStart=0;



//+------------------------------------------------------------------+
//| LICENSE + NOTIFICATIONS                                          |
//+------------------------------------------------------------------+
void Notify(string m){if(InpPush)SendNotification(m);if(InpAlert)Alert(m);Print(m);}
string GenKey(long a){string r=LIC_SALT+IntegerToString(a);int h=0;for(int i=0;i<StringLen(r);i++){h=h*31+StringGetCharacter(r,i);h=h%999999;}if(h<0)h=-h;return "ANTU-"+IntegerToString(h,6,'0');}
bool CheckPass(){if(InpAdminPassword==ADMIN_PASS){adminMode=true;return true;}if(StringLen(InpPassword)==0||InpPassword!=MASTER_PASS)return false;return true;}
bool CheckLic(){if(adminMode)return true;long a=AccountInfoInteger(ACCOUNT_LOGIN);if(StringLen(InpLicenseKey)>0&&InpLicenseKey==GenKey(a)){licValid=true;return true;}if(InpTrialDays>0){string gv="ANTU_BRK_"+IntegerToString(a);datetime f=(datetime)GlobalVariableGet(gv);if(f==0){f=TimeCurrent();GlobalVariableSet(gv,(double)f);trialStart=f;return true;}trialStart=f;if(InpTrialDays-(int)((TimeCurrent()-f)/86400)>0)return true;}return false;}
int CountPos(){int c=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0)continue;if(!PositionSelectByTicket(t))continue;if(PositionGetInteger(POSITION_MAGIC)==InpMagic&&PositionGetString(POSITION_SYMBOL)==_Symbol)c++;}return c;}

//+------------------------------------------------------------------+
//| DONCHIAN HELPERS (uses PERIOD_CURRENT = M15)                     |
//+------------------------------------------------------------------+
double DonchHigh(int per,int shift){double h=0;for(int i=shift;i<shift+per;i++){double v=iHigh(_Symbol,PERIOD_CURRENT,i);if(v>h)h=v;}return h;}
double DonchLow(int per,int shift){double l=999999;for(int i=shift;i<shift+per;i++){double v=iLow(_Symbol,PERIOD_CURRENT,i);if(v<l)l=v;}return l;}
double DonchMid(int per,int shift){return(DonchHigh(per,shift)+DonchLow(per,shift))/2.0;}

//+------------------------------------------------------------------+
//| LOT CALCULATOR                                                   |
//+------------------------------------------------------------------+
double CalcLot(double slPrice){
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0||ts<=0)return InpFixedLot;
   double risk=eq*InpRiskPercent/100.0;
   double lpl=(slPrice/ts)*tv;
   if(lpl<=0)return InpFixedLot;
   double lot=risk/lpl;
   if(InpMaxSLDollar>0)lot=MathMin(lot,InpMaxSLDollar/lpl);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(st<=0)st=0.01;
   lot=MathFloor(lot/st)*st;
   lot=MathMax(mn,MathMin(mx,MathMin(lot,InpMaxLotCap)));
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
//| SESSION / NEWS                                                   |
//+------------------------------------------------------------------+
bool IsTime(){if(!InpUseSession)return true;MqlDateTime d;TimeCurrent(d);if(d.hour<InpStartHour||d.hour>=InpEndHour)return false;if(InpAvoidFriday&&d.day_of_week==5&&d.hour>=19)return false;return true;}
bool IsNews(){if(!InpUseNews||MQLInfoInteger(MQL_TESTER))return false;MqlCalendarValue v[];datetime t=TimeCurrent();if(CalendarValueHistory(v,t-InpNewsBlock*60,t+InpNewsBlock*60)){for(int i=0;i<ArraySize(v);i++){MqlCalendarEvent e;if(CalendarEventById(v[i].event_id,e)&&e.importance>=CALENDAR_IMPORTANCE_HIGH)return true;}}return false;}



//+------------------------------------------------------------------+
//| PROFESSIONAL DASHBOARD (Gold Style)                              |
//+------------------------------------------------------------------+
void DrawRect(string n,int x,int y,int w,int h,color bg){
   if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,n,OBJPROP_COLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,n,OBJPROP_BACK,false);
}
void DrawTxt(string n,int x,int y,string t,int s,color c,string f="Segoe UI",bool b=false){
   if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,n,OBJPROP_TEXT,t);ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,s);ObjectSetString(0,n,OBJPROP_FONT,b?f+" Bold":f);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
}

void Dashboard(double pnl,string st,color sc,double chH,double chL){
   DrawRect("D_Out",20,30,310,300,CLR_GOLD);
   DrawRect("D_In",22,32,306,296,CLR_BG);
   DrawRect("D_Hdr",22,32,306,40,CLR_GOLD);
   DrawTxt("D_T",40,40,"XAU BREAKOUT PRO | M15",11,C'15,15,15',"Segoe UI Black",true);
   DrawRect("D_L1",40,100,270,1,CLR_LINE);
   DrawRect("D_L2",40,160,270,1,CLR_LINE);
   DrawRect("D_L3",40,230,270,1,CLR_LINE);

   DrawTxt("D_S0",40,80,"STATUS",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_S1",180,78,st,9,sc,"Segoe UI Black",true);

   DrawTxt("D_P0",40,110,"TODAY P/L",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_P1",180,106,"$"+DoubleToString(pnl,2),14,pnl>=0?CLR_GREEN:CLR_RED,"Consolas",true);

   DrawTxt("D_C0",40,135,"CHANNEL",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_C1",180,135,DoubleToString(chH,2)+" / "+DoubleToString(chL,2),8,CLR_WHITE,"Consolas",true);

   DrawTxt("D_M0",40,170,"MAX SL",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_M1",180,170,"$"+DoubleToString(InpMaxSLDollar,2),8,CLR_WARN,"Consolas",true);

   DrawTxt("D_T0",40,190,"TRADES TODAY",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_T1",180,190,IntegerToString(dailyTrades)+" / "+IntegerToString(InpMaxTrades),8,CLR_WHITE,"Consolas",true);

   DrawTxt("D_L0",40,210,"CONSEC LOSS",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_L00",180,210,IntegerToString(consecLoss)+" / "+IntegerToString(InpMaxConsecLoss),8,locked?CLR_RED:CLR_WHITE,"Consolas",true);

   DrawTxt("D_PO",40,240,"POSITIONS",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_PO1",180,240,IntegerToString(CountPos()),8,CLR_WHITE,"Consolas",true);

   string li=licValid?"LICENSED":"TRIAL";
   if(trialStart>0&&!licValid){int d=InpTrialDays-(int)((TimeCurrent()-trialStart)/86400);li="TRIAL: "+IntegerToString(d)+"d left";}
   DrawTxt("D_LI",40,260,"LICENSE",8,CLR_MUTED,"Segoe UI",true);
   DrawTxt("D_LI1",180,260,li,8,licValid?CLR_GREEN:CLR_WARN,"Consolas",true);

   DrawTxt("D_FT",85,295,"POWERED BY ANTU TRADING",7,CLR_GOLD,"Segoe UI",true);
   ChartRedraw();
}



//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                 |
//+------------------------------------------------------------------+
void ManageTrades(){
   double atrA[];if(CopyBuffer(atrHandle,0,1,1,atrA)<=0)return;
   double atr=atrA[0];
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tk=PositionGetTicket(i);if(!PositionSelectByTicket(tk))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
      double op=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      double cp=PositionGetDouble(POSITION_PRICE_CURRENT),vol=PositionGetDouble(POSITION_VOLUME);
      long pt=PositionGetInteger(POSITION_TYPE);string cm=PositionGetString(POSITION_COMMENT);
      // PARTIAL
      if(InpUsePartial&&StringFind(cm,"PC")<0){
         double pd=atr*InpPartialMult;bool hit=false;
         if(pt==POSITION_TYPE_BUY&&cp>=op+pd)hit=true;
         if(pt==POSITION_TYPE_SELL&&cp<=op-pd)hit=true;
         if(hit){double st2=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);double cl=MathFloor((vol*InpPartialPct/100.0)/st2)*st2;if(cl>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)&&cl<vol){trade.PositionClosePartial(tk,cl);continue;}}
      }
      if(!PositionSelectByTicket(tk))continue;sl=PositionGetDouble(POSITION_SL);cp=PositionGetDouble(POSITION_PRICE_CURRENT);
      // BE
      if(InpUseBreakeven){
         double bd=atr*InpBE_ATR_Mult,bl=InpBE_LockPips*_Point*10;
         if(pt==POSITION_TYPE_BUY&&cp>op+bd){double ns=op+bl;if(sl<ns)trade.PositionModify(tk,ns,tp);}
         if(pt==POSITION_TYPE_SELL&&cp<op-bd){double ns=op-bl;if(sl>ns||sl==0)trade.PositionModify(tk,ns,tp);}
      }
      // TRAIL
      if(InpUseTrailing){
         if(InpTrailByChannel){
            double mid=DonchMid(InpChannelPeriod,1);
            if(pt==POSITION_TYPE_BUY&&mid>sl&&mid>op)trade.PositionModify(tk,mid,tp);
            if(pt==POSITION_TYPE_SELL&&(mid<sl||sl==0)&&mid<op)trade.PositionModify(tk,mid,tp);
         }else{
            double td=atr*InpTrail_ATR_Mult;
            if(pt==POSITION_TYPE_BUY){double ns=cp-td;if(ns>sl&&ns>op)trade.PositionModify(tk,ns,tp);}
            if(pt==POSITION_TYPE_SELL){double ns=cp+td;if((ns<sl||sl==0)&&ns<op)trade.PositionModify(tk,ns,tp);}
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION                                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &tr,const MqlTradeRequest &rq,const MqlTradeResult &rs){
   if(tr.type==TRADE_TRANSACTION_DEAL_ADD&&HistoryDealSelect(tr.deal)&&HistoryDealGetInteger(tr.deal,DEAL_MAGIC)==InpMagic){
      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(tr.deal,DEAL_ENTRY);
      if(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_INOUT){
         double pr=HistoryDealGetDouble(tr.deal,DEAL_PROFIT);dailyTrades++;
         if(pr>0){consecLoss=0;if(locked)locked=false;}
         else if(pr<0){consecLoss++;if(InpMaxConsecLoss>0&&consecLoss>=InpMaxConsecLoss)locked=true;}
      }
   }
}

//+------------------------------------------------------------------+
//| INIT / DEINIT                                                    |
//+------------------------------------------------------------------+
int OnInit(){
   if(!CheckPass()){Alert("Invalid Password!");return INIT_FAILED;}
   if(adminMode){long a=AccountInfoInteger(ACCOUNT_LOGIN);Alert("Account:"+IntegerToString(a)+"\nKey:"+GenKey(a));Comment("Key:"+GenKey(a));return INIT_SUCCEEDED;}
   if(!CheckLic()){Alert("License expired!");return INIT_FAILED;}
   trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(10);
   dayBal=AccountInfoDouble(ACCOUNT_EQUITY);
   atrHandle=iATR(_Symbol,PERIOD_CURRENT,InpATRPeriod);
   if(atrHandle==INVALID_HANDLE){Print("ATR failed!");return INIT_FAILED;}
   Notify("XAU Breakout Pro started! M15 | MaxSL:$"+DoubleToString(InpMaxSLDollar,2));
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){Comment("");ObjectsDeleteAll(0,"D_");IndicatorRelease(atrHandle);ChartRedraw();}



//+------------------------------------------------------------------+
//| ON TICK — MAIN LOGIC (Donchian Breakout M15)                     |
//+------------------------------------------------------------------+
void OnTick(){
   if(adminMode)return;

   // Daily reset
   MqlDateTime dt;TimeCurrent(dt);static int pDay=-1;
   if(dt.day!=pDay){pDay=dt.day;dailyHit=false;dailyTrades=0;consecLoss=0;locked=false;dayBal=AccountInfoDouble(ACCOUNT_EQUITY);}

   double pnl=AccountInfoDouble(ACCOUNT_EQUITY)-dayBal;
   if(InpUseDailyLimit&&(pnl>=InpDailyTarget||pnl<=-InpDailyMaxLoss))dailyHit=true;

   ManageTrades();

   // Channel for dashboard
   double chH=DonchHigh(InpChannelPeriod,1),chL=DonchLow(InpChannelPeriod,1);

   // Status
   string st="HUNTING";color sc=CLR_GREEN;
   if(dailyHit){st="TARGET HIT";sc=CLR_WARN;}
   else if(locked){st="LOCKED";sc=CLR_RED;}
   else if(!IsTime()){st="SLEEPING";sc=CLR_MUTED;}
   else if(IsNews()){st="NEWS BLOCK";sc=CLR_WARN;}
   else if(CountPos()>0){st="IN TRADE";sc=C'0,200,255';}

   static datetime lastUI=0;
   if(TimeCurrent()-lastUI>=1){Dashboard(pnl,st,sc,chH,chL);lastUI=TimeCurrent();}

   // BLOCKS
   if(dailyHit||locked||!IsTime()||IsNews())return;
   if((int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>350)return;
   if(InpMaxTrades>0&&dailyTrades>=InpMaxTrades)return;

   // NEW BAR (M15 = PERIOD_CURRENT)
   datetime tArr[];
   if(CopyTime(_Symbol,PERIOD_CURRENT,0,1,tArr)<=0||tArr[0]==lastBar)return;
   lastBar=tArr[0];

   if(CountPos()>0)return;

   // ATR
   double atrA[];if(CopyBuffer(atrHandle,0,1,1,atrA)<=0)return;
   double atr=atrA[0];

   // ATR MOMENTUM: must be above average
   double atrAvg[];if(CopyBuffer(atrHandle,0,1,20,atrAvg)<=0)return;
   double avg=0;for(int i=0;i<20;i++)avg+=atrAvg[i];avg/=20.0;
   if(atr<avg*InpATRMinMult)return;

   // DONCHIAN
   double high=DonchHigh(InpChannelPeriod,2); // Channel of bars BEFORE last bar
   double low=DonchLow(InpChannelPeriod,2);

   // LAST COMPLETED BAR
   double c1=iClose(_Symbol,PERIOD_CURRENT,1);
   double c2=iClose(_Symbol,PERIOD_CURRENT,2);

   // BREAKOUT SIGNALS
   bool buy=(c1>high&&c2<=high);
   bool sell=(c1<low&&c2>=low);

   if(!buy&&!sell)return;

   // SL/TP
   double slD=atr*InpSL_ATR_Mult;
   double tpD=atr*InpTP_ATR_Mult;
   double lot=CalcLot(slD);
   if(lot<=0)return;

   if(buy){
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(trade.Buy(lot,_Symbol,ask,NormalizeDouble(ask-slD,_Digits),NormalizeDouble(ask+tpD,_Digits),InpComment))
         if(InpNotifyTrade)Notify("BUY Lot="+DoubleToString(lot,2)+" "+_Symbol);
   }
   if(sell){
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(trade.Sell(lot,_Symbol,bid,NormalizeDouble(bid+slD,_Digits),NormalizeDouble(bid-tpD,_Digits),InpComment))
         if(InpNotifyTrade)Notify("SELL Lot="+DoubleToString(lot,2)+" "+_Symbol);
   }
}
//+------------------------------------------------------------------+
