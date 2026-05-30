//+------------------------------------------------------------------+
//|                              ANTU_GOLDMIND_PRO_V6_SAFE.mq5       |
//|        Strategy: Quality Range Scalp + News Guard + Trailing     |
//|        Target Asset: XAUUSD (Gold)                               |
//|        Philosophy: SMALL LOSS, STEADY GAIN, NEWS = NO TRADE      |
//+------------------------------------------------------------------+
#property copyright "ANTU Trading"
#property version   "6.50"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//================ LICENSE & PASSWORD SYSTEM =========//
input group "=== License & Security ==="
input string   InpPassword           = "";       // EA Password (required)
input string   InpLicenseKey         = "";       // License Key (get from ANTU Trading)
input int      InpTrialDays          = 7;        // Trial period days (0=no trial)
input string   InpAdminPassword      = "";       // Admin Password (for key generator)


//================ MONEY MANAGEMENT =================//
input group "=== Money Management ==="
input bool     InpUseRiskPercent     = true;     // Use % Risk
input double   InpRiskPercent        = 0.5;      // Risk % per trade
input double   InpFixedLotSize       = 0.01;     // Fixed Lot (if % off)
input double   InpMaxLotCap          = 0.50;     // Max Lot Cap
input double   InpMaxSLDollar        = 3.0;      // MAX SL $ per trade (hard cap - DD control)

//================ SL / TP =========================//
input group "=== Stop Loss / Take Profit ==="
input bool     InpUseATRStops        = true;     // Use ATR-based SL/TP
input double   InpATRMultSL          = 1.2;      // ATR x for SL (tight SL = small loss)
input double   InpATRMultTP          = 3.5;      // ATR x for TP (wide TP = big profit)
input double   InpFixedSLPips        = 25.0;     // Fixed SL pips (if ATR off)
input double   InpFixedTPPips        = 30.0;     // Fixed TP pips (if ATR off)

//================ TRAILING / BREAKEVEN ============//
input group "=== Trailing & Breakeven ==="
input bool     InpUseBreakeven       = true;     // Move SL to BE
input double   InpBEActivatePips     = 7.0;      // Activate BE after +X pips (quick BE)
input double   InpBEOffsetPips       = 2.0;      // Lock +X pips at BE
input bool     InpUseTrailing        = true;     // Trail stop
input double   InpTrailStartPips     = 10.0;     // Start trail after +X pips (earlier trail)
input double   InpTrailStepPips      = 5.0;      // Trail distance pips (tight = lock more profit)

//================ PARTIAL CLOSE ====================//
input group "=== Partial Close (Profit Booster) ==="
input bool     InpUsePartialClose    = true;     // Enable Partial Close
input double   InpPartialPercent     = 50.0;     // % of position to close (50 = half)
input double   InpPartialTPRatio     = 0.5;      // Close at X of full TP (0.5 = half TP)


//================ DAILY GUARD =====================//
input group "=== Daily Guard ==="
input bool     InpUsePercentGuard    = true;     // Use % of balance
input double   InpDailyTargetPct     = 5.0;      // Daily Target %
input double   InpDailyMaxLossPct    = 5.0;      // Daily Max Loss %
input double   InpDailyTargetUSD     = 30.0;     // Daily Target $ (if % off)
input double   InpDailyMaxLossUSD    = 15.0;     // Daily Max Loss $ (if % off)
input int      InpMaxConsecutiveLoss = 3;        // Stop after N losses
input int      InpMaxTradesPerDay    = 8;        // Max trades per day

//================ QUALITY FILTERS =================//
input group "=== Quality Filters ==="
input double   InpMinBandDistancePips = 50.0;    // Min BB width pips
input int      InpMaxSpread          = 350;      // Max spread points
input double   InpMinATRPips         = 10.0;     // Min ATR pips
input double   InpMaxATRPips         = 400.0;    // Max ATR pips
input bool     InpUseATRMaxFilter    = true;     // Enable HIGH VOL block

//================ TIME / NEWS GUARD ===============//
input group "=== Time & News Guard ==="
input bool     InpUseSessionTime     = true;     // Use trading hours
input int      InpStartHour          = 8;        // Start hour
input int      InpEndHour            = 21;       // End hour
input bool     InpAvoidFridayLate    = true;     // No trade Fri after 19:00
input bool     InpAvoidMondayOpen    = true;     // No trade Mon before 09:00
input string   InpNewsTimes          = "13:30,15:00,18:00"; // News HH:MM CSV
input int      InpNewsBlockMinutes   = 15;       // Block X min before/after


//================ NOTIFICATIONS ===================//
input group "=== Mobile Notifications ==="
input bool     InpSendPushNotify     = true;     // Send Push to Mobile
input bool     InpSendAlert          = false;    // Show Alert popup on PC
input bool     InpNotifyOnTrade      = true;     // Notify on trade open
input bool     InpNotifyOnBlock      = false;    // Notify when blocked

input group "=== System ==="
input int      InpMagicNumber        = 654321;
input string   InpComment            = "Goldmind V6 Safe";

//================ DASHBOARD COLORS ================//
#define CLR_BG_OUTER  C'150,120,40'
#define CLR_BG_INNER  C'18,18,22'
#define CLR_HEADER    C'212,175,55'
#define CLR_LINE      C'35,35,42'
#define CLR_TXT_MUTED C'140,145,150'
#define CLR_TXT_WHITE C'250,250,255'
#define CLR_PROFIT    C'0,220,110'
#define CLR_LOSS      C'255,70,70'
#define CLR_WARN      C'255,180,50'

//--- LICENSE CONSTANTS
#define LICENSE_MASTER_PASS   "ANTU2024PRO"
#define LICENSE_ADMIN_PASS    "ANTUADMIN99"
#define LICENSE_SALT          "ANTU_GOLD_"


//--- Globals
int      bb_handle, rsi_handle, atr_handle;
double   bb_upper[], bb_lower[], rsi_buffer[], atr_buffer[];

datetime last_bar_time = 0;
int      last_deals_total = 0;
double   cached_daily_profit = 0.0;
int      cached_daily_trades = 0;
int      cached_consec_losses = 0;
int      current_day = -1;
bool     license_valid = false;
datetime trial_start_time = 0;
bool     admin_mode = false;

datetime news_times_today[];

//+------------------------------------------------------------------+
//| Pip helper                                                       |
//+------------------------------------------------------------------+
double PipsToPrice(double pips) { return pips * _Point * 10.0; }
double PriceToPips(double price){ return price / (_Point * 10.0); }


//+------------------------------------------------------------------+
//| NOTIFICATION SYSTEM                                              |
//+------------------------------------------------------------------+
void SendNotify(string msg){
   if(InpSendPushNotify) SendNotification(msg);
   if(InpSendAlert) Alert(msg);
   Print(msg);
}

void NotifyTradeOpen(string direction,double lot,double slPips,double tpPips){
   if(!InpNotifyOnTrade) return;
   string msg = "ANTU EA: "+direction+" | Lot="+DoubleToString(lot,2)
              +" | SL="+DoubleToString(slPips,1)+"pip"
              +" | TP="+DoubleToString(tpPips,1)+"pip | "+_Symbol;
   SendNotify(msg);
}

void NotifyBlock(string reason){
   if(!InpNotifyOnBlock) return;
   static string lastReason = "";
   if(reason == lastReason) return;
   lastReason = reason;
   SendNotify("ANTU EA: BLOCKED - " + reason);
}


//+------------------------------------------------------------------+
//| LICENSE KEY GENERATOR (Built-in Admin Panel)                     |
//| Admin password se khulega, account number daalo, key milegi      |
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
   // Admin mode - show key for current account
   long accNum = AccountInfoInteger(ACCOUNT_LOGIN);
   string key = GenerateLicenseKey(accNum);
   
   string msg = "========= ANTU KEY GENERATOR =========\n"
              + "Account Number: " + IntegerToString(accNum) + "\n"
              + "License Key: " + key + "\n"
              + "======================================\n"
              + "Yeh key client ko do.\n"
              + "Client EA settings mein License Key field mein paste karega.";
   
   Alert(msg);
   Print("=== KEY GENERATOR ===");
   Print("Account: ", accNum);
   Print("Key: ", key);
   Print("=====================");
   
   // Also show on chart as comment
   Comment("ANTU KEY GENERATOR\n"
          +"Account: "+IntegerToString(accNum)+"\n"
          +"License Key: "+key+"\n\n"
          +"Yeh key client ko do!");
}


//+------------------------------------------------------------------+
//| PASSWORD & LICENSE VALIDATION                                    |
//+------------------------------------------------------------------+
bool ValidatePassword(){
   // Check if admin mode (key generator)
   if(InpAdminPassword == LICENSE_ADMIN_PASS){
      admin_mode = true;
      return true;
   }
   
   if(StringLen(InpPassword)==0){
      Print("ERROR: Password required! Contact ANTU Trading.");
      return false;
   }
   if(InpPassword != LICENSE_MASTER_PASS){
      Print("ERROR: Invalid password!");
      return false;
   }
   return true;
}

bool ValidateLicense(){
   // Admin mode doesn't need license
   if(admin_mode) return true;
   
   long accNum = AccountInfoInteger(ACCOUNT_LOGIN);

   // Check license key
   if(StringLen(InpLicenseKey) > 0){
      string validKey = GenerateLicenseKey(accNum);
      if(InpLicenseKey == validKey){
         license_valid = true;
         Print("LICENSE VALID. Account: ", accNum);
         return true;
      }
   }

   // Check trial
   if(InpTrialDays > 0){
      string gvName = "ANTU_FIRST_RUN_" + IntegerToString(accNum);
      datetime firstRun = (datetime)GlobalVariableGet(gvName);
      if(firstRun == 0){
         firstRun = TimeCurrent();
         GlobalVariableSet(gvName, (double)firstRun);
         trial_start_time = firstRun;
         Print("TRIAL STARTED: ", InpTrialDays, " days. Account: ", accNum);
         SendNotify("ANTU EA: Trial started! "+IntegerToString(InpTrialDays)+" days free.");
         return true;
      }
      trial_start_time = firstRun;
      int elapsed = (int)((TimeCurrent() - firstRun) / 86400);
      int daysLeft = InpTrialDays - elapsed;
      if(daysLeft > 0){
         Print("TRIAL: ", daysLeft, " days left. Account: ", accNum);
         return true;
      } else {
         Print("TRIAL EXPIRED! Contact ANTU Trading. Account: ", accNum);
         SendNotify("ANTU EA: Trial EXPIRED! Get license from ANTU Trading.");
         return false;
      }
   }

   Print("NO LICENSE. Account: ", accNum);
   return false;
}


//+------------------------------------------------------------------+
//| Count OUR positions                                              |
//+------------------------------------------------------------------+
int CountMyPositions(){
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--){
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| MAX SL $ CAP                                                     |
//+------------------------------------------------------------------+
double CalcMaxLotForDollarSL(double slPips){
   if(InpMaxSLDollar <= 0) return InpMaxLotCap;
   double tickVal  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0 || tickSize<=0) return InpFixedLotSize;
   double slPrice = PipsToPrice(slPips);
   double lossPerLot = (slPrice / tickSize) * tickVal;
   if(lossPerLot<=0) return InpFixedLotSize;
   return InpMaxSLDollar / lossPerLot;
}


//+------------------------------------------------------------------+
//| Lot calculator with $5 MAX SL CAP                                |
//+------------------------------------------------------------------+
double CalcLot(double slPips){
   double lot;
   if(!InpUseRiskPercent){
      lot = InpFixedLotSize;
   } else {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskUsd = balance * InpRiskPercent / 100.0;
      double tickVal  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickVal<=0 || tickSize<=0) return NormalizeLot(InpFixedLotSize);
      double slPrice = PipsToPrice(slPips);
      double lossPerLot = (slPrice / tickSize) * tickVal;
      if(lossPerLot<=0) return NormalizeLot(InpFixedLotSize);
      lot = riskUsd / lossPerLot;
   }
   double maxLotByCap = CalcMaxLotForDollarSL(slPips);
   lot = MathMin(lot, maxLotByCap);
   return NormalizeLot(lot);
}

double NormalizeLot(double lot){
   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step = 0.01;
   lot = MathFloor(lot/step)*step;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   lot = MathMin(lot, InpMaxLotCap);
   return NormalizeDouble(lot,2);
}


//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawRect(string name,int x,int y,int w,int h,color bg){
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}

void DrawText(string name,int x,int y,string txt,int sz,color clr,string font="Segoe UI",bool bold=false){
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,name,OBJPROP_FONT, bold ? font+" Bold" : font);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
}


void UpdateDashboard(double pnl,int spread,double band_dist,double atrPips,string status){
   DrawRect("UI_Outer",20,30,310,330,CLR_BG_OUTER);
   DrawRect("UI_Inner",22,32,306,326,CLR_BG_INNER);
   DrawRect("UI_Header",22,32,306,40,CLR_HEADER);
   DrawText("UI_Title",45,40,"ANTU GOLDMIND PRO V6",11,C'15,15,15',"Segoe UI Black",true);

   DrawRect("UI_Line1",40,105,270,1,CLR_LINE);
   DrawRect("UI_Line2",40,155,270,1,CLR_LINE);
   DrawRect("UI_Line3",40,225,270,1,CLR_LINE);

   color stC = CLR_PROFIT;
   if(status=="TARGET HIT"||status=="LOSS HIT"||status=="MAX LOSSES") stC=CLR_LOSS;
   else if(status=="NEWS BLOCK"||status=="HIGH SPREAD"||status=="LOW VOL"||status=="HIGH VOL") stC=CLR_WARN;
   else if(status!="ACTIVE") stC=CLR_TXT_MUTED;

   DrawText("L_Status",40,80,"SYSTEM STATUS",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Status",180,78,status,9,stC,"Segoe UI Black",true);

   DrawText("L_Net",40,120,"TODAY P/L",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Net",180,115,"$"+DoubleToString(pnl,2),14,pnl>=0?CLR_PROFIT:CLR_LOSS,"Consolas",true);

   DrawText("L_Spread",40,170,"SPREAD",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Spread",180,170,IntegerToString(spread)+" / "+IntegerToString(InpMaxSpread),8,
            spread>InpMaxSpread?CLR_LOSS:CLR_TXT_WHITE,"Consolas",true);

   DrawText("L_BBW",40,190,"BAND WIDTH",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_BBW",180,190,DoubleToString(band_dist,1)+" / "+DoubleToString(InpMinBandDistancePips,0),8,
            band_dist<InpMinBandDistancePips?CLR_WARN:CLR_TXT_WHITE,"Consolas",true);


   DrawText("L_ATR",40,205,"ATR (PIPS)",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_ATR",180,205,DoubleToString(atrPips,1),8,
            (atrPips<InpMinATRPips||atrPips>InpMaxATRPips)?CLR_WARN:CLR_TXT_WHITE,"Consolas",true);

   DrawText("L_Trades",40,240,"TRADES TODAY",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Trades",180,240,IntegerToString(cached_daily_trades)+" / "+IntegerToString(InpMaxTradesPerDay),8,CLR_TXT_WHITE,"Consolas",true);

   DrawText("L_Loss",40,255,"CONSEC LOSS",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Loss",180,255,IntegerToString(cached_consec_losses)+" / "+IntegerToString(InpMaxConsecutiveLoss),8,
            cached_consec_losses>=InpMaxConsecutiveLoss?CLR_LOSS:CLR_TXT_WHITE,"Consolas",true);

   DrawText("L_MyPos",40,270,"MY POSITIONS",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_MyPos",180,270,IntegerToString(CountMyPositions()),8,CLR_TXT_WHITE,"Consolas",true);

   DrawText("L_MaxSL",40,285,"MAX SL CAP",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_MaxSL",180,285,"$"+DoubleToString(InpMaxSLDollar,2),8,CLR_WARN,"Consolas",true);

   // License info
   string licInfo = "LICENSED";
   if(!license_valid){
      if(trial_start_time > 0){
         int elapsed = (int)((TimeCurrent()-trial_start_time)/86400);
         int daysLeft = InpTrialDays - elapsed;
         licInfo = "TRIAL: "+IntegerToString(daysLeft)+"d left";
      } else licInfo = "TRIAL";
   }
   DrawText("L_Lic",40,300,"LICENSE",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Lic",180,300,licInfo,8,license_valid?CLR_PROFIT:CLR_WARN,"Consolas",true);

   DrawText("UI_Footer",85,335,"POWERED BY ANTU TRADING",7,CLR_BG_OUTER,"Segoe UI",true);
}


//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit(){
   // PASSWORD CHECK
   if(!ValidatePassword()){
      Alert("ANTU EA: Invalid Password! Contact ANTU Trading.");
      return(INIT_FAILED);
   }
   
   // ADMIN MODE - Show Key Generator and stop
   if(admin_mode){
      ShowKeyGeneratorPanel();
      Print("=== ADMIN MODE: Key Generator Active ===");
      Print("Attach EA to CLIENT's account to see their key.");
      Print("Or check Experts tab for current account key.");
      return(INIT_SUCCEEDED);
   }
   
   // LICENSE CHECK
   license_valid = false;
   if(!ValidateLicense()){
      Alert("ANTU EA: License expired! Contact ANTU Trading.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();

   bb_handle  = iBands(_Symbol,PERIOD_CURRENT,20,0,2.0,PRICE_CLOSE);
   rsi_handle = iRSI(_Symbol,PERIOD_CURRENT,14,PRICE_CLOSE);
   atr_handle = iATR(_Symbol,PERIOD_CURRENT,14);

   if(bb_handle==INVALID_HANDLE||rsi_handle==INVALID_HANDLE||atr_handle==INVALID_HANDLE){
      Print("ERROR: Indicator handle creation failed!");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(bb_upper,true);
   ArraySetAsSeries(bb_lower,true);
   ArraySetAsSeries(rsi_buffer,true);
   ArraySetAsSeries(atr_buffer,true);

   ParseNewsTimes();
   long accNum = AccountInfoInteger(ACCOUNT_LOGIN);
   SendNotify("ANTU EA started! Acc:"+IntegerToString(accNum)+" MaxSL:$"+DoubleToString(InpMaxSLDollar,2));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   Comment("");
   ObjectsDeleteAll(0,"UI_");
   ObjectsDeleteAll(0,"L_");
   ObjectsDeleteAll(0,"V_");
   IndicatorRelease(bb_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(atr_handle);
}


//+------------------------------------------------------------------+
//| News Times Parser                                                |
//+------------------------------------------------------------------+
void ParseNewsTimes(){
   ArrayResize(news_times_today,0);
   if(StringLen(InpNewsTimes)==0) return;
   string parts[];
   int n = StringSplit(InpNewsTimes,',',parts);
   MqlDateTime now; TimeCurrent(now);
   for(int i=0;i<n;i++){
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      string hm[];
      if(StringSplit(s,':',hm)!=2) continue;
      int hh=(int)StringToInteger(hm[0]);
      int mm=(int)StringToInteger(hm[1]);
      MqlDateTime nt = now;
      nt.hour=hh; nt.min=mm; nt.sec=0;
      datetime t = StructToTime(nt);
      int sz = ArraySize(news_times_today);
      ArrayResize(news_times_today,sz+1);
      news_times_today[sz]=t;
   }
}

bool IsNewsBlock(){
   if(ArraySize(news_times_today)==0) return false;
   datetime nowT = TimeCurrent();
   int blockSec = InpNewsBlockMinutes*60;
   for(int i=0;i<ArraySize(news_times_today);i++){
      if(MathAbs((long)nowT-(long)news_times_today[i]) <= blockSec) return true;
   }
   return false;
}


//+------------------------------------------------------------------+
//| Daily Stats                                                      |
//+------------------------------------------------------------------+
void RefreshDailyStats(){
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.day != current_day){
      current_day = dt.day;
      cached_daily_profit = 0.0;
      cached_daily_trades = 0;
      cached_consec_losses = 0;
      last_deals_total = 0;
      ParseNewsTimes();
   }
   datetime startOfDay = TimeCurrent()-(TimeCurrent()%86400);
   HistorySelect(startOfDay, TimeCurrent());
   int deals = HistoryDealsTotal();
   if(deals == last_deals_total) return;

   double profit = 0.0;
   int trades = 0;
   int consec = 0;
   for(int i=0;i<deals;i++){
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk,DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(tk,DEAL_ENTRY);
      double p = HistoryDealGetDouble(tk,DEAL_PROFIT)
               + HistoryDealGetDouble(tk,DEAL_SWAP)
               + HistoryDealGetDouble(tk,DEAL_COMMISSION);
      profit += p;
      if(entry == DEAL_ENTRY_OUT){
         trades++;
         if(p < 0) consec++;
         else consec = 0;
      }
   }
   cached_daily_profit  = profit;
   cached_daily_trades  = trades;
   cached_consec_losses = consec;
   last_deals_total     = deals;
}

//+------------------------------------------------------------------+
//| Time Filter                                                      |
//+------------------------------------------------------------------+
bool IsTradingTime(){
   if(!InpUseSessionTime) return true;
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
   if(InpAvoidFridayLate && dt.day_of_week==5 && dt.hour>=19) return false;
   if(InpAvoidMondayOpen && dt.day_of_week==1 && dt.hour<9)   return false;
   return true;
}


//+------------------------------------------------------------------+
//| Trailing / Breakeven / Partial Close                             |
//+------------------------------------------------------------------+
void ManageOpenPositions(){
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      long type   = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double bid  = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double newSL = sl;

      if(type==POSITION_TYPE_BUY){
         double profitPips = PriceToPips(bid - open);
         double tpPips = PriceToPips(tp - open);
         
         // PARTIAL CLOSE: Close half at 50% of TP
         if(InpUsePartialClose && tpPips > 0){
            double partialTarget = tpPips * InpPartialTPRatio;
            if(profitPips >= partialTarget){
               double closeLot = NormalizeDouble(vol * InpPartialPercent / 100.0, 2);
               double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               if(closeLot >= minLot && vol > minLot){
                  // Check if already partially closed (volume reduced)
                  string comment = PositionGetString(POSITION_COMMENT);
                  if(StringFind(comment, "PC") < 0){
                     trade.PositionClosePartial(ticket, closeLot);
                     PrintFormat("PARTIAL CLOSE BUY: %.2f lot at +%.1f pips", closeLot, profitPips);
                     if(InpNotifyOnTrade)
                        SendNotify("ANTU EA: PARTIAL CLOSE BUY +"+DoubleToString(profitPips,1)+"pip");
                     continue; // skip further modification this tick
                  }
               }
            }
         }
         
         // Breakeven
         if(InpUseBreakeven && profitPips >= InpBEActivatePips){
            double be = open + PipsToPrice(InpBEOffsetPips);
            if(sl < be) newSL = be;
         }
         // Trailing
         if(InpUseTrailing && profitPips >= InpTrailStartPips){
            double trail = bid - PipsToPrice(InpTrailStepPips);
            if(trail > newSL) newSL = trail;
         }
         if(newSL > sl + _Point)
            trade.PositionModify(ticket,NormalizeDouble(newSL,_Digits),tp);
      }
      else if(type==POSITION_TYPE_SELL){
         double profitPips = PriceToPips(open - ask);
         double tpPips = PriceToPips(open - tp);
         
         // PARTIAL CLOSE: Close half at 50% of TP
         if(InpUsePartialClose && tpPips > 0){
            double partialTarget = tpPips * InpPartialTPRatio;
            if(profitPips >= partialTarget){
               double closeLot = NormalizeDouble(vol * InpPartialPercent / 100.0, 2);
               double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               if(closeLot >= minLot && vol > minLot){
                  string comment = PositionGetString(POSITION_COMMENT);
                  if(StringFind(comment, "PC") < 0){
                     trade.PositionClosePartial(ticket, closeLot);
                     PrintFormat("PARTIAL CLOSE SELL: %.2f lot at +%.1f pips", closeLot, profitPips);
                     if(InpNotifyOnTrade)
                        SendNotify("ANTU EA: PARTIAL CLOSE SELL +"+DoubleToString(profitPips,1)+"pip");
                     continue;
                  }
               }
            }
         }
         
         // Breakeven
         if(InpUseBreakeven && profitPips >= InpBEActivatePips){
            double be = open - PipsToPrice(InpBEOffsetPips);
            if(sl==0 || sl > be) newSL = be;
         }
         // Trailing
         if(InpUseTrailing && profitPips >= InpTrailStartPips){
            double trail = ask + PipsToPrice(InpTrailStepPips);
            if(newSL==0 || trail < newSL) newSL = trail;
         }
         if(newSL!=sl && (sl==0 || newSL < sl - _Point))
            trade.PositionModify(ticket,NormalizeDouble(newSL,_Digits),tp);
      }
   }
}


//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick(){
   // Admin mode - no trading, only key generator
   if(admin_mode) return;
   
   RefreshDailyStats();
   ManageOpenPositions();

   int spread = (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(CopyBuffer(bb_handle,1,0,3,bb_upper)<=0) return;
   if(CopyBuffer(bb_handle,2,0,3,bb_lower)<=0) return;
   if(CopyBuffer(atr_handle,0,0,3,atr_buffer)<=0) return;

   double bandPips = PriceToPips(bb_upper[0]-bb_lower[0]);
   double atrPips  = PriceToPips(atr_buffer[0]);

   string status = "ACTIVE";
   bool blocked = false;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double targetUSD, maxLossUSD;
   if(InpUsePercentGuard){
      targetUSD  = balance * InpDailyTargetPct / 100.0;
      maxLossUSD = balance * InpDailyMaxLossPct / 100.0;
   } else {
      targetUSD  = InpDailyTargetUSD;
      maxLossUSD = InpDailyMaxLossUSD;
   }

   if(targetUSD>0 && cached_daily_profit>=targetUSD){
      status="TARGET HIT"; blocked=true;
      NotifyBlock("Target hit $"+DoubleToString(cached_daily_profit,2));
   }
   else if(maxLossUSD>0 && cached_daily_profit<=-maxLossUSD){
      status="LOSS HIT"; blocked=true;
      NotifyBlock("Loss limit $"+DoubleToString(cached_daily_profit,2));
   }
   else if(InpMaxConsecutiveLoss>0 && cached_consec_losses>=InpMaxConsecutiveLoss){status="MAX LOSSES";blocked=true;}
   else if(InpMaxTradesPerDay>0 && cached_daily_trades>=InpMaxTradesPerDay){status="MAX TRADES";blocked=true;}
   else if(!IsTradingTime()){status="SLEEPING";blocked=true;}
   else if(IsNewsBlock()){status="NEWS BLOCK";blocked=true;}
   else if(spread>InpMaxSpread){status="HIGH SPREAD";blocked=true;}
   else if(bandPips<InpMinBandDistancePips){status="LOW VOL";blocked=true;}
   else if(atrPips<InpMinATRPips){status="LOW VOL";blocked=true;}
   else if(InpUseATRMaxFilter && atrPips>InpMaxATRPips){status="HIGH VOL";blocked=true;}

   UpdateDashboard(cached_daily_profit, spread, bandPips, atrPips, status);

   if(blocked) return;
   if(CountMyPositions() > 0) return;


   // New bar only
   datetime ct = iTime(_Symbol,PERIOD_CURRENT,0);
   if(ct == last_bar_time) return;

   if(CopyBuffer(rsi_handle,0,1,3,rsi_buffer)<=0) return;
   last_bar_time = ct;

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double last_close = iClose(_Symbol,PERIOD_CURRENT,1);

   double slPips, tpPips;
   if(InpUseATRStops){
      slPips = atrPips * InpATRMultSL;
      tpPips = atrPips * InpATRMultTP;
      slPips = MathMin(slPips, InpFixedSLPips * 1.5);
      tpPips = MathMax(tpPips, slPips * 1.1);
   } else {
      slPips = InpFixedSLPips;
      tpPips = InpFixedTPPips;
   }

   double lot = CalcLot(slPips);
   if(lot<=0) return;

   //-------- BUY SIGNAL
   if(last_close <= bb_lower[1] && rsi_buffer[0] < 35.0){
      double sl = ask - PipsToPrice(slPips);
      double tp = ask + PipsToPrice(tpPips);
      if(!trade.Buy(lot,_Symbol,ask,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),InpComment))
         PrintFormat("Buy failed: %d %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
      else
         NotifyTradeOpen("BUY",lot,slPips,tpPips);
      return;
   }

   //-------- SELL SIGNAL
   if(last_close >= bb_upper[1] && rsi_buffer[0] > 65.0){
      double sl = bid + PipsToPrice(slPips);
      double tp = bid - PipsToPrice(tpPips);
      if(!trade.Sell(lot,_Symbol,bid,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),InpComment))
         PrintFormat("Sell failed: %d %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
      else
         NotifyTradeOpen("SELL",lot,slPips,tpPips);
      return;
   }
}
//+------------------------------------------------------------------+
