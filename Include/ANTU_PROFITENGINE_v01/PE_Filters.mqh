//+------------------------------------------------------------------+
//|                                                  PE_Filters.mqh  |
//|                          ANTU PROFIT ENGINE v01 - Safety Filters |
//|                                                                  |
//|  Purpose: ADX, ATR, RSI, Spread, Session - sab filters check     |
//|           Safe trading ke liye crucial hai                       |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property strict

//+------------------------------------------------------------------+
//| Safety Filters Class                                             |
//+------------------------------------------------------------------+
class CFilters
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_tf;
   
   int      m_handleADX;
   int      m_handleATR;
   int      m_handleRSI;
   
   double   m_maxADX;        // Above this = trending market = skip
   double   m_maxATR;        // Above this = high volatility = skip
   int      m_maxSpread;     // Maximum allowed spread (points)
   
   int      m_sessionStart;  // Trading session start hour
   int      m_sessionEnd;    // Trading session end hour

public:
   //--- Constructor
   CFilters(string symbol, ENUM_TIMEFRAMES tf, double maxADX, 
            double maxATR, int maxSpread, int sessStart, int sessEnd)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_maxADX = maxADX;
      m_maxATR = maxATR;
      m_maxSpread = maxSpread;
      m_sessionStart = sessStart;
      m_sessionEnd = sessEnd;
      
      m_handleADX = iADX(m_symbol, m_tf, 14);
      m_handleATR = iATR(m_symbol, m_tf, 14);
      m_handleRSI = iRSI(m_symbol, m_tf, 14, PRICE_CLOSE);
   }
   
   //--- Destructor
   ~CFilters()
   {
      if(m_handleADX != INVALID_HANDLE) IndicatorRelease(m_handleADX);
      if(m_handleATR != INVALID_HANDLE) IndicatorRelease(m_handleATR);
      if(m_handleRSI != INVALID_HANDLE) IndicatorRelease(m_handleRSI);
   }
   
   //--- Get current ADX
   double GetADX()
   {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(m_handleADX, 0, 0, 2, adx) <= 0) return -1;
      return adx[0];
   }
   
   //--- Get current ATR
   double GetATR()
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_handleATR, 0, 0, 2, atr) <= 0) return -1;
      return atr[0];
   }
   
   //--- Get current RSI
   double GetRSI()
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(m_handleRSI, 0, 0, 2, rsi) <= 0) return -1;
      return rsi[0];
   }
   
   //--- Get current spread in points
   int GetSpread()
   {
      return (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   }
   
   //--- ADX Filter: trend nahi hona chahiye
   bool ADXOk()
   {
      double adx = GetADX();
      if(adx < 0) return false;
      return (adx < m_maxADX);
   }
   
   //--- ATR Filter: volatility low honi chahiye
   bool ATROk()
   {
      double atr = GetATR();
      if(atr < 0) return false;
      return (atr < m_maxATR);
   }
   
   //--- Spread Filter: spread acceptable hona chahiye
   bool SpreadOk()
   {
      return (GetSpread() <= m_maxSpread);
   }
   
   //--- Session Filter: trading time hona chahiye
   bool SessionOk()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      
      // Day of week: 0=Sunday, 6=Saturday - skip weekend
      if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
      
      // Friday afternoon avoid karo (volatility)
      if(dt.day_of_week == 5 && hour >= 18) return false;
      
      // Monday morning thoda late start
      if(dt.day_of_week == 1 && hour < m_sessionStart) return false;
      
      // Session window check
      if(m_sessionStart <= m_sessionEnd)
         return (hour >= m_sessionStart && hour < m_sessionEnd);
      else
         // Cross-midnight session
         return (hour >= m_sessionStart || hour < m_sessionEnd);
   }
   
   //--- Master Check: sab filters pass?
   bool AllFiltersOk()
   {
      return ADXOk() && ATROk() && SpreadOk() && SessionOk();
   }
   
   //--- Get filter status string for dashboard
   string GetFilterStatus()
   {
      string s = "";
      s += "ADX: "    + DoubleToString(GetADX(), 1) + (ADXOk() ? " [OK]" : " [HIGH-Trend]") + "\n";
      s += "ATR: "    + DoubleToString(GetATR(), 2) + (ATROk() ? " [OK]" : " [HIGH-Vol]")  + "\n";
      s += "RSI: "    + DoubleToString(GetRSI(), 1) + "\n";
      s += "Spread: " + IntegerToString(GetSpread()) + (SpreadOk() ? " [OK]" : " [HIGH]") + "\n";
      s += "Session: " + (SessionOk() ? "[OPEN]" : "[CLOSED]");
      return s;
   }
};
//+------------------------------------------------------------------+
