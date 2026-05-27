//+------------------------------------------------------------------+
//|                                                PE_Dashboard.mqh  |
//|                          ANTU PROFIT ENGINE v01 - Visual Display |
//|                                                                  |
//|  Purpose: Chart pe professional dashboard banao                  |
//|           Real-time status, P&L, filters - sab dikhao            |
//+------------------------------------------------------------------+
#property copyright "ANTU PROFIT ENGINE v01"
#property strict

#include "PE_RangeDetector.mqh"
#include "PE_Filters.mqh"
#include "PE_RiskManager.mqh"

//+------------------------------------------------------------------+
//| Dashboard Class                                                  |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   string m_prefix;          // Object name prefix
   int    m_xStart;          // X position
   int    m_yStart;          // Y position
   int    m_width;           // Panel width
   int    m_lineHeight;      // Line spacing
   color  m_bgColor;
   color  m_textColor;
   color  m_goodColor;
   color  m_badColor;
   color  m_warnColor;
   color  m_headerColor;
   
   //--- Create background rectangle
   void CreateBG(string name, int x, int y, int w, int h, color clr)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   
   //--- Create text label
   void CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 9)
   {
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

public:
   //--- Constructor
   CDashboard(string prefix = "ANTU_DASH_")
   {
      m_prefix      = prefix;
      m_xStart      = 15;
      m_yStart      = 25;
      m_width       = 280;
      m_lineHeight  = 17;
      
      m_bgColor     = C'25,25,35';
      m_textColor   = clrWhite;
      m_goodColor   = clrLime;
      m_badColor    = clrRed;
      m_warnColor   = clrOrange;
      m_headerColor = C'255,200,50'; // gold
   }
   
   //--- Initialize dashboard (background panel)
   void Init()
   {
      // Background panel
      CreateBG(m_prefix + "BG", m_xStart - 5, m_yStart - 5, 
               m_width, 380, m_bgColor);
      
      // Header bar
      CreateBG(m_prefix + "HDR", m_xStart - 5, m_yStart - 5, 
               m_width, 24, C'45,45,75');
   }
   
   //--- Update dashboard with latest data
   void Update(string symbol, CRangeDetector *rangeDet, 
               CFilters *filters, CRiskManager *risk, 
               int openPositions, double floatingPnL)
   {
      int y = m_yStart;
      int x = m_xStart;
      
      //--- HEADER ---
      CreateLabel(m_prefix + "TITLE", x, y, 
                  "  ANTU PROFITENGINE v01", m_headerColor, 10);
      y += m_lineHeight + 8;
      
      //--- STATUS LINE ---
      string statusText;
      color  statusClr;
      if(risk.IsLocked())
      {
         statusText = "STATUS:  [LOCKED] " + risk.LockReasonText();
         statusClr  = m_badColor;
      }
      else
      {
         statusText = "STATUS:  [ACTIVE]";
         statusClr  = m_goodColor;
      }
      CreateLabel(m_prefix + "STATUS", x, y, statusText, statusClr);
      y += m_lineHeight;
      
      //--- Market Mode ---
      bool isRange = filters.ADXOk() && filters.ATROk();
      CreateLabel(m_prefix + "MODE", x, y, 
                  "Market: " + (isRange ? "[RANGE - OK]" : "[TREND - WAIT]"),
                  isRange ? m_goodColor : m_warnColor);
      y += m_lineHeight + 5;
      
      //--- DIVIDER ---
      CreateLabel(m_prefix + "DIV1", x, y, 
                  "---------- RANGE ----------", clrSlateGray);
      y += m_lineHeight;
      
      //--- RANGE INFO ---
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(rangeDet.currentRange.isValid)
      {
         CreateLabel(m_prefix + "RHIGH", x, y, 
                     "High:   " + DoubleToString(rangeDet.currentRange.high, digits),
                     m_textColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RLOW", x, y, 
                     "Low:    " + DoubleToString(rangeDet.currentRange.low, digits),
                     m_textColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RSIZE", x, y, 
                     "Size:   " + DoubleToString(rangeDet.currentRange.sizePips, 1) + " pips",
                     m_textColor);
         y += m_lineHeight;
      }
      else
      {
         CreateLabel(m_prefix + "RHIGH", x, y, "Range:  [INVALID]", m_warnColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RLOW", x, y, "", m_textColor);
         y += m_lineHeight;
         CreateLabel(m_prefix + "RSIZE", x, y, "", m_textColor);
         y += m_lineHeight;
      }
      
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      CreateLabel(m_prefix + "RPRICE", x, y, 
                  "Price:  " + DoubleToString(bid, digits), m_headerColor);
      y += m_lineHeight + 5;
      
      //--- DIVIDER ---
      CreateLabel(m_prefix + "DIV2", x, y, 
                  "---------- FILTERS --------", clrSlateGray);
      y += m_lineHeight;
      
      //--- FILTERS ---
      CreateLabel(m_prefix + "FADX", x, y, 
                  "ADX:    " + DoubleToString(filters.GetADX(), 1) + 
                  (filters.ADXOk() ? "  [OK]" : "  [TREND]"),
                  filters.ADXOk() ? m_goodColor : m_warnColor);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "FATR", x, y, 
                  "ATR:    " + DoubleToString(filters.GetATR(), 2) + 
                  (filters.ATROk() ? "  [OK]" : "  [HIGH]"),
                  filters.ATROk() ? m_goodColor : m_warnColor);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "FRSI", x, y, 
                  "RSI:    " + DoubleToString(filters.GetRSI(), 1),
                  m_textColor);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "FSPR", x, y, 
                  "Spread: " + IntegerToString(filters.GetSpread()) + " pts" +
                  (filters.SpreadOk() ? "  [OK]" : "  [HIGH]"),
                  filters.SpreadOk() ? m_goodColor : m_warnColor);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "FSESS", x, y, 
                  "Session: " + (filters.SessionOk() ? "[OPEN]" : "[CLOSED]"),
                  filters.SessionOk() ? m_goodColor : m_warnColor);
      y += m_lineHeight + 5;
      
      //--- DIVIDER ---
      CreateLabel(m_prefix + "DIV3", x, y, 
                  "---------- TODAY ----------", clrSlateGray);
      y += m_lineHeight;
      
      //--- DAILY P&L ---
      double pnl   = risk.DailyPnL() + floatingPnL;
      double tgt   = risk.DailyTarget();
      double pct   = (tgt > 0) ? (pnl / tgt * 100.0) : 0.0;
      color  pnlClr = (pnl >= 0) ? m_goodColor : m_badColor;
      
      CreateLabel(m_prefix + "PNL", x, y, 
                  "P&L:    $" + DoubleToString(pnl, 2) + 
                  "  (" + DoubleToString(pct, 0) + "%)", pnlClr);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "TGT", x, y, 
                  "Target: $" + DoubleToString(tgt, 2) + 
                  " | Loss: -$" + DoubleToString(risk.DailyLossLimit(), 2),
                  m_textColor);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "TRADES", x, y, 
                  "Trades: " + IntegerToString(risk.TradesToday()) + 
                  " / " + IntegerToString(risk.MaxTrades()), m_textColor);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "OPEN", x, y, 
                  "Open:   " + IntegerToString(openPositions) + 
                  "  | Float: $" + DoubleToString(floatingPnL, 2),
                  (floatingPnL >= 0) ? m_goodColor : m_badColor);
      y += m_lineHeight;
      
      CreateLabel(m_prefix + "CONSEC", x, y, 
                  "Consec L: " + IntegerToString(risk.ConsecLosses()),
                  (risk.ConsecLosses() > 0) ? m_warnColor : m_textColor);
      y += m_lineHeight + 5;
      
      //--- EMERGENCY LOCK STATUS ---
      CreateLabel(m_prefix + "LOCK", x, y, 
                  "EMERGENCY: " + (risk.IsLocked() ? "[ACTIVE]" : "[OFF]"),
                  risk.IsLocked() ? m_badColor : m_goodColor);
      
      ChartRedraw(0);
   }
   
   //--- Cleanup all dashboard objects
   void Cleanup()
   {
      ObjectsDeleteAll(0, m_prefix);
      ChartRedraw(0);
   }
};
//+------------------------------------------------------------------+
