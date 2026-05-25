//+------------------------------------------------------------------+
//|                                                      Filters.mqh |
//|                              XAU Range Scalper Pro - Filters     |
//|  Spread, session, news/volatility filters                        |
//+------------------------------------------------------------------+
#ifndef __XRSP_FILTERS_MQH__
#define __XRSP_FILTERS_MQH__

//+------------------------------------------------------------------+
//| CFilters - all pre-trade filters                                 |
//+------------------------------------------------------------------+
class CFilters
{
private:
   string   m_symbol;
   int      m_spreadLimitPoints;
   bool     m_useSessionFilter;
   int      m_sessionStartHour;     // server time
   int      m_sessionEndHour;       // server time
   bool     m_avoidLondonOpen;
   bool     m_avoidNYOpen;
   int      m_londonOpenHour;       // server time, default 10 (varies)
   int      m_nyOpenHour;           // server time, default 15 (varies)
   int      m_avoidMinutesAround;   // minutes around the opens to skip

public:
   void Init(const string symbol,
             const int    spreadLimitPoints,
             const bool   useSessionFilter,
             const int    sessionStartHour,
             const int    sessionEndHour,
             const bool   avoidLondonOpen,
             const bool   avoidNYOpen,
             const int    londonOpenHour,
             const int    nyOpenHour,
             const int    avoidMinutesAround)
   {
      m_symbol             = symbol;
      m_spreadLimitPoints  = spreadLimitPoints;
      m_useSessionFilter   = useSessionFilter;
      m_sessionStartHour   = sessionStartHour;
      m_sessionEndHour     = sessionEndHour;
      m_avoidLondonOpen    = avoidLondonOpen;
      m_avoidNYOpen        = avoidNYOpen;
      m_londonOpenHour     = londonOpenHour;
      m_nyOpenHour         = nyOpenHour;
      m_avoidMinutesAround = avoidMinutesAround;
   }

   //--- current spread in points
   int CurrentSpreadPoints() const
   {
      return (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   }

   //--- spread acceptable?
   bool SpreadOK(string &reason) const
   {
      int sp = CurrentSpreadPoints();
      if(sp > m_spreadLimitPoints)
      {
         reason = StringFormat("Spread too high: %d > %d", sp, m_spreadLimitPoints);
         return false;
      }
      return true;
   }

   //--- session ok?
   bool SessionOK(string &reason) const
   {
      if(!m_useSessionFilter) return true;

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      int m = dt.min;

      // session window
      if(m_sessionStartHour <= m_sessionEndHour)
      {
         if(h < m_sessionStartHour || h >= m_sessionEndHour)
         {
            reason = StringFormat("Outside session window %02d-%02d (now %02d:%02d)",
                                  m_sessionStartHour, m_sessionEndHour, h, m);
            return false;
         }
      }
      else
      {
         // wraps midnight
         if(h < m_sessionStartHour && h >= m_sessionEndHour)
         {
            reason = StringFormat("Outside session window %02d-%02d (now %02d:%02d)",
                                  m_sessionStartHour, m_sessionEndHour, h, m);
            return false;
         }
      }

      // avoid London open volatility
      if(m_avoidLondonOpen && IsAroundHour(h, m, m_londonOpenHour))
      {
         reason = StringFormat("Around London open (%02d:00 +/- %dm)",
                               m_londonOpenHour, m_avoidMinutesAround);
         return false;
      }

      // avoid NY open volatility
      if(m_avoidNYOpen && IsAroundHour(h, m, m_nyOpenHour))
      {
         reason = StringFormat("Around NY open (%02d:00 +/- %dm)",
                               m_nyOpenHour, m_avoidMinutesAround);
         return false;
      }

      return true;
   }

   //--- combined check
   bool AllOK(string &reason) const
   {
      if(!SpreadOK(reason))  return false;
      if(!SessionOK(reason)) return false;
      return true;
   }

private:
   bool IsAroundHour(int curH, int curM, int targetH) const
   {
      int curMinutes    = curH * 60 + curM;
      int targetMinutes = targetH * 60;
      int diff          = MathAbs(curMinutes - targetMinutes);
      // handle midnight wrap roughly
      diff = MathMin(diff, 24 * 60 - diff);
      return diff <= m_avoidMinutesAround;
   }
};

#endif // __XRSP_FILTERS_MQH__
