//+------------------------------------------------------------------+
//|                                            PE_RangeDetector.mqh  |
//|                          ANTU PROFIT ENGINE v01 - Range Detector |
//|                                                                  |
//|  Purpose: Asian session ka High/Low calculate karta hai          |
//|           aur check karta hai market range me hai ya nahi        |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property strict

//--- Range Data structure
struct RangeData
{
   double   high;          // Range ka upper boundary
   double   low;           // Range ka lower boundary
   double   middle;        // Range ka middle (mean)
   double   sizePips;      // Range size in pips
   datetime startTime;     // Range start time
   datetime endTime;       // Range end time
   bool     isValid;       // Range valid hai ya nahi
};

//+------------------------------------------------------------------+
//| Range Detector Class                                             |
//+------------------------------------------------------------------+
class CRangeDetector
{
private:
   string   m_symbol;
   int      m_asianStartHour;    // Asian session start (server time)
   int      m_asianEndHour;      // Asian session end
   double   m_minRangePips;      // Minimum acceptable range
   double   m_maxRangePips;      // Maximum acceptable range
   double   m_pipValue;          // Pip value for symbol

public:
   RangeData currentRange;

   //--- Constructor
   CRangeDetector(string symbol, int asianStart, int asianEnd, 
                  double minPips, double maxPips)
   {
      m_symbol = symbol;
      m_asianStartHour = asianStart;
      m_asianEndHour = asianEnd;
      m_minRangePips = minPips;
      m_maxRangePips = maxPips;
      
      // XAUUSD ke liye 1 pip = 0.10 (10 points)
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_pipValue = (digits == 3 || digits == 5) ? 
                   SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10 : 
                   SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      
      // For XAUUSD specifically: 1 pip = 0.1
      if(StringFind(m_symbol, "XAU") >= 0 || StringFind(m_symbol, "GOLD") >= 0)
         m_pipValue = 0.1;
      
      ZeroMemory(currentRange);
   }
   
   //--- Calculate Asian Session Range
   bool CalculateRange()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // Aaj ki date ke saath asian session ka start/end time banao
      dt.hour = m_asianStartHour;
      dt.min = 0;
      dt.sec = 0;
      datetime asianStart = StructToTime(dt);
      
      dt.hour = m_asianEndHour;
      datetime asianEnd = StructToTime(dt);
      
      // Agar abhi asian session khatam nahi hua, kal ka data use karo
      if(TimeCurrent() < asianEnd)
      {
         asianStart -= 86400;
         asianEnd -= 86400;
      }
      
      // M5 timeframe pe high/low nikalo
      int barsToCheck = (int)((asianEnd - asianStart) / 300); // 300 sec = M5
      if(barsToCheck < 1) barsToCheck = 84; // ~7 hours of M5
      
      double highArr[], lowArr[];
      ArraySetAsSeries(highArr, true);
      ArraySetAsSeries(lowArr, true);
      
      int copiedH = CopyHigh(m_symbol, PERIOD_M5, asianStart, asianEnd, highArr);
      int copiedL = CopyLow(m_symbol, PERIOD_M5, asianStart, asianEnd, lowArr);
      
      if(copiedH <= 0 || copiedL <= 0)
      {
         currentRange.isValid = false;
         return false;
      }
      
      double rHigh = highArr[ArrayMaximum(highArr)];
      double rLow  = lowArr[ArrayMinimum(lowArr)];
      double sizePips = (rHigh - rLow) / m_pipValue;
      
      currentRange.high      = rHigh;
      currentRange.low       = rLow;
      currentRange.middle    = (rHigh + rLow) / 2.0;
      currentRange.sizePips  = sizePips;
      currentRange.startTime = asianStart;
      currentRange.endTime   = asianEnd;
      
      // Validate: range size acceptable hai?
      currentRange.isValid = (sizePips >= m_minRangePips && 
                              sizePips <= m_maxRangePips);
      
      return currentRange.isValid;
   }
   
   //--- Check if price is near upper boundary (sell zone)
   bool IsNearHigh(double price, double bufferPips = 3.0)
   {
      if(!currentRange.isValid) return false;
      double buffer = bufferPips * m_pipValue;
      return (price >= currentRange.high - buffer);
   }
   
   //--- Check if price is near lower boundary (buy zone)
   bool IsNearLow(double price, double bufferPips = 3.0)
   {
      if(!currentRange.isValid) return false;
      double buffer = bufferPips * m_pipValue;
      return (price <= currentRange.low + buffer);
   }
   
   //--- Get pip value for symbol
   double PipValue() { return m_pipValue; }
};
//+------------------------------------------------------------------+
