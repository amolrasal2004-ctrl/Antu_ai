//+------------------------------------------------------------------+
//|                                                RangeDetector.mqh |
//|              XAU Range Scalper Pro - Range / S&R detection       |
//+------------------------------------------------------------------+
#ifndef __XRSP_RANGE_DETECTOR_MQH__
#define __XRSP_RANGE_DETECTOR_MQH__

//+------------------------------------------------------------------+
//| Holds the current detected range                                 |
//+------------------------------------------------------------------+
struct SRange
{
   bool     valid;            // is range currently valid
   double   support;          // support price
   double   resistance;       // resistance price
   double   width;            // resistance - support
   int      supportTouches;   // how many rejections from support
   int      resistanceTouches;// how many rejections from resistance
   double   atr;              // current ATR
   datetime computedAt;       // last computation time
};

//+------------------------------------------------------------------+
//| CRangeDetector                                                   |
//|  - Detects sideways range using last N candles                   |
//|  - Counts support/resistance rejections (no repainting: uses     |
//|    only fully closed candles)                                    |
//|  - Confirms low-volatility env via ATR                           |
//+------------------------------------------------------------------+
class CRangeDetector
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_lookback;
   int               m_atrPeriod;
   double            m_atrMaxRatio;       // max ATR / range width ratio (low vol)
   double            m_touchTolerancePts; // distance in points to count a touch
   int               m_minTouches;        // touches required per side
   int               m_atrHandle;
   SRange            m_range;

public:
   CRangeDetector() : m_atrHandle(INVALID_HANDLE) {}

   bool Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const int lookback,
             const int atrPeriod,
             const double atrMaxRatio,
             const double touchTolerancePoints,
             const int minTouches)
   {
      m_symbol             = symbol;
      m_tf                 = tf;
      m_lookback           = lookback;
      m_atrPeriod          = atrPeriod;
      m_atrMaxRatio        = atrMaxRatio;
      m_touchTolerancePts  = touchTolerancePoints;
      m_minTouches         = minTouches;

      m_atrHandle = iATR(m_symbol, m_tf, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("RangeDetector: failed to create ATR handle, err=", GetLastError());
         return false;
      }

      ZeroMemory(m_range);
      return true;
   }

   void Deinit()
   {
      if(m_atrHandle != INVALID_HANDLE)
         IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }

   //--- recompute on each new bar; uses only closed bars (shift>=1)
   bool Update()
   {
      ZeroMemory(m_range);
      m_range.computedAt = TimeCurrent();

      if(Bars(m_symbol, m_tf) < m_lookback + 5) return false;

      // pull highs/lows for last lookback candles, indices 1..lookback (closed)
      double highs[], lows[], closes[], opens[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      ArraySetAsSeries(closes, true);
      ArraySetAsSeries(opens, true);
      if(CopyHigh(m_symbol, m_tf, 1, m_lookback, highs)   <= 0) return false;
      if(CopyLow(m_symbol, m_tf, 1, m_lookback, lows)     <= 0) return false;
      if(CopyClose(m_symbol, m_tf, 1, m_lookback, closes) <= 0) return false;
      if(CopyOpen(m_symbol, m_tf, 1, m_lookback, opens)   <= 0) return false;

      double resistance = highs[ArrayMaximum(highs, 0, m_lookback)];
      double support    = lows[ArrayMinimum(lows,  0, m_lookback)];
      double width      = resistance - support;
      if(width <= 0) return false;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tol   = m_touchTolerancePts * point;

      // count rejection touches: candle wick reaches level then closes back inside
      int sTouch = 0, rTouch = 0;
      for(int i = 0; i < m_lookback; i++)
      {
         // resistance rejection: high near resistance, close clearly below
         if(highs[i] >= resistance - tol && closes[i] < resistance - tol*0.5)
            rTouch++;

         // support rejection: low near support, close clearly above
         if(lows[i] <= support + tol && closes[i] > support + tol*0.5)
            sTouch++;
      }

      // ATR
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(m_atrHandle, 0, 1, 1, atrBuf) <= 0) return false;
      double atr = atrBuf[0];

      m_range.support           = support;
      m_range.resistance        = resistance;
      m_range.width             = width;
      m_range.supportTouches    = sTouch;
      m_range.resistanceTouches = rTouch;
      m_range.atr               = atr;

      // validity:
      //  - enough touches each side
      //  - low volatility (ATR small relative to range width)
      bool enoughTouches = (sTouch >= m_minTouches && rTouch >= m_minTouches);
      bool lowVol        = (atr > 0 && (atr / width) <= m_atrMaxRatio);

      m_range.valid = enoughTouches && lowVol;
      return true;
   }

   //--- breakout detection: latest closed candle closes outside range
   //    with a body > 1.2 * ATR -> strong breakout
   bool IsStrongBreakout() const
   {
      if(!m_range.valid && m_range.width <= 0) return false;

      double o[], c[];
      ArraySetAsSeries(o, true);
      ArraySetAsSeries(c, true);
      if(CopyOpen(m_symbol, m_tf, 1, 1, o) <= 0) return false;
      if(CopyClose(m_symbol, m_tf, 1, 1, c) <= 0) return false;

      double body = MathAbs(c[0] - o[0]);
      if(m_range.atr <= 0) return false;
      bool bigCandle = body > 1.2 * m_range.atr;

      bool brokeUp   = c[0] > m_range.resistance && bigCandle;
      bool brokeDown = c[0] < m_range.support    && bigCandle;
      return brokeUp || brokeDown;
   }

   const SRange Range() const { return m_range; }

   //--- helpers
   bool NearSupport(const double price) const
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tol   = m_touchTolerancePts * point;
      return (price <= m_range.support + tol);
   }

   bool NearResistance(const double price) const
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tol   = m_touchTolerancePts * point;
      return (price >= m_range.resistance - tol);
   }
};

#endif // __XRSP_RANGE_DETECTOR_MQH__
