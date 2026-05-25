//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|       XAU Range Scalper Pro - Candlestick + RSI signal logic     |
//|  v1.1 improvements:                                              |
//|   - Optional EMA-200 trend "non-strong" filter:                  |
//|     skip BUY if price is far below EMA200 (strong downtrend)     |
//|     skip SELL if price is far above EMA200 (strong uptrend)      |
//|   - Stronger pattern validation: minimum body/range ratios       |
//|   - RSI slope hint for stronger reversal confirmation            |
//+------------------------------------------------------------------+
#ifndef __XRSP_SIGNAL_ENGINE_MQH__
#define __XRSP_SIGNAL_ENGINE_MQH__

#include <XAURangeScalperPro/RangeDetector.mqh>

enum ENUM_SIGNAL
{
   SIG_NONE = 0,
   SIG_BUY  = 1,
   SIG_SELL = 2
};

//+------------------------------------------------------------------+
//| CSignalEngine                                                    |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_rsiPeriod;
   double            m_rsiBuyMax;
   double            m_rsiSellMin;
   bool              m_useBollinger;
   int               m_bbPeriod;
   double            m_bbDeviation;
   bool              m_useTrendFilter;
   int               m_emaPeriod;
   double            m_emaMaxDistAtr;   // skip if abs(price-EMA) > x * ATR

   int               m_rsiHandle;
   int               m_bbHandle;
   int               m_emaHandle;

public:
   CSignalEngine() : m_rsiHandle(INVALID_HANDLE),
                     m_bbHandle(INVALID_HANDLE),
                     m_emaHandle(INVALID_HANDLE) {}

   bool Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const int rsiPeriod,
             const double rsiBuyMax,
             const double rsiSellMin,
             const bool useBollinger,
             const int bbPeriod,
             const double bbDeviation,
             const bool useTrendFilter,
             const int emaPeriod,
             const double emaMaxDistAtr)
   {
      m_symbol         = symbol;
      m_tf             = tf;
      m_rsiPeriod      = rsiPeriod;
      m_rsiBuyMax      = rsiBuyMax;
      m_rsiSellMin     = rsiSellMin;
      m_useBollinger   = useBollinger;
      m_bbPeriod       = bbPeriod;
      m_bbDeviation    = bbDeviation;
      m_useTrendFilter = useTrendFilter;
      m_emaPeriod      = emaPeriod;
      m_emaMaxDistAtr  = emaMaxDistAtr;

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
      if(m_useTrendFilter)
      {
         m_emaHandle = iMA(m_symbol, m_tf, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
         if(m_emaHandle == INVALID_HANDLE)
         {
            Print("SignalEngine: EMA handle failed, err=", GetLastError());
            return false;
         }
      }
      return true;
   }

   void Deinit()
   {
      if(m_rsiHandle != INVALID_HANDLE) IndicatorRelease(m_rsiHandle);
      if(m_bbHandle  != INVALID_HANDLE) IndicatorRelease(m_bbHandle);
      if(m_emaHandle != INVALID_HANDLE) IndicatorRelease(m_emaHandle);
      m_rsiHandle = INVALID_HANDLE;
      m_bbHandle  = INVALID_HANDLE;
      m_emaHandle = INVALID_HANDLE;
   }

   //--- main signal evaluator (uses last CLOSED candle, no repaint)
   ENUM_SIGNAL Evaluate(const CRangeDetector &range, double &outRsi)
   {
      outRsi = 0.0;
      const SRange r = range.Range();
      if(!r.valid) return SIG_NONE;

      // last 3 closed candles (need extra for RSI slope)
      double o[], h[], l[], c[];
      ArraySetAsSeries(o, true);
      ArraySetAsSeries(h, true);
      ArraySetAsSeries(l, true);
      ArraySetAsSeries(c, true);
      if(CopyOpen(m_symbol, m_tf, 1, 3, o)  <= 0) return SIG_NONE;
      if(CopyHigh(m_symbol, m_tf, 1, 3, h)  <= 0) return SIG_NONE;
      if(CopyLow(m_symbol, m_tf, 1, 3, l)   <= 0) return SIG_NONE;
      if(CopyClose(m_symbol, m_tf, 1, 3, c) <= 0) return SIG_NONE;

      // RSI: get 2 values for slope check
      double rsiBuf[];
      ArraySetAsSeries(rsiBuf, true);
      if(CopyBuffer(m_rsiHandle, 0, 1, 2, rsiBuf) <= 0) return SIG_NONE;
      double rsiNow  = rsiBuf[0];
      double rsiPrev = rsiBuf[1];
      outRsi = rsiNow;

      // Bollinger (optional)
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

      // EMA trend filter (optional)
      double ema = 0;
      if(m_useTrendFilter)
      {
         double emaBuf[];
         ArraySetAsSeries(emaBuf, true);
         if(CopyBuffer(m_emaHandle, 0, 1, 1, emaBuf) <= 0) return SIG_NONE;
         ema = emaBuf[0];
      }

      bool nearSupport    = range.NearSupport(l[0]);
      bool nearResistance = range.NearResistance(h[0]);

      // BUY: bullish rejection at support
      if(nearSupport)
      {
         bool bullishEngulf = IsBullishEngulfing(o[1], c[1], o[0], c[0]);
         bool bullPin       = IsBullishPin(o[0], h[0], l[0], c[0]);
         bool patternOK     = bullishEngulf || bullPin;

         bool rsiOK         = (rsiNow <= m_rsiBuyMax) && (rsiNow >= rsiPrev); // turning up
         bool bbOK          = (!m_useBollinger) || (l[0] <= bbLower);

         // trend filter: skip BUY if price way below EMA200 (downtrend)
         bool trendOK = true;
         if(m_useTrendFilter && r.atr > 0)
         {
            double dist = (ema - c[0]); // positive if price below EMA
            if(dist > m_emaMaxDistAtr * r.atr) trendOK = false;
         }

         if(patternOK && rsiOK && bbOK && trendOK) return SIG_BUY;
      }

      // SELL: bearish rejection at resistance
      if(nearResistance)
      {
         bool bearishEngulf = IsBearishEngulfing(o[1], c[1], o[0], c[0]);
         bool shootingStar  = IsShootingStar(o[0], h[0], l[0], c[0]);
         bool patternOK     = bearishEngulf || shootingStar;

         bool rsiOK         = (rsiNow >= m_rsiSellMin) && (rsiNow <= rsiPrev); // turning down
         bool bbOK          = (!m_useBollinger) || (h[0] >= bbUpper);

         // trend filter: skip SELL if price way above EMA200 (uptrend)
         bool trendOK = true;
         if(m_useTrendFilter && r.atr > 0)
         {
            double dist = (c[0] - ema);
            if(dist > m_emaMaxDistAtr * r.atr) trendOK = false;
         }

         if(patternOK && rsiOK && bbOK && trendOK) return SIG_SELL;
      }

      return SIG_NONE;
   }

private:
   //--- bullish engulfing: prev red, current green, current body > prev body
   bool IsBullishEngulfing(double o1, double c1, double o0, double c0) const
   {
      if(!(c1 < o1 && c0 > o0)) return false;
      double body0 = c0 - o0;
      double body1 = o1 - c1;
      if(body1 <= 0 || body0 <= 0) return false;
      // current must engulf previous body
      bool engulf = (c0 >= o1) && (o0 <= c1);
      // current body must be larger
      bool stronger = body0 >= body1 * 1.0;
      return engulf && stronger;
   }

   bool IsBearishEngulfing(double o1, double c1, double o0, double c0) const
   {
      if(!(c1 > o1 && c0 < o0)) return false;
      double body0 = o0 - c0;
      double body1 = c1 - o1;
      if(body1 <= 0 || body0 <= 0) return false;
      bool engulf = (c0 <= o1) && (o0 >= c1);
      bool stronger = body0 >= body1 * 1.0;
      return engulf && stronger;
   }

   //--- bullish pin: long lower wick (>=2x body), small upper wick, close>=mid
   bool IsBullishPin(double op, double hi, double lo, double cl) const
   {
      double range = hi - lo;
      if(range <= 0) return false;
      double body  = MathAbs(cl - op);
      if(body <= 0) return false;
      double lower = MathMin(op, cl) - lo;
      double upper = hi - MathMax(op, cl);
      bool longLower    = lower >= 2.0 * body;
      bool shortUpper   = upper <= 0.5 * body;
      bool closeUpper   = cl >= (lo + range * 0.5);
      bool smallishBody = body <= range * 0.4;
      return longLower && shortUpper && closeUpper && smallishBody;
   }

   //--- shooting star: long upper wick, small lower, close<=mid
   bool IsShootingStar(double op, double hi, double lo, double cl) const
   {
      double range = hi - lo;
      if(range <= 0) return false;
      double body  = MathAbs(cl - op);
      if(body <= 0) return false;
      double upper = hi - MathMax(op, cl);
      double lower = MathMin(op, cl) - lo;
      bool longUpper    = upper >= 2.0 * body;
      bool shortLower   = lower <= 0.5 * body;
      bool closeLower   = cl <= (lo + range * 0.5);
      bool smallishBody = body <= range * 0.4;
      return longUpper && shortLower && closeLower && smallishBody;
   }
};

#endif // __XRSP_SIGNAL_ENGINE_MQH__
