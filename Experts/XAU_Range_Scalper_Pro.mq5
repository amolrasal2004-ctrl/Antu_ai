//+------------------------------------------------------------------+
//| XAU_RANGE_SCALPER_PRO.mq5                                        |
//| Strategy: Donchian Channel Breakout + ATR Momentum               |
//| Timeframe: H1 | Target: XAUUSD                                  |
//| Style: BIG TRADE CAPTURE (Swing Trading)                         |
//| COPYRIGHT: ANTU Trading                                          |
//+------------------------------------------------------------------+
#property copyright "ANTU Trading"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//================ LICENSE & PASSWORD =================//
input group "=== License & Security ==="
input string   InpPassword          = "";        // EA Password (required)
input string   InpLicenseKey        = "";        // License Key
input int      InpTrialDays         = 7;         // Trial days
input string   InpAdminPassword     = "";        // Admin Password

//================ MONEY MANAGEMENT =================//
input group "=== Money Management ==="
input double   InpRiskPercent       = 1.0;       // Risk % per trade
input double   InpFixedLot          = 0.01;      // Fixed lot (fallback)
input double   InpMaxLotCap         = 0.50;      // Max lot cap
input double   InpMaxSLDollar       = 5.0;       // MAX SL $ (hard cap)

//================ CHANNEL BREAKOUT ================//
input group "=== Channel Breakout (Donchian) ==="
input int      InpChannelPeriod     = 50;        // Donchian Channel period
input int      InpATRPeriod         = 14;        // ATR period
input double   InpATRMinMult        = 1.0;       // Min ATR multiplier (momentum filter)

//================ SL / TP =========================//
input group "=== Stop Loss / Take Profit ==="
input double   InpSL_ATR_Mult       = 1.5;       // SL = ATR x 1.5 (tight)
input double   InpTP_ATR_Mult       = 5.0;       // TP = ATR x 5.0 (BIG target)
input bool     InpUseTrailByChannel = true;       // Trail SL using Donchian middle

//================ TRAILING / BREAKEVEN ============//
input group "=== Profit Protection ==="
input bool     InpUseBreakeven      = true;       // Move SL to BE
input double   InpBE_ATR_Mult       = 1.5;       // BE activate at ATR x 1.5
input double   InpBE_LockPips       = 5.0;       // Lock pips at BE
input bool     InpUseTrailing       = true;       // Trail stop
input double   InpTrail_ATR_Mult    = 2.0;       // Trail distance = ATR x 2

//================ PARTIAL CLOSE ====================//
input group "=== Partial Close ==="
input bool     InpUsePartialClose   = true;       // Partial close ON
input double   InpPartialPercent    = 50.0;       // % to close
input double   InpPartialTP_Mult    = 2.5;        // Close at ATR x 2.5

//================ DAILY GUARD =====================//
input group "=== Daily Guard ==="
input bool     InpUseDailyLimit     = true;
input double   InpDailyTargetUSD    = 20.0;       // Daily target $
input double   InpDailyMaxLossUSD   = 10.0;       // Daily max loss $
input int      InpMaxConsecLoss     = 3;          // Emergency lock after N losses
input int      InpMaxTradesPerDay   = 4;          // Max trades (swing = few)

//================ SESSION / NEWS =================//
input group "=== Session & News ==="
input bool     InpUseSession        = true;
input int      InpStartHour         = 8;
input int      InpEndHour           = 21;
input bool     InpAvoidFridayLate   = true;
input bool     InpUseNewsFilter     = true;
input int      InpNewsBlockMin      = 30;

//================ NOTIFICATIONS ===================//
input group "=== Notifications ==="
input bool     InpSendPush          = true;
input bool     InpSendAlert         = false;
input bool     InpNotifyOnTrade     = true;
input bool     InpNotifyOnBlock     = false;

input group "=== System ==="
input int      InpMagicNumber       = 777777;
input string   InpComment           = "XAU Swing Pro";

//================ CONSTANTS =======================//
#define LICENSE_MASTER_PASS   "ANTU2024PRO"
#define LICENSE_ADMIN_PASS    "ANTUADMIN99"
#define LICENSE_SALT          "ANTU_GOLD_"



//================ GLOBALS =========================//
int      atrHandle=INVALID_HANDLE;
double   dayBalance=0;
datetime lastBarTime=0, gLastBlink=0;
bool     dailyTargetHit=false, gBlinkPhase=false, gEmergencyLocked=false;
int      gConsecLosses=0, cachedDailyTrades=0;
bool     license_valid=false, admin_mode=false;
datetime trial_start_time=0;

//+------------------------------------------------------------------+
//| NOTIFICATION SYSTEM                                              |
//+------------------------------------------------------------------+
void SendNotify(string msg){
   if(InpSendPush) SendNotification(msg);
   if(InpSendAlert) Alert(msg);
   Print(msg);
}
void NotifyTrade(string dir,double lot,double sl,double tp){
   if(!InpNotifyOnTrade) return;
   SendNotify("ANTU SWING: "+dir+" Lot="+DoubleToString(lot,2)+" SL="+DoubleToString(sl,1)+" TP="+DoubleToString(tp,1)+" "+_Symbol);
}
void NotifyBlock(string reason){
   if(!InpNotifyOnBlock) return;
   static string last=""; if(reason==last) return; last=reason;
   SendNotify("ANTU SWING: BLOCKED - "+reason);
}

//+------------------------------------------------------------------+
//| LICENSE SYSTEM                                                    |
//+------------------------------------------------------------------+
string GenerateLicenseKey(long acc){
   string raw=LICENSE_SALT+IntegerToString(acc);int hash=0;
   for(int i=0;i<StringLen(raw);i++){hash=hash*31+StringGetCharacter(raw,i);hash=hash%999999;}
   if(hash<0)hash=-hash;
   return "ANTU-"+IntegerToString(hash,6,'0');
}
bool ValidatePassword(){
   if(InpAdminPassword==LICENSE_ADMIN_PASS){admin_mode=true;return true;}
   if(StringLen(InpPassword)==0){Print("ERROR: Password required!");return false;}
   if(InpPassword!=LICENSE_MASTER_PASS){Print("ERROR: Wrong password!");return false;}
   return true;
}
bool ValidateLicense(){
   if(admin_mode) return true;
   long acc=AccountInfoInteger(ACCOUNT_LOGIN);
   if(StringLen(InpLicenseKey)>0 && InpLicenseKey==GenerateLicenseKey(acc)){license_valid=true;return true;}
   if(InpTrialDays>0){
      string gv="ANTU_SWING_"+IntegerToString(acc);
      datetime fr=(datetime)GlobalVariableGet(gv);
      if(fr==0){fr=TimeCurrent();GlobalVariableSet(gv,(double)fr);trial_start_time=fr;return true;}
      trial_start_time=fr;
      if(InpTrialDays-(int)((TimeCurrent()-fr)/86400)>0)return true;
      else{SendNotify("ANTU SWING: Trial EXPIRED!");return false;}
   }
   return false;
}
void ShowKeyGenerator(){
   long acc=AccountInfoInteger(ACCOUNT_LOGIN);string key=GenerateLicenseKey(acc);
   Alert("Account: "+IntegerToString(acc)+"\nKey: "+key);
   Comment("ANTU KEY GENERATOR\nAccount: "+IntegerToString(acc)+"\nKey: "+key);
}



//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
int CountMyPositions(){
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong t=PositionGetTicket(i);if(t==0)continue;
      if(!PositionSelectByTicket(t))continue;
      if(PositionGetInteger(POSITION_MAGIC)==InpMagicNumber&&PositionGetString(POSITION_SYMBOL)==_Symbol)c++;
   }
   return c;
}

double GetDonchianHigh(int period,int shift){
   double highest=0;
   for(int i=shift;i<shift+period;i++){
      double h=iHigh(_Symbol,PERIOD_H1,i);
      if(h>highest) highest=h;
   }
   return highest;
}

double GetDonchianLow(int period,int shift){
   double lowest=999999;
   for(int i=shift;i<shift+period;i++){
      double l=iLow(_Symbol,PERIOD_H1,i);
      if(l<lowest) lowest=l;
   }
   return lowest;
}

double GetDonchianMid(int period,int shift){
   return (GetDonchianHigh(period,shift)+GetDonchianLow(period,shift))/2.0;
}

double ComputeLot(double slPrice){
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0||tickSz<=0) return InpFixedLot;

   double riskUsd=equity*InpRiskPercent/100.0;
   double lossPerLot=(slPrice/tickSz)*tickVal;
   if(lossPerLot<=0) return InpFixedLot;

   double lot=riskUsd/lossPerLot;
   // MAX SL $ CAP
   if(InpMaxSLDollar>0){
      double maxLot=InpMaxSLDollar/lossPerLot;
      lot=MathMin(lot,maxLot);
   }
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot2=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0)step=0.01;
   lot=MathFloor(lot/step)*step;
   lot=MathMax(lot,minLot);
   lot=MathMin(lot,maxLot2);
   lot=MathMin(lot,InpMaxLotCap);
   return NormalizeDouble(lot,2);
}

bool IsTradingTime(){
   if(!InpUseSession)return true;
   MqlDateTime dt;TimeCurrent(dt);
   if(dt.hour<InpStartHour||dt.hour>=InpEndHour)return false;
   if(InpAvoidFridayLate&&dt.day_of_week==5&&dt.hour>=19)return false;
   return true;
}

bool IsNewsBlock(){
   if(!InpUseNewsFilter||MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION))return false;
   MqlCalendarValue values[];datetime tNow=TimeCurrent();
   if(CalendarValueHistory(values,tNow-(InpNewsBlockMin*60),tNow+(InpNewsBlockMin*60))){
      for(int i=0;i<ArraySize(values);i++){
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id,ev)&&ev.importance>=CALENDAR_IMPORTANCE_HIGH)return true;
      }
   }
   return false;
}



//+------------------------------------------------------------------+
//| TRADE MANAGEMENT (Partial + BE + Trail by Channel)               |
//+------------------------------------------------------------------+
void ManageOpenTrades(){
   double atrArr[];
   if(CopyBuffer(atrHandle,0,1,1,atrArr)<=0) return;
   double atr=atrArr[0];

   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)continue;

      double openP=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      double curPrice=PositionGetDouble(POSITION_PRICE_CURRENT);
      double curLot=PositionGetDouble(POSITION_VOLUME);
      long posType=PositionGetInteger(POSITION_TYPE);
      string comment=PositionGetString(POSITION_COMMENT);

      // PARTIAL CLOSE at ATR x 2.5
      if(InpUsePartialClose && StringFind(comment,"PC")<0){
         double partialDist=atr*InpPartialTP_Mult;
         bool partialHit=false;
         if(posType==POSITION_TYPE_BUY && curPrice>=openP+partialDist) partialHit=true;
         if(posType==POSITION_TYPE_SELL && curPrice<=openP-partialDist) partialHit=true;
         if(partialHit){
            double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
            double closeLot=MathFloor((curLot*InpPartialPercent/100.0)/lotStep)*lotStep;
            double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(closeLot>=minLot && closeLot<curLot){
               trade.PositionClosePartial(ticket,closeLot);
               NotifyTrade("PARTIAL",closeLot,0,0);
               continue;
            }
         }
      }

      if(!PositionSelectByTicket(ticket))continue;
      curSL=PositionGetDouble(POSITION_SL);curPrice=PositionGetDouble(POSITION_PRICE_CURRENT);

      // BREAKEVEN
      if(InpUseBreakeven){
         double beDist=atr*InpBE_ATR_Mult;
         double beLock=InpBE_LockPips*_Point*10;
         if(posType==POSITION_TYPE_BUY && curPrice>openP+beDist){
            double newSL=openP+beLock;
            if(curSL<newSL) trade.PositionModify(ticket,newSL,curTP);
         }
         if(posType==POSITION_TYPE_SELL && curPrice<openP-beDist){
            double newSL=openP-beLock;
            if(curSL>newSL||curSL==0) trade.PositionModify(ticket,newSL,curTP);
         }
      }

      // TRAILING by Donchian Middle OR ATR
      if(InpUseTrailing){
         if(InpUseTrailByChannel){
            // Trail by Donchian middle band
            double mid=GetDonchianMid(InpChannelPeriod,1);
            if(posType==POSITION_TYPE_BUY && mid>curSL && mid>openP)
               trade.PositionModify(ticket,mid,curTP);
            if(posType==POSITION_TYPE_SELL && (mid<curSL||curSL==0) && mid<openP)
               trade.PositionModify(ticket,mid,curTP);
         } else {
            // Trail by ATR
            double trailDist=atr*InpTrail_ATR_Mult;
            if(posType==POSITION_TYPE_BUY){
               double newSL=curPrice-trailDist;
               if(newSL>curSL && newSL>openP) trade.PositionModify(ticket,newSL,curTP);
            }
            if(posType==POSITION_TYPE_SELL){
               double newSL=curPrice+trailDist;
               if((newSL<curSL||curSL==0) && newSL<openP) trade.PositionModify(ticket,newSL,curTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION                                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result){
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal) && HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==InpMagicNumber){
      ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
      if(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_INOUT){
         double pr=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
         cachedDailyTrades++;
         if(pr>0){gConsecLosses=0;if(gEmergencyLocked)gEmergencyLocked=false;}
         else if(pr<0){gConsecLosses++;if(InpMaxConsecLoss>0&&gConsecLosses>=InpMaxConsecLoss)gEmergencyLocked=true;}
      }
   }
}



//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void DrawLabel(string name,int x,int y,string txt,int sz,color clr,bool bold=false){
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,name,OBJPROP_FONT,bold?"Arial Black":"Calibri");
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}

void DrawDashboard(double pnl,string status,color stClr){
   if(MQLInfoInteger(MQL_OPTIMIZATION))return;
   if(ObjectFind(0,"BG")<0)ObjectCreate(0,"BG",OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,"BG",OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,"BG",OBJPROP_XDISTANCE,5);ObjectSetInteger(0,"BG",OBJPROP_YDISTANCE,5);
   ObjectSetInteger(0,"BG",OBJPROP_XSIZE,230);ObjectSetInteger(0,"BG",OBJPROP_YSIZE,200);
   ObjectSetInteger(0,"BG",OBJPROP_BGCOLOR,C'10,12,20');
   ObjectSetInteger(0,"BG",OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,"BG",OBJPROP_COLOR,C'0,150,200');ObjectSetInteger(0,"BG",OBJPROP_WIDTH,2);
   ObjectSetInteger(0,"BG",OBJPROP_BACK,false);

   DrawLabel("T1",15,12,"XAU SWING BREAKOUT PRO",9,clrCyan,true);
   DrawLabel("S1",15,38,"STATUS:",8,C'150,200,255');
   DrawLabel("S2",75,38,status,8,stClr,true);
   DrawLabel("P1",15,58,"Daily P&L:",8,C'150,200,255');
   DrawLabel("P2",85,58,"$"+DoubleToString(pnl,2),9,pnl>=0?C'0,255,100':C'255,50,50',true);
   DrawLabel("M1",15,83,"MAX SL: $"+DoubleToString(InpMaxSLDollar,2),7,C'255,180,50',true);
   DrawLabel("M2",15,103,"Positions: "+IntegerToString(CountMyPositions()),7,C'220,230,255');
   DrawLabel("M3",15,123,"Consec Loss: "+IntegerToString(gConsecLosses)+"/"+IntegerToString(InpMaxConsecLoss),7,gEmergencyLocked?C'255,50,50':C'200,220,255');

   string licInfo=license_valid?"LICENSED":"TRIAL";
   if(trial_start_time>0&&!license_valid){int dl=InpTrialDays-(int)((TimeCurrent()-trial_start_time)/86400);licInfo="TRIAL: "+IntegerToString(dl)+"d";}
   DrawLabel("LC",15,148,licInfo,7,license_valid?C'0,255,100':C'255,180,50');
   DrawLabel("FT",40,175,"POWERED BY ANTU TRADING",7,C'0,150,200',true);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| INIT / DEINIT                                                    |
//+------------------------------------------------------------------+
int OnInit(){
   if(!ValidatePassword()){Alert("ANTU: Invalid Password!");return(INIT_FAILED);}
   if(admin_mode){ShowKeyGenerator();return(INIT_SUCCEEDED);}
   if(!ValidateLicense()){Alert("ANTU: License expired!");return(INIT_FAILED);}

   trade.SetExpertMagicNumber(InpMagicNumber);trade.SetDeviationInPoints(10);
   dayBalance=AccountInfoDouble(ACCOUNT_EQUITY);

   atrHandle=iATR(_Symbol,PERIOD_H1,InpATRPeriod);
   if(atrHandle==INVALID_HANDLE){Print("ERROR: ATR handle failed!");return(INIT_FAILED);}

   SendNotify("XAU Swing Breakout PRO started! MaxSL:$"+DoubleToString(InpMaxSLDollar,2));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   Comment("");ObjectsDeleteAll(0);IndicatorRelease(atrHandle);ChartRedraw();
}



//+------------------------------------------------------------------+
//| ON TICK — MAIN LOGIC (Donchian Breakout + ATR Momentum)          |
//+------------------------------------------------------------------+
void OnTick(){
   if(admin_mode) return;

   // Daily reset
   MqlDateTime dt;TimeCurrent(dt);
   static int prevDay=-1;
   if(dt.day!=prevDay){prevDay=dt.day;dailyTargetHit=false;cachedDailyTrades=0;gConsecLosses=0;gEmergencyLocked=false;dayBalance=AccountInfoDouble(ACCOUNT_EQUITY);}

   double pnl=AccountInfoDouble(ACCOUNT_EQUITY)-dayBalance;
   if(InpUseDailyLimit&&(pnl>=InpDailyTargetUSD||pnl<=-InpDailyMaxLossUSD)) dailyTargetHit=true;

   ManageOpenTrades();

   // Status
   string status="HUNTING"; color stClr=C'0,255,100';
   if(dailyTargetHit){status="TARGET HIT";stClr=C'255,215,0';}
   else if(gEmergencyLocked){status="LOCKED";stClr=C'255,50,50';}
   else if(!IsTradingTime()){status="SLEEPING";stClr=C'165,165,165';}
   else if(IsNewsBlock()){status="NEWS BLOCK";stClr=C'255,100,0';}
   else if(CountMyPositions()>0){status="IN TRADE";stClr=C'0,200,255';}

   static datetime lastUI=0;
   if(TimeCurrent()-lastUI>=1){DrawDashboard(pnl,status,stClr);lastUI=TimeCurrent();}

   // BLOCK CONDITIONS
   if(dailyTargetHit||gEmergencyLocked||!IsTradingTime()||IsNewsBlock()) return;
   if((int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpMaxSLDollar*100) return; // spread sanity
   if(InpMaxTradesPerDay>0 && cachedDailyTrades>=InpMaxTradesPerDay) return;

   // NEW BAR ONLY (H1)
   datetime timeArr[];
   if(CopyTime(_Symbol,PERIOD_H1,0,1,timeArr)<=0||timeArr[0]==lastBarTime) return;
   lastBarTime=timeArr[0];

   // Already in trade? Skip
   if(CountMyPositions()>0) return;

   // GET ATR
   double atrArr[];
   if(CopyBuffer(atrHandle,0,1,1,atrArr)<=0) return;
   double atr=atrArr[0];

   // ATR MOMENTUM FILTER: ATR must be above average
   double atrAvg[];
   if(CopyBuffer(atrHandle,0,1,20,atrAvg)<=0) return;
   double avgATR=0;
   for(int i=0;i<20;i++) avgATR+=atrAvg[i];
   avgATR/=20.0;
   if(atr < avgATR*InpATRMinMult) return; // No momentum = no trade

   // DONCHIAN CHANNEL
   double channelHigh = GetDonchianHigh(InpChannelPeriod, 1); // Previous bars (not current)
   double channelLow  = GetDonchianLow(InpChannelPeriod, 1);
   double channelMid  = (channelHigh+channelLow)/2.0;

   // CURRENT CLOSE
   double close1=iClose(_Symbol,PERIOD_H1,1); // Last completed bar

   // PREVIOUS CLOSE (bar before)
   double close2=iClose(_Symbol,PERIOD_H1,2);

   // BREAKOUT SIGNALS
   bool buySignal  = (close1 > channelHigh && close2 <= channelHigh); // Break above
   bool sellSignal = (close1 < channelLow  && close2 >= channelLow);  // Break below

   if(!buySignal && !sellSignal) return;

   // CALCULATE SL/TP
   double slDist = atr * InpSL_ATR_Mult;
   double tpDist = atr * InpTP_ATR_Mult;

   double lot = ComputeLot(slDist);
   if(lot<=0) return;

   // ENTRY
   if(buySignal){
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=ask-slDist;
      double tp=ask+tpDist;
      if(trade.Buy(lot,_Symbol,ask,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),InpComment))
         NotifyTrade("BUY",lot,slDist,tpDist);
   }
   if(sellSignal){
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=bid+slDist;
      double tp=bid-tpDist;
      if(trade.Sell(lot,_Symbol,bid,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),InpComment))
         NotifyTrade("SELL",lot,slDist,tpDist);
   }
}
//+------------------------------------------------------------------+
