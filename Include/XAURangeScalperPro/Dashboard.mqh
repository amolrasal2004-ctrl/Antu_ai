//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|        XAU Range Scalper Pro - on-chart info panel               |
//+------------------------------------------------------------------+
#ifndef __XRSP_DASHBOARD_MQH__
#define __XRSP_DASHBOARD_MQH__

#include "RangeDetector.mqh"

struct SStats
{
   int    totalTrades;
   int    wins;
   int    losses;
   double dayPnL;
   double dayPnLPercent;
   int    spreadPoints;
   bool   filtersOK;
   string filterReason;
};

//+------------------------------------------------------------------+
//| CDashboard - simple labels block on top-left                     |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   string m_prefix;
   int    m_x;
   int    m_y;
   int    m_lineHeight;
   color  m_titleColor;
   color  m_textColor;

public:
   void Init()
   {
      m_prefix      = "XRSP_DASH_";
      m_x           = 10;
      m_y           = 20;
      m_lineHeight  = 16;
      m_titleColor  = clrGold;
      m_textColor   = clrWhite;
   }

   void Deinit()
   {
      ObjectsDeleteAll(0, m_prefix);
   }

   void Update(const SRange &r, const SStats &s)
   {
      int line = 0;
      DrawLabel(line++, "XAU Range Scalper Pro",
                StringFormat("v1.0  %s", _Symbol),
                m_titleColor);

      DrawLabel(line++, "Range",
                r.valid
                   ? StringFormat("S=%.2f  R=%.2f  W=%.2f", r.support, r.resistance, r.width)
                   : "INVALID",
                r.valid ? clrLime : clrOrangeRed);

      DrawLabel(line++, "Touches",
                StringFormat("Sup=%d  Res=%d  ATR=%.2f",
                             r.supportTouches, r.resistanceTouches, r.atr),
                m_textColor);

      double wr = (s.totalTrades > 0)
                  ? (100.0 * s.wins / s.totalTrades) : 0.0;
      DrawLabel(line++, "Trades",
                StringFormat("%d (W:%d / L:%d)  WR=%.1f%%",
                             s.totalTrades, s.wins, s.losses, wr),
                m_textColor);

      DrawLabel(line++, "Daily PnL",
                StringFormat("%.2f (%.2f%%)", s.dayPnL, s.dayPnLPercent),
                (s.dayPnL >= 0) ? clrLime : clrRed);

      DrawLabel(line++, "Spread",
                StringFormat("%d pts", s.spreadPoints),
                m_textColor);

      DrawLabel(line++, "Filter",
                s.filtersOK ? "OK" : s.filterReason,
                s.filtersOK ? clrLime : clrOrange);
   }

private:
   void DrawLabel(int line, const string title, const string value, color clr)
   {
      string name = StringFormat("%sL%02d", m_prefix, line);
      string text = StringFormat("%-10s : %s", title, value);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y + line * m_lineHeight);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
         ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString (0, name, OBJPROP_TEXT,  text);
   }
};

#endif // __XRSP_DASHBOARD_MQH__
