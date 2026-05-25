//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|       XAU Range Scalper Pro - Candlestick + RSI signal logic     |
//+------------------------------------------------------------------+
#ifndef __XRSP_SIGNAL_ENGINE_MQH__
#define __XRSP_SIGNAL_ENGINE_MQH__

#include "RangeDetector.mqh"

enum ENUM_SIGNAL
{
   SIG_NONE = 0,
   SIG_BUY  = 1,
   SIG_SELL = 2
};

//+------------------------------------------------------------------+
//| CSignalEngine                                                    |
//|   Reads only CLOSED bars (shift>=1) -> no repainting              |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_rsiPeriod;
   double            m_rsiBuyMax;     // RSI must be <= this for BUY (e.g., 35)
   double            m_rsiSellMin;    // RSI must be >= this for SELL (e.g., 65)
   bool              m_useBollinger;
   int               m_bbPeriod;
   double            m_bbDeviation;

   int               m_rsiHandle;
   int               m_bbHandle;

public:
   CSignalEngine() : m_rsiHandle(INVALID_HANDLE), m_bbHandle(INVALID_HANDLE) {}

   bool Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const int rsiPeriod,
             const double rsiBuyMax,
             const double rsiSellMin,
             const bool useBollinger,
             const int bbPeriod,
             const double bbDeviation)
   {
      m_symbol       = symbol;
      m_tf           = tf;
      m_rsiPeriod    = rsiPeriod;
      m_rsiBuyMax    = rsiBuyMax;
      m_rsiSellMin   = rsiSellMin;
      m_useBollinger = useBollinger;
      m_bbPeriod     = bbPeriod;
      m_bbDeviation  = bbDeviation;

      m_rsiHandle = iRSI(m_symbol, m_tf, m_rsiPeriod, PRICE_CLOSE);
      if(m_rsiHandle == INVALID_HANDLE)
      {
         Print("SignalEngine: RSI handle failed, err=", GetLastError());
         return false;
      }
      if(m_useBollinger)
      {
         m_bbHandle = iBands(m_symbol, m_tf, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
         if(m_bbHandle == INVALID_HANDLE)
         {
            Print("SignalEngine: BB handle failed, err=", GetLastError());
            return false;
         }
      }
      return true;
   }

   void Deinit()
   {
      if(m_rsiHandle != INVALID_HANDLE) IndicatorRelease(m_rsiHandle);
      if(m_bbHandle  != INVALID_HANDLE) IndicatorRelease(m_bbHandle);
      m_rsiHandle = INVALID_HANDLE;
      m_bbHandle  = INVALID_HANDLE;
   }

   //--- main signal evaluator (uses last CLOSED candle for pattern + RSI)
   ENUM_SIGNAL Evaluate(const CRangeDetector &range, double &outRsi)
   {
      outRsi = 0.0;
      const SRange r = range.Range();
      if(!r.valid) return SIG_NONE;

      // last 2 closed candles
      double o[], h[], l[], c[];
      ArraySetAsSeries(o, true);
      ArraySetAsSeries(h, true);
      ArraySetAsSeries(l, true);
      ArraySetAsSeries(c, true);
      if(CopyOpen(m_symbol, m_tf, 1, 2, o)  <= 0) return SIG_NONE;
      if(CopyHigh(m_symbol, m_tf, 1, 2, h)  <= 0) return SIG_NONE;
      if(CopyLow(m_symbol, m_tf, 1, 2, l)   <= 0) return SIG_NONE;
      if(CopyClose(m_symbol, m_tf, 1, 2, c) <= 0) return SIG_NONE;

      // index 0 = most recent closed bar, 1 = prior
      double rsiBuf[];
      ArraySetAsSeries(rsiBuf, true);
      if(CopyBuffer(m_rsiHandle, 0, 1, 1, rsiBuf) <= 0) return SIG_NONE;
      double rsi = rsiBuf[0];
      outRsi = rsi;

      // optional Bollinger filter: BUY when price below lower band, SELL above upper
      double bbLower = 0.0, bbUpper = 0.0;
      if(m_useBollinger)
      {
         double up[], lo[];
         ArraySetAsSeries(up, true);
         ArraySetAsSeries(lo, true);
         if(CopyBuffer(m_bbHandle, 1, 1, 1, up) <= 0) return SIG_NONE; // upper
         if(CopyBuffer(m_bbHandle, 2, 1, 1, lo) <= 0) return SIG_NONE; // lower
         bbUpper = up[0];
         bbLower = lo[0];
      }

      bool nearSupport    = range.NearSupport(l[0]);
      bool nearResistance = range.NearResistance(h[0]);

      // BUY: bullish rejection at support
      if(nearSupport)
      {
         bool bullishEngulf = (c[1] < o[1]) && (c[0] > o[0]) &&
                              (c[0] >= o[1]) && (o[0] <= c[1]);
         bool bullPin       = IsBullishPin(o[0], h[0], l[0], c[0]);
         bool patternOK     = bullishEngulf || bullPin;
         bool rsiOK         = (rsi <= m_rsiBuyMax);
         bool bbOK          = (!m_useBollinger) || (l[0] <= bbLower);

         if(patternOK && rsiOK && bbOK) return SIG_BUY;
      }

      // SELL: bearish rejection at resistance
      if(nearResistance)
      {
         bool bearishEngulf = (c[1] > o[1]) && (c[0] < o[0]) &&
                              (c[0] <= o[1]) && (o[0] >= c[1]);
         bool shootingStar  = IsShootingStar(o[0], h[0], l[0], c[0]);
         bool patternOK     = bearishEngulf || shootingStar;
         bool rsiOK         = (rsi >= m_rsiSellMin);
         bool bbOK          = (!m_useBollinger) || (h[0] >= bbUpper);

         if(patternOK && rsiOK && bbOK) return SIG_SELL;
      }

      return SIG_NONE;
   }

private:
   //--- bullish pin bar: long lower wick, small body, body in upper third
   bool IsBullishPin(double op, double hi, double lo, double cl) const
   {
      double range = hi - lo;
      if(range <= 0) return false;
      double body  = MathAbs(cl - op);
      double lower = MathMin(op, cl) - lo;
      double upper = hi - MathMax(op, cl);
      return (lower >= 2.0 * body) && (upper <= 0.5 * body) && (cl > op || body < range * 0.3);
   }

   //--- shooting star: long upper wick, small body, body in lower third
   bool IsShootingStar(double op, double hi, double lo, double cl) const
   {
      double range = hi - lo;
      if(range <= 0) return false;
      double body  = MathAbs(cl - op);
      double upper = hi - MathMax(op, cl);
      double lower = MathMin(op, cl) - lo;
      return (upper >= 2.0 * body) && (lower <= 0.5 * body) && (cl < op || body < range * 0.3);
   }
};

#endif // __XRSP_SIGNAL_ENGINE_MQH__
