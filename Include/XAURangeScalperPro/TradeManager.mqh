//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|   XAU Range Scalper Pro - order open/close, BE, trailing, log    |
//+------------------------------------------------------------------+
#ifndef __XRSP_TRADE_MANAGER_MQH__
#define __XRSP_TRADE_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| CTradeManager                                                    |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   string         m_symbol;
   ulong          m_magic;
   int            m_slippagePoints;
   bool           m_useTrailing;
   double         m_trailStartPoints;   // start trailing after this profit
   double         m_trailStepPoints;    // distance to keep
   bool           m_useBreakEven;
   double         m_breakEvenTriggerPts;
   double         m_breakEvenLockPts;
   bool           m_drawObjects;
   bool           m_pushAlerts;
   string         m_logFile;
   int            m_logHandle;

   CTrade         m_trade;
   CPositionInfo  m_pos;

public:
   CTradeManager() : m_logHandle(INVALID_HANDLE) {}

   bool Init(const string symbol,
             const ulong magic,
             const int slippagePoints,
             const bool useTrailing,
             const double trailStartPoints,
             const double trailStepPoints,
             const bool useBreakEven,
             const double breakEvenTriggerPts,
             const double breakEvenLockPts,
             const bool drawObjects,
             const bool pushAlerts,
             const string logFileName)
   {
      m_symbol             = symbol;
      m_magic              = magic;
      m_slippagePoints     = slippagePoints;
      m_useTrailing        = useTrailing;
      m_trailStartPoints   = trailStartPoints;
      m_trailStepPoints    = trailStepPoints;
      m_useBreakEven       = useBreakEven;
      m_breakEvenTriggerPts= breakEvenTriggerPts;
      m_breakEvenLockPts   = breakEvenLockPts;
      m_drawObjects        = drawObjects;
      m_pushAlerts         = pushAlerts;
      m_logFile            = logFileName;

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippagePoints);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      m_logHandle = FileOpen(m_logFile, FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON|FILE_SHARE_READ);
      if(m_logHandle != INVALID_HANDLE)
      {
         FileSeek(m_logHandle, 0, SEEK_END);
         WriteLog("=== EA Started ===");
      }
      return true;
   }

   void Deinit()
   {
      if(m_logHandle != INVALID_HANDLE)
      {
         WriteLog("=== EA Stopped ===");
         FileClose(m_logHandle);
         m_logHandle = INVALID_HANDLE;
      }
   }

   //--- count own open positions
   int CountOpenPositions() const
   {
      int cnt = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         cnt++;
      }
      return cnt;
   }

   bool HasOpenPosition() const { return CountOpenPositions() > 0; }

   //--- open a market trade with SL/TP in PRICE
   bool OpenTrade(const ENUM_ORDER_TYPE type,
                  const double lots,
                  const double sl,
                  const double tp,
                  const string comment)
   {
      double price = (type == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      bool ok = false;
      if(type == ORDER_TYPE_BUY)
         ok = m_trade.Buy(lots, m_symbol, price, sl, tp, comment);
      else
         ok = m_trade.Sell(lots, m_symbol, price, sl, tp, comment);

      if(ok)
      {
         string txt = StringFormat("OPEN %s lots=%.2f price=%.2f SL=%.2f TP=%.2f (%s)",
                                   (type == ORDER_TYPE_BUY ? "BUY":"SELL"),
                                   lots, price, sl, tp, comment);
         WriteLog(txt);
         if(m_pushAlerts)
         {
            SendNotification(StringFormat("[XAU RSP] %s", txt));
            Alert(txt);
         }
         if(m_drawObjects)
            DrawEntry(type, price, sl, tp);
      }
      else
      {
         WriteLog(StringFormat("OPEN FAIL %s err=%d %s",
                              (type == ORDER_TYPE_BUY ? "BUY":"SELL"),
                              m_trade.ResultRetcode(),
                              m_trade.ResultRetcodeDescription()));
      }
      return ok;
   }

   //--- manage open positions: BE + trailing
   void ManageOpenPositions()
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!m_pos.SelectByTicket(ticket)) continue;
         if(m_pos.Symbol() != m_symbol) continue;
         if((ulong)m_pos.Magic() != m_magic) continue;

         double openPrice = m_pos.PriceOpen();
         double sl        = m_pos.StopLoss();
         double tp        = m_pos.TakeProfit();
         long   type      = m_pos.PositionType();

         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double curPrice = (type == POSITION_TYPE_BUY) ? bid : ask;

         double profitPts = 0.0;
         if(type == POSITION_TYPE_BUY)  profitPts = (curPrice - openPrice) / point;
         else                           profitPts = (openPrice - curPrice) / point;

         double newSL = sl;

         //--- break-even
         if(m_useBreakEven && profitPts >= m_breakEvenTriggerPts)
         {
            double beSL = (type == POSITION_TYPE_BUY)
                          ? openPrice + m_breakEvenLockPts * point
                          : openPrice - m_breakEvenLockPts * point;
            if(type == POSITION_TYPE_BUY  && (sl < beSL || sl == 0)) newSL = beSL;
            if(type == POSITION_TYPE_SELL && (sl > beSL || sl == 0)) newSL = beSL;
         }

         //--- trailing
         if(m_useTrailing && profitPts >= m_trailStartPoints)
         {
            double trailSL = (type == POSITION_TYPE_BUY)
                             ? curPrice - m_trailStepPoints * point
                             : curPrice + m_trailStepPoints * point;
            if(type == POSITION_TYPE_BUY  && trailSL > newSL) newSL = trailSL;
            if(type == POSITION_TYPE_SELL && (trailSL < newSL || newSL == 0)) newSL = trailSL;
         }

         if(MathAbs(newSL - sl) > point && newSL != 0)
         {
            if(m_trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp))
               WriteLog(StringFormat("MODIFY ticket=%I64u newSL=%.2f", ticket, newSL));
         }
      }
   }

   //--- close all of our positions (used on daily loss limit)
   void CloseAllOurPositions(const string reason)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!m_pos.SelectByTicket(ticket)) continue;
         if(m_pos.Symbol() != m_symbol) continue;
         if((ulong)m_pos.Magic() != m_magic) continue;

         if(m_trade.PositionClose(ticket))
            WriteLog(StringFormat("CLOSE ticket=%I64u (%s)", ticket, reason));
      }
   }

   //--- log helper
   void WriteLog(const string msg)
   {
      Print("[XAU RSP] ", msg);
      if(m_logHandle == INVALID_HANDLE) return;
      string ts   = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
      string line = ts + " | " + msg;
      FileWriteString(m_logHandle, line);
      FileWriteString(m_logHandle, ShortToString(13) + ShortToString(10));
      FileFlush(m_logHandle);
   }

private:
   //--- draw entry arrow + SL/TP horizontal lines
   void DrawEntry(const ENUM_ORDER_TYPE type, const double price, const double sl, const double tp)
   {
      string ts  = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
      string tag = StringFormat("XRSP_%s", ts);
      StringReplace(tag, ":", "");
      StringReplace(tag, " ", "_");
      StringReplace(tag, ".", "");

      string arrowName = "ARR_" + tag;
      if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), price))
      {
         ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE,
                          (type == ORDER_TYPE_BUY) ? 233 : 234);
         ObjectSetInteger(0, arrowName, OBJPROP_COLOR,
                          (type == ORDER_TYPE_BUY) ? clrLime : clrRed);
         ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
      }

      if(sl > 0)
      {
         string slName = "SL_" + tag;
         if(ObjectCreate(0, slName, OBJ_HLINE, 0, 0, sl))
         {
            ObjectSetInteger(0, slName, OBJPROP_COLOR, clrCrimson);
            ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetString(0, slName, OBJPROP_TEXT, "SL");
         }
      }
      if(tp > 0)
      {
         string tpName = "TP_" + tag;
         if(ObjectCreate(0, tpName, OBJ_HLINE, 0, 0, tp))
         {
            ObjectSetInteger(0, tpName, OBJPROP_COLOR, clrDodgerBlue);
            ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetString(0, tpName, OBJPROP_TEXT, "TP");
         }
      }
   }
};

#endif // __XRSP_TRADE_MANAGER_MQH__
