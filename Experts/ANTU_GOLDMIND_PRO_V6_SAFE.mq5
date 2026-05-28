//+------------------------------------------------------------------+
//|                              ANTU_GOLDMIND_PRO_V6_SAFE.mq5       |
//|        Strategy: Quality Range Scalp + News Guard + Trailing     |
//|        Target Asset: XAUUSD (Gold)                               |
//|        Philosophy: SMALL LOSS, STEADY GAIN, NEWS = NO TRADE      |
//+------------------------------------------------------------------+
#property copyright "Kiran Group"
#property version   "6.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//================ MONEY MANAGEMENT =================//
input group "=== Money Management ==="
input bool     InpUseRiskPercent     = true;     // Use % Risk (recommended)
input double   InpRiskPercent        = 0.5;      // Risk % per trade (of balance)
input double   InpFixedLotSize       = 0.01;     // Fixed Lot (if % off)
input double   InpMaxLotCap          = 0.50;     // Max Lot Cap (safety)

//================ SL / TP (TIGHT & SAFE) ==========//
input group "=== Stop Loss / Take Profit ==="
input bool     InpUseATRStops        = true;     // Use ATR-based SL/TP
input double   InpATRMultSL          = 1.8;      // ATR x for SL
input double   InpATRMultTP          = 2.2;      // ATR x for TP (R:R ~1.2)
input double   InpFixedSLPips        = 25.0;     // Fixed SL pips (if ATR off)
input double   InpFixedTPPips        = 30.0;     // Fixed TP pips (if ATR off)

//================ TRAILING / BREAKEVEN ============//
input group "=== Trailing & Breakeven ==="
input bool     InpUseBreakeven       = true;     // Move SL to BE in profit
input double   InpBEActivatePips     = 10.0;     // Activate BE after +X pips
input double   InpBEOffsetPips       = 2.0;      // Lock +X pips at BE
input bool     InpUseTrailing        = true;     // Trail stop in profit
input double   InpTrailStartPips     = 15.0;     // Start trail after +X pips
input double   InpTrailStepPips      = 8.0;      // Trail distance pips

//================ DAILY GUARD =====================//
input group "=== Daily Guard ==="
input bool     InpUsePercentGuard    = true;     // Use % of balance (auto-scale) instead of fixed $
input double   InpDailyTargetPct     = 5.0;      // Daily Target % of balance (e.g. 5% of $200 = $10)
input double   InpDailyMaxLossPct    = 3.0;      // Daily Max Loss % of balance (e.g. 3% of $200 = $6)
input double   InpDailyTargetUSD     = 30.0;     // Daily Target $ (used if % guard OFF, 0 = unlimited)
input double   InpDailyMaxLossUSD    = 8.0;      // Daily Max Loss $ (used if % guard OFF, 0 = unlimited)
input int      InpMaxConsecutiveLoss = 2;        // Stop after N back-to-back losses (0 = off)
input int      InpMaxTradesPerDay    = 6;        // Max trades per day (0 = unlimited)

//================ QUALITY FILTERS =================//
input group "=== Quality Filters ==="
input double   InpMinBandDistancePips = 80.0;    // Min BB width pips (raised for high gold price)
input int      InpMaxSpread          = 350;      // Max spread points
input double   InpMinATRPips         = 15.0;    // Min ATR pips (avoid dead market)
input double   InpMaxATRPips         = 350.0;    // Max ATR pips (only block real news spikes)
input bool     InpUseATRMaxFilter    = true;     // Enable HIGH VOL block (turn off if too restrictive)

//================ TIME / NEWS GUARD ===============//
input group "=== Time & News Guard ==="
input bool     InpUseSessionTime     = true;     // Use trading hours
input int      InpStartHour          = 8;        // Start hour (server time)
input int      InpEndHour            = 21;       // End hour
input bool     InpAvoidFridayLate    = true;     // No trade Fri after 19:00
input bool     InpAvoidMondayOpen    = true;     // No trade Mon before 09:00
input string   InpNewsTimes          = "13:30,15:00,18:00"; // High impact news HH:MM CSV (server time)
input int      InpNewsBlockMinutes   = 30;       // Block X min before/after news

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

//--- Globals
int      bb_handle, rsi_handle, atr_handle;
double   bb_upper[], bb_lower[], rsi_buffer[], atr_buffer[];

datetime last_bar_time = 0;
int      last_deals_total = 0;
double   cached_daily_profit = 0.0;
int      cached_daily_trades = 0;
int      cached_consec_losses = 0;
int      current_day = -1;

datetime news_times_today[];
double   pip_size;   // 0.01 for XAUUSD with 2-digit, 0.1 for 1-digit, set as 10*_Point

//+------------------------------------------------------------------+
//| Pip helper (XAUUSD friendly: 1 pip = 0.10 price = 10 points)     |
//+------------------------------------------------------------------+
double PipsToPrice(double pips) { return pips * _Point * 10.0; }
double PriceToPips(double price){ return price / (_Point * 10.0); }

//+------------------------------------------------------------------+
//| Dashboard Drawing                                                |
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
   DrawRect("UI_Outer",20,30,310,300,CLR_BG_OUTER);
   DrawRect("UI_Inner",22,32,306,296,CLR_BG_INNER);
   DrawRect("UI_Header",22,32,306,40,CLR_HEADER);
   DrawText("UI_Title",45,40,"ANTU GOLDMIND PRO V6 SAFE",11,C'15,15,15',"Segoe UI Black",true);

   DrawRect("UI_Line1",40,105,270,1,CLR_LINE);
   DrawRect("UI_Line2",40,155,270,1,CLR_LINE);
   DrawRect("UI_Line3",40,225,270,1,CLR_LINE);

   color stC = CLR_PROFIT;
   if(status=="TARGET HIT" || status=="LOSS HIT" || status=="MAX LOSSES") stC = CLR_LOSS;
   else if(status=="NEWS BLOCK" || status=="HIGH SPREAD" || status=="LOW VOL" || status=="HIGH VOL") stC = CLR_WARN;
   else if(status!="ACTIVE") stC = CLR_TXT_MUTED;

   DrawText("L_Status",40,80,"SYSTEM STATUS",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Status",180,78,status,9,stC,"Segoe UI Black",true);

   DrawText("L_Net",40,120,"TODAY P/L",8,CLR_TXT_MUTED,"Segoe UI",true);
   DrawText("V_Net",180,115,"$"+DoubleToString(pnl,2),14, pnl>=0?CLR_PROFIT:CLR_LOSS,"Consolas",true);

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

   DrawText("UI_Footer",95,295,"DEVELOPED BY KIRAN GROUP",7,CLR_BG_OUTER,"Segoe UI",true);
}

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit(){
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();

   bb_handle  = iBands(_Symbol,PERIOD_CURRENT,20,0,2.0,PRICE_CLOSE);
   rsi_handle = iRSI(_Symbol,PERIOD_CURRENT,14,PRICE_CLOSE);
   atr_handle = iATR(_Symbol,PERIOD_CURRENT,14);

   if(bb_handle==INVALID_HANDLE || rsi_handle==INVALID_HANDLE || atr_handle==INVALID_HANDLE)
      return(INIT_FAILED);

   ArraySetAsSeries(bb_upper,true);
   ArraySetAsSeries(bb_lower,true);
   ArraySetAsSeries(rsi_buffer,true);
   ArraySetAsSeries(atr_buffer,true);

   ParseNewsTimes();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   ObjectsDeleteAll(0,"UI_");
   ObjectsDeleteAll(0,"L_");
   ObjectsDeleteAll(0,"V_");
   IndicatorRelease(bb_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Parse "13:30,15:00,18:00" -> datetime[] for today               |
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
      if(MathAbs((long)nowT - (long)news_times_today[i]) <= blockSec) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Daily stats: profit, trade count, consecutive losses             |
//+------------------------------------------------------------------+
void RefreshDailyStats(){
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.day != current_day){
      current_day = dt.day;
      cached_daily_profit = 0.0;
      cached_daily_trades = 0;
      cached_consec_losses = 0;
      last_deals_total = 0;
      ParseNewsTimes(); // refresh news for new day
   }

   datetime startOfDay = TimeCurrent() - (TimeCurrent() % 86400);
   HistorySelect(startOfDay, TimeCurrent());
   int deals = HistoryDealsTotal();
   if(deals == last_deals_total) return;

   double profit = 0.0;
   int trades = 0;
   int consec = 0;
   for(int i=0;i<deals;i++){
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk,DEAL_MAGIC) != InpMagicNumber) continue;
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
//| Time filter                                                      |
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
//| Lot calculator (% risk based)                                    |
//+------------------------------------------------------------------+
double CalcLot(double slPips){
   if(!InpUseRiskPercent) return NormalizeLot(InpFixedLotSize);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskUsd = balance * InpRiskPercent / 100.0;

   double tickVal  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0 || tickSize<=0) return NormalizeLot(InpFixedLotSize);

   double slPrice = PipsToPrice(slPips);
   double lossPerLot = (slPrice / tickSize) * tickVal;
   if(lossPerLot<=0) return NormalizeLot(InpFixedLotSize);

   double lot = riskUsd / lossPerLot;
   return NormalizeLot(lot);
}

double NormalizeLot(double lot){
   double minLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step = 0.01;
   lot = MathFloor(lot/step)*step;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   lot = MathMin(lot, InpMaxLotCap);
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
//| Trailing stop / Breakeven                                        |
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
      double bid  = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double newSL = sl;

      if(type==POSITION_TYPE_BUY){
         double profitPips = PriceToPips(bid - open);

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
         if(newSL > sl + _Point){
            trade.PositionModify(ticket,NormalizeDouble(newSL,_Digits),tp);
         }
      }
      else if(type==POSITION_TYPE_SELL){
         double profitPips = PriceToPips(open - ask);

         if(InpUseBreakeven && profitPips >= InpBEActivatePips){
            double be = open - PipsToPrice(InpBEOffsetPips);
            if(sl==0 || sl > be) newSL = be;
         }
         if(InpUseTrailing && profitPips >= InpTrailStartPips){
            double trail = ask + PipsToPrice(InpTrailStepPips);
            if(newSL==0 || trail < newSL) newSL = trail;
         }
         if(newSL!=sl && (sl==0 || newSL < sl - _Point)){
            trade.PositionModify(ticket,NormalizeDouble(newSL,_Digits),tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick(){
   RefreshDailyStats();
   ManageOpenPositions();

   int spread = (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(CopyBuffer(bb_handle,1,0,3,bb_upper)<=0) return;
   if(CopyBuffer(bb_handle,2,0,3,bb_lower)<=0) return;
   if(CopyBuffer(atr_handle,0,0,3,atr_buffer)<=0) return;

   double bandPips = PriceToPips(bb_upper[0]-bb_lower[0]);
   double atrPips  = PriceToPips(atr_buffer[0]);

   //-------- Status logic
   string status = "ACTIVE";
   bool blocked = false;

   // Calculate effective target/loss limits
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double targetUSD, maxLossUSD;
   if(InpUsePercentGuard){
      targetUSD  = balance * InpDailyTargetPct  / 100.0;
      maxLossUSD = balance * InpDailyMaxLossPct / 100.0;
   } else {
      targetUSD  = InpDailyTargetUSD;
      maxLossUSD = InpDailyMaxLossUSD;
   }

   if(targetUSD > 0 && cached_daily_profit >= targetUSD){ status="TARGET HIT"; blocked=true; }
   else if(maxLossUSD > 0 && cached_daily_profit <= -maxLossUSD){ status="LOSS HIT"; blocked=true; }
   else if(InpMaxConsecutiveLoss > 0 && cached_consec_losses >= InpMaxConsecutiveLoss){ status="MAX LOSSES"; blocked=true; }
   else if(InpMaxTradesPerDay > 0 && cached_daily_trades >= InpMaxTradesPerDay){ status="MAX TRADES"; blocked=true; }
   else if(!IsTradingTime()){ status="SLEEPING"; blocked=true; }
   else if(IsNewsBlock()){ status="NEWS BLOCK"; blocked=true; }
   else if(spread > InpMaxSpread){ status="HIGH SPREAD"; blocked=true; }
   else if(bandPips < InpMinBandDistancePips){ status="LOW VOL"; blocked=true; }
   else if(atrPips < InpMinATRPips){ status="LOW VOL"; blocked=true; }
   else if(InpUseATRMaxFilter && atrPips > InpMaxATRPips){ status="HIGH VOL"; blocked=true; }

   UpdateDashboard(cached_daily_profit, spread, bandPips, atrPips, status);

   if(blocked) return;
   if(PositionsTotal()>0) return; // one trade at a time

   // New bar only
   datetime ct = iTime(_Symbol,PERIOD_CURRENT,0);
   if(ct == last_bar_time) return;

   if(CopyBuffer(rsi_handle,0,1,3,rsi_buffer)<=0) return;
   last_bar_time = ct;

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double last_close = iClose(_Symbol,PERIOD_CURRENT,1);

   // Calculate SL/TP
   double slPips, tpPips;
   if(InpUseATRStops){
      slPips = atrPips * InpATRMultSL;
      tpPips = atrPips * InpATRMultTP;
      // Hard cap so news-late spikes can't over-extend SL
      slPips = MathMin(slPips, InpFixedSLPips * 1.5);
      tpPips = MathMax(tpPips, slPips * 1.1); // keep R:R >= 1.1
   } else {
      slPips = InpFixedSLPips;
      tpPips = InpFixedTPPips;
   }

   double lot = CalcLot(slPips);
   if(lot<=0) return;

   //-------- BUY
   if(last_close <= bb_lower[1] && rsi_buffer[0] < 35.0){
      double sl = ask - PipsToPrice(slPips);
      double tp = ask + PipsToPrice(tpPips);
      if(!trade.Buy(lot,_Symbol,ask,
                    NormalizeDouble(sl,_Digits),
                    NormalizeDouble(tp,_Digits),
                    InpComment))
         PrintFormat("Buy failed: %d %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return;
   }

   //-------- SELL
   if(last_close >= bb_upper[1] && rsi_buffer[0] > 65.0){
      double sl = bid + PipsToPrice(slPips);
      double tp = bid - PipsToPrice(tpPips);
      if(!trade.Sell(lot,_Symbol,bid,
                     NormalizeDouble(sl,_Digits),
                     NormalizeDouble(tp,_Digits),
                     InpComment))
         PrintFormat("Sell failed: %d %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return;
   }
}
//+------------------------------------------------------------------+
