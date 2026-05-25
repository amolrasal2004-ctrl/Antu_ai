//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|        XAU Range Scalper Pro - lot sizing & daily loss guard     |
//+------------------------------------------------------------------+
#ifndef __XRSP_RISK_MANAGER_MQH__
#define __XRSP_RISK_MANAGER_MQH__

//+------------------------------------------------------------------+
//| CRiskManager                                                     |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   string   m_symbol;
   double   m_riskPercent;
   double   m_maxDailyLossPercent;
   double   m_dayStartEquity;
   datetime m_dayStartTime;

public:
   void Init(const string symbol,
             const double riskPercent,
             const double maxDailyLossPercent)
   {
      m_symbol              = symbol;
      m_riskPercent         = riskPercent;
      m_maxDailyLossPercent = maxDailyLossPercent;
      m_dayStartEquity      = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartTime        = StartOfDay(TimeCurrent());
   }

   //--- call on each tick; resets daily anchor at new day
   void OnTick()
   {
      datetime today = StartOfDay(TimeCurrent());
      if(today != m_dayStartTime)
      {
         m_dayStartTime   = today;
         m_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      }
   }

   double DayStartEquity() const { return m_dayStartEquity; }

   double DayPnL() const
   {
      return AccountInfoDouble(ACCOUNT_EQUITY) - m_dayStartEquity;
   }

   double DayPnLPercent() const
   {
      if(m_dayStartEquity <= 0) return 0.0;
      return (DayPnL() / m_dayStartEquity) * 100.0;
   }

   bool DailyLossHit() const
   {
      if(m_maxDailyLossPercent <= 0) return false;
      return DayPnLPercent() <= -m_maxDailyLossPercent;
   }

   //--- compute lot size from risk % and SL distance in price
   double CalcLotByRisk(const double slDistancePrice) const
   {
      if(slDistancePrice <= 0) return 0.0;

      double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney   = balance * (m_riskPercent / 100.0);

      double tickSize    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0 || tickValue <= 0) return 0.0;

      // money lost per 1 lot if price moves slDistancePrice
      double lossPerLot  = (slDistancePrice / tickSize) * tickValue;
      if(lossPerLot <= 0) return 0.0;

      double lots = riskMoney / lossPerLot;
      return NormalizeLot(lots);
   }

   double NormalizeLot(double lots) const
   {
      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(stepLot <= 0) stepLot = 0.01;

      lots = MathMax(minLot, MathMin(maxLot, lots));
      lots = MathFloor(lots / stepLot) * stepLot;
      // round to 2 decimals to be safe
      return NormalizeDouble(lots, 2);
   }

private:
   datetime StartOfDay(const datetime t) const
   {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }
};

#endif // __XRSP_RISK_MANAGER_MQH__
