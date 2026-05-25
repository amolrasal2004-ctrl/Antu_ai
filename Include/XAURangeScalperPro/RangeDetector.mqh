//+------------------------------------------------------------------+
//|                                                RangeDetector.mqh |
//|              XAU Range Scalper Pro - Range / S&R detection       |
//|  v1.1 improvements:                                              |
//|   - ADX filter (only trade when ADX < threshold = ranging)       |
//|   - Touch spacing requirement (touches must be distributed over  |
//|     time, not clustered in last few bars)                        |
//|   - Higher-timeframe range confirmation (optional)               |
//|   - Stronger breakout: 2-bar momentum check                      |
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
   double   adx;              // current ADX (trend strength)
   datetime computedAt;       // last computation time
   string   reason;           // why valid/invalid (for dashboard)
};

//+------------------------------------------------------------------+
//| CRangeDetector                                                   |
//+------------------------------------------------------------------+
class CRangeDetector
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   ENUM_TIMEFRAMES   m_htf;               // higher TF for confirmation
   int               m_lookback;
   int               m_atrPeriod;
   int               m_adxPeriod;
   double            m_atrMaxRatio;
   double            m_adxMax;            // ADX must be below this
   double            m_touchTolerancePts;
   int               m_minTouches;
   int               m_minTouchSpacing;   // bars between any two touches on same side
   bool              m_useHtfFilter;

   int               m_atrHandle;
   int               m_adxHandle;
   int               m_atrHtfHandle;

   SRange            m_range;

public:
   CRangeDetector() : m_atrHandle(INVALID_HANDLE),
                      m_adxHandle(INVALID_HANDLE),
                      m_atrHtfHandle(INVALID_HANDLE) {}

   bool Init(const string symbol,
             const ENUM_TIMEFRAMES tf,
             const int lookback,
             const int atrPeriod,
             const int adxPeriod,
             const double atrMaxRatio,
             const double adxMax,
             const double touchTolerancePoints,
             const int minTouches,
             const int minTouchSpacing,
             const bool useHtfFilter,
             const ENUM_TIMEFRAMES htf)
   {
      m_symbol             = symbol;
      m_tf                 = tf;
      m_htf                = htf;
      m_lookback           = lookback;
      m_atrPeriod          = atrPeriod;
      m_adxPeriod          = adxPeriod;
      m_atrMaxRatio        = atrMaxRatio;
      m_adxMax             = adxMax;
      m_touchTolerancePts  = touchTolerancePoints;
      m_minTouches         = minTouches;
      m_minTouchSpacing    = minTouchSpacing;
      m_useHtfFilter       = useHtfFilter;

      m_atrHandle = iATR(m_symbol, m_tf, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("RangeDetector: ATR handle failed, err=", GetLastError());
         return false;
      }

      m_adxHandle = iADX(m_symbol, m_tf, m_adxPeriod);
      if(m_adxHandle == INVALID_HANDLE)
      {
         Print("RangeDetector: ADX handle failed, err=", GetLastError());
         return false;
      }

      if(m_useHtfFilter)
      {
         m_atrHtfHandle = iATR(m_symbol, m_htf, m_atrPeriod);
         if(m_atrHtfHandle == INVALID_HANDLE)
         {
            Print("RangeDetector: HTF ATR handle failed, err=", GetLastError());
            return false;
         }
      }

      ResetRange();
      return true;
   }

   void Deinit()
   {
      if(m_atrHandle    != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_adxHandle    != INVALID_HANDLE) IndicatorRelease(m_adxHandle);
      if(m_atrHtfHandle != INVALID_HANDLE) IndicatorRelease(m_atrHtfHandle);
      m_atrHandle    = INVALID_HANDLE;
      m_adxHandle    = INVALID_HANDLE;
      m_atrHtfHandle = INVALID_HANDLE;
   }

   //--- recompute on each new bar; uses only closed bars (shift>=1)
   bool Update()
   {
      ResetRange();
      m_range.computedAt = TimeCurrent();
      m_range.reason     = "n/a";

      if(Bars(m_symbol, m_tf) < m_lookback + 5)
      {
         m_range.reason = "not enough bars";
         return false;
      }

      // pull data: indices 1..lookback (closed bars only, no repaint)
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
      if(width <= 0)
      {
         m_range.reason = "no width";
         return false;
      }

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tol   = m_touchTolerancePts * point;

      // count rejection touches AND record their bar indices
      int sIdx[], rIdx[];
      ArrayResize(sIdx, 0);
      ArrayResize(rIdx, 0);
      int sTouch = 0, rTouch = 0;

      for(int i = 0; i < m_lookback; i++)
      {
         // resistance rejection
         if(highs[i] >= resistance - tol && closes[i] < resistance - tol*0.5)
         {
            int n = ArraySize(rIdx);
            ArrayResize(rIdx, n + 1);
            rIdx[n] = i;
            rTouch++;
         }
         // support rejection
         if(lows[i] <= support + tol && closes[i] > support + tol*0.5)
         {
            int n = ArraySize(sIdx);
            ArrayResize(sIdx, n + 1);
            sIdx[n] = i;
            sTouch++;
         }
      }

      // ATR
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(m_atrHandle, 0, 1, 1, atrBuf) <= 0) return false;
      double atr = atrBuf[0];

      // ADX (main line on buffer 0)
      double adxBuf[];
      ArraySetAsSeries(adxBuf, true);
      if(CopyBuffer(m_adxHandle, 0, 1, 1, adxBuf) <= 0) return false;
      double adx = adxBuf[0];

      m_range.support           = support;
      m_range.resistance        = resistance;
      m_range.width             = width;
      m_range.supportTouches    = sTouch;
      m_range.resistanceTouches = rTouch;
      m_range.atr               = atr;
      m_range.adx               = adx;

      //--- VALIDATION

      // 1) enough touches each side
      if(sTouch < m_minTouches || rTouch < m_minTouches)
      {
         m_range.valid  = false;
         m_range.reason = StringFormat("touches S=%d R=%d", sTouch, rTouch);
         return true;
      }

      // 2) touches must be spaced over time (not clustered)
      if(!TouchesSpaced(sIdx, sTouch) || !TouchesSpaced(rIdx, rTouch))
      {
         m_range.valid  = false;
         m_range.reason = "touches clustered";
         return true;
      }

      // 3) low ATR / range ratio
      if(atr <= 0 || (atr / width) > m_atrMaxRatio)
      {
         m_range.valid  = false;
         m_range.reason = StringFormat("ATR/W=%.2f", (width > 0 ? atr/width : 0));
         return true;
      }

      // 4) ADX < threshold = market is ranging, not trending
      if(adx > m_adxMax)
      {
         m_range.valid  = false;
         m_range.reason = StringFormat("ADX=%.1f trending", adx);
         return true;
      }

      // 5) higher-TF confirmation: HTF ATR shouldn't be exploding
      if(m_useHtfFilter)
      {
         double htfAtr[];
         ArraySetAsSeries(htfAtr, true);
         if(CopyBuffer(m_atrHtfHandle, 0, 1, 3, htfAtr) > 0)
         {
            double htfAtrAvg = (htfAtr[0] + htfAtr[1] + htfAtr[2]) / 3.0;
            // if HTF ATR is much larger than width -> HTF is volatile, skip
            if(htfAtrAvg > width * 0.5)
            {
               m_range.valid  = false;
               m_range.reason = "HTF too volatile";
               return true;
            }
         }
      }

      m_range.valid  = true;
      m_range.reason = "OK";
      return true;
   }

   //--- breakout detection (improved): 2 consecutive closes outside +
   //    last bar body > 1.0 * ATR
   bool IsStrongBreakout() const
   {
      if(m_range.width <= 0 || m_range.atr <= 0) return false;

      double o[], c[];
      ArraySetAsSeries(o, true);
      ArraySetAsSeries(c, true);
      if(CopyOpen(m_symbol, m_tf, 1, 2, o) <= 0) return false;
      if(CopyClose(m_symbol, m_tf, 1, 2, c) <= 0) return false;

      double body0 = MathAbs(c[0] - o[0]);
      bool bigCandle = body0 > 1.0 * m_range.atr;

      // up breakout: last 2 closes above resistance AND last candle big
      bool brokeUp = (c[0] > m_range.resistance) &&
                     (c[1] > m_range.resistance) &&
                     bigCandle;

      // down breakout: last 2 closes below support AND last candle big
      bool brokeDown = (c[0] < m_range.support) &&
                       (c[1] < m_range.support) &&
                       bigCandle;

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

private:
   //--- reset SRange without ZeroMemory (it has a string member)
   void ResetRange()
   {
      m_range.valid             = false;
      m_range.support           = 0.0;
      m_range.resistance        = 0.0;
      m_range.width             = 0.0;
      m_range.supportTouches    = 0;
      m_range.resistanceTouches = 0;
      m_range.atr               = 0.0;
      m_range.adx               = 0.0;
      m_range.computedAt        = 0;
      m_range.reason            = "";
   }

   //--- check that any two touches are at least m_minTouchSpacing bars apart
   bool TouchesSpaced(const int &idx[], const int count) const
   {
      if(count < 2) return false;
      for(int i = 0; i < count; i++)
         for(int j = i + 1; j < count; j++)
            if(MathAbs(idx[i] - idx[j]) >= m_minTouchSpacing)
               return true;
      return false;
   }
};

#endif // __XRSP_RANGE_DETECTOR_MQH__
