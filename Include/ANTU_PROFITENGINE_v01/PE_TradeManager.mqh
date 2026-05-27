//+------------------------------------------------------------------+
//|                                            PE_TradeManager.mqh   |
//|                       ANTU PROFIT ENGINE v01 - Order Execution   |
//|                                                                  |
//|  Purpose: BUY/SELL orders open karna, SL/TP set, close trades    |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Trade Manager Class                                              |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade         m_trade;
   CPositionInfo  m_pos;
   string         m_symbol;
   ulong          m_magicNumber;
   string         m_comment;

public:
   //--- Constructor
   CTradeManager(string symbol, ulong magic, string comment)
   {
      m_symbol      = symbol;
      m_magicNumber = magic;
      m_comment     = comment;
      
      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(m_symbol);
      m_trade.SetDeviationInPoints(20); // 20 points slippage allowed
   }
   
   //--- Open BUY order
   bool OpenBuy(double lot, double slPips, double tpPips, double pipValue)
   {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - slPips * pipValue, 
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      double tp  = NormalizeDouble(ask + tpPips * pipValue, 
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      
      bool result = m_trade.Buy(lot, m_symbol, ask, sl, tp, m_comment);
      
      if(result)
         Print(">>> ANTU BUY: ", lot, " lots @ ", ask, " SL:", sl, " TP:", tp);
      else
         Print(">>> ANTU BUY FAILED: ", m_trade.ResultRetcodeDescription());
      
      return result;
   }
   
   //--- Open SELL order
   bool OpenSell(double lot, double slPips, double tpPips, double pipValue)
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + slPips * pipValue, 
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      double tp  = NormalizeDouble(bid - tpPips * pipValue, 
                                   (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      
      bool result = m_trade.Sell(lot, m_symbol, bid, sl, tp, m_comment);
      
      if(result)
         Print(">>> ANTU SELL: ", lot, " lots @ ", bid, " SL:", sl, " TP:", tp);
      else
         Print(">>> ANTU SELL FAILED: ", m_trade.ResultRetcodeDescription());
      
      return result;
   }
   
   //--- Count open positions for this EA
   int CountOpenPositions()
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_pos.SelectByIndex(i))
         {
            if(m_pos.Symbol() == m_symbol && m_pos.Magic() == m_magicNumber)
               count++;
         }
      }
      return count;
   }
   
   //--- Close all positions for this EA
   void CloseAll()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_pos.SelectByIndex(i))
         {
            if(m_pos.Symbol() == m_symbol && m_pos.Magic() == m_magicNumber)
               m_trade.PositionClose(m_pos.Ticket());
         }
      }
   }
   
   //--- Get total floating P&L for this EA
   double GetFloatingPnL()
   {
      double total = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_pos.SelectByIndex(i))
         {
            if(m_pos.Symbol() == m_symbol && m_pos.Magic() == m_magicNumber)
               total += m_pos.Profit() + m_pos.Swap() + m_pos.Commission();
         }
      }
      return total;
   }
   
   //--- Magic number getter
   ulong Magic() { return m_magicNumber; }
};
//+------------------------------------------------------------------+
