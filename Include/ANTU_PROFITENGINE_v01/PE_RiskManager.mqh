//+------------------------------------------------------------------+
//|                                              PE_RiskManager.mqh  |
//|                       ANTU PROFIT ENGINE v01 - Risk + Emergency  |
//|                                                                  |
//|  Purpose: Lot calc, daily limits, emergency lock                 |
//|           Account ko safe rakhna - sabse important               |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property strict

//--- Lock reasons
enum ENUM_LOCK_REASON
{
   LOCK_NONE             = 0,
   LOCK_DAILY_LOSS       = 1,
   LOCK_DAILY_PROFIT     = 2,
   LOCK_CONSEC_LOSSES    = 3,
   LOCK_DRAWDOWN         = 4,
   LOCK_TRADE_LIMIT      = 5,
   LOCK_MANUAL           = 6
};

//+------------------------------------------------------------------+
//| Risk Manager Class                                               |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   double   m_dailyProfitTarget;     // $20 per day
   double   m_dailyLossLimit;        // $10 per day max loss
   double   m_riskPercent;           // 1% per trade
   int      m_maxTradesPerDay;       // 3-4 trades max
   int      m_maxConsecLosses;       // 3 consec = pause
   double   m_maxDrawdownPct;        // 5% account drawdown
   
   datetime m_dayStart;              // Today's start time
   double   m_dayStartBalance;       // Balance at day start
   double   m_dailyPnL;              // Running daily P&L
   int      m_tradesToday;           // Trades count today
   int      m_consecLosses;          // Consecutive losses
   datetime m_pauseUntil;            // Paused until this time
   
   bool     m_locked;                // Currently locked
   ENUM_LOCK_REASON m_lockReason;    // Why locked

public:
   //--- Constructor
   CRiskManager(double dailyProfit, double dailyLoss, double riskPct,
                int maxTrades, int maxConsecL, double maxDDPct)
   {
      m_dailyProfitTarget = dailyProfit;
      m_dailyLossLimit    = dailyLoss;
      m_riskPercent       = riskPct;
      m_maxTradesPerDay   = maxTrades;
      m_maxConsecLosses   = maxConsecL;
      m_maxDrawdownPct    = maxDDPct;
      
      ResetDay();
   }
   
   //--- Reset daily counters (call at new day)
   void ResetDay()
   {
      m_dayStart        = TimeCurrent();
      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_dailyPnL        = 0.0;
      m_tradesToday     = 0;
      m_consecLosses    = 0;
      m_pauseUntil      = 0;
      m_locked          = false;
      m_lockReason      = LOCK_NONE;
   }
   
   //--- Check if new day started, reset if needed
   void CheckNewDay()
   {
      MqlDateTime dtNow, dtStart;
      TimeToStruct(TimeCurrent(), dtNow);
      TimeToStruct(m_dayStart, dtStart);
      
      if(dtNow.day != dtStart.day || dtNow.mon != dtStart.mon)
      {
         ResetDay();
         Print(">>> ANTU: New day started - counters reset");
      }
   }
   
   //--- Calculate lot size based on SL distance and risk %
   double CalculateLot(string symbol, double slPips, double pipValue)
   {
      double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount  = balance * (m_riskPercent / 100.0);
      
      // Tick value for symbol (1 lot, 1 point)
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      // Convert SL pips to money loss for 1 lot
      double slPoints  = slPips * (pipValue / point);
      double lossPerLot = slPoints * tickValue * (point / tickSize);
      
      if(lossPerLot <= 0) return 0.01;
      
      double lot = riskAmount / lossPerLot;
      
      // Round to symbol's lot step
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      
      lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMax(lot, minLot);
      lot = MathMin(lot, maxLot);
      
      // Safety cap for $300 account: max 0.05 lots
      double balanceCap = balance * 0.0002; // 0.02 lot per $100
      lot = MathMin(lot, balanceCap);
      lot = MathMax(lot, minLot);
      
      return NormalizeDouble(lot, 2);
   }
   
   //--- Update P&L from closed trade
   void OnTradeClosed(double profit)
   {
      m_dailyPnL += profit;
      m_tradesToday++;
      
      if(profit < 0)
         m_consecLosses++;
      else if(profit > 0)
         m_consecLosses = 0;
      
      // Consecutive loss pause: 2 hour pause
      if(m_consecLosses >= m_maxConsecLosses)
      {
         m_pauseUntil = TimeCurrent() + 7200; // 2 hours
         Print(">>> ANTU: ", m_consecLosses, " losses in row - paused 2hrs");
      }
   }
   
   //--- Master check: can we trade now?
   bool CanTrade()
   {
      CheckNewDay();
      
      // Already manually locked
      if(m_locked) return false;
      
      // Daily profit target hit - lock for the day
      if(m_dailyPnL >= m_dailyProfitTarget)
      {
         m_locked = true;
         m_lockReason = LOCK_DAILY_PROFIT;
         return false;
      }
      
      // Daily loss limit hit - emergency stop
      if(m_dailyPnL <= -m_dailyLossLimit)
      {
         m_locked = true;
         m_lockReason = LOCK_DAILY_LOSS;
         return false;
      }
      
      // Max trades per day
      if(m_tradesToday >= m_maxTradesPerDay)
      {
         m_locked = true;
         m_lockReason = LOCK_TRADE_LIMIT;
         return false;
      }
      
      // Drawdown check
      double currBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double ddPct = (m_dayStartBalance - currBalance) / m_dayStartBalance * 100.0;
      if(ddPct >= m_maxDrawdownPct)
      {
         m_locked = true;
         m_lockReason = LOCK_DRAWDOWN;
         return false;
      }
      
      // Pause active?
      if(TimeCurrent() < m_pauseUntil) return false;
      
      return true;
   }
   
   //--- Manual lock/unlock
   void SetManualLock(bool lock)
   {
      m_locked = lock;
      m_lockReason = lock ? LOCK_MANUAL : LOCK_NONE;
   }
   
   //--- Getters for dashboard
   double   DailyPnL()         { return m_dailyPnL; }
   double   DailyTarget()      { return m_dailyProfitTarget; }
   double   DailyLossLimit()   { return m_dailyLossLimit; }
   int      TradesToday()      { return m_tradesToday; }
   int      MaxTrades()        { return m_maxTradesPerDay; }
   int      ConsecLosses()     { return m_consecLosses; }
   bool     IsLocked()         { return m_locked; }
   datetime PausedUntil()      { return m_pauseUntil; }
   
   string LockReasonText()
   {
      switch(m_lockReason)
      {
         case LOCK_DAILY_LOSS:    return "Daily Loss Hit";
         case LOCK_DAILY_PROFIT:  return "Profit Target Hit";
         case LOCK_CONSEC_LOSSES: return "Consec Losses";
         case LOCK_DRAWDOWN:      return "Drawdown Limit";
         case LOCK_TRADE_LIMIT:   return "Max Trades";
         case LOCK_MANUAL:        return "Manual Lock";
         default:                 return "None";
      }
   }
};
//+------------------------------------------------------------------+
