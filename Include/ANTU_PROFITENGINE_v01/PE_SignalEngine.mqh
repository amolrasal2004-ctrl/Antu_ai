//+------------------------------------------------------------------+
//|                                              PE_SignalEngine.mqh |
//|                         ANTU PROFIT ENGINE v01 - Signal Generator|
//|                                                                  |
//|  Purpose: Range boundaries pe BUY/SELL signal generate karna     |
//|           RSI + Candle confirmation ke saath                     |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property strict

#include "PE_RangeDetector.mqh"
#include "PE_Filters.mqh"

//--- Signal types
enum ENUM_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
};

//+------------------------------------------------------------------+
//| Signal Engine Class                                              |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   string         m_symbol;
   ENUM_TIMEFRAMES m_tf;
   double         m_rsiOversold;
   double         m_rsiOverbought;

public:
   //--- Constructor
   CSignalEngine(string symbol, ENUM_TIMEFRAMES tf, 
                 double rsiOS = 30.0, double rsiOB = 70.0)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_rsiOversold = rsiOS;
      m_rsiOverbought = rsiOB;
   }
   
   //--- Get last closed candle data
   bool GetCandle(int shift, double &op, double &cl, double &hi, double &lo)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_tf, shift, 1, rates) <= 0) return false;
      op = rates[0].open;
      cl = rates[0].close;
      hi = rates[0].high;
      lo = rates[0].low;
      return true;
   }
   
   //--- Bullish candle confirmation
   bool IsBullishCandle()
   {
      double op, cl, hi, lo;
      if(!GetCandle(1, op, cl, hi, lo)) return false;
      // Close > Open AND body > 30% of full range
      double body  = MathAbs(cl - op);
      double range = hi - lo;
      if(range == 0) return false;
      return (cl > op && body / range > 0.3);
   }
   
   //--- Bearish candle confirmation
   bool IsBearishCandle()
   {
      double op, cl, hi, lo;
      if(!GetCandle(1, op, cl, hi, lo)) return false;
      double body  = MathAbs(cl - op);
      double range = hi - lo;
      if(range == 0) return false;
      return (cl < op && body / range > 0.3);
   }
   
   //--- Main Signal Check
   ENUM_SIGNAL CheckSignal(CRangeDetector *rangeDet, CFilters *filters)
   {
      // 1. All filters must pass
      if(!filters.AllFiltersOk()) return SIGNAL_NONE;
      
      // 2. Range must be valid
      if(!rangeDet.currentRange.isValid) return SIGNAL_NONE;
      
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double rsi = filters.GetRSI();
      
      //--- BUY signal: price near range low + RSI oversold + bullish candle
      if(rangeDet.IsNearLow(ask) && 
         rsi < m_rsiOversold && 
         IsBullishCandle())
      {
         return SIGNAL_BUY;
      }
      
      //--- SELL signal: price near range high + RSI overbought + bearish candle
      if(rangeDet.IsNearHigh(bid) && 
         rsi > m_rsiOverbought && 
         IsBearishCandle())
      {
         return SIGNAL_SELL;
      }
      
      return SIGNAL_NONE;
   }
};
//+------------------------------------------------------------------+
