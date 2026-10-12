//+------------------------------------------------------------------+
//|                                                    XauTheme.mqh  |
//|                     XAU Suite for MetaTrader 5 - colour themes   |
//+------------------------------------------------------------------+
#ifndef XAU_THEME_MQH
#define XAU_THEME_MQH

#include "XauBase.mqh"

enum ENUM_XAU_THEME
  {
   XAU_THEME_MIDNIGHT=0, // Midnight - mint / rose / gold
   XAU_THEME_AURORA=1,   // Aurora - aqua / magenta / violet
   XAU_THEME_CLASSIC=2,  // Classic - TradingView colours
   XAU_THEME_DAYLIGHT=3  // Daylight - for white charts
  };

//--- every entry is 0xRRGGBB; alpha is chosen where the colour is used
struct XauTheme
  {
   bool              dark;
   uint              bull;
   uint              bear;
   uint              gold;
   uint              blue;
   uint              violet;
   uint              orange;
   uint              cyan;
   uint              silver;
   uint              text;      // primary text
   uint              muted;     // secondary text, guides
   uint              neutral;   // flat / undecided state
   uint              panel;     // card background
   uint              border;    // card frame and grid
   uint              header;    // card header strip
   uint              ink;       // text drawn on solid coloured chips
   uint              chart_bg;  // used by the chart-theme script
   uint              chart_fg;
   uint              grid;
  };

void XauLoadTheme(const ENUM_XAU_THEME id,XauTheme &t)
  {
   switch(id)
     {
      case XAU_THEME_AURORA:
         t.dark=true;
         t.bull=0x2EE6D6;
         t.bear=0xFF4FA3;
         t.gold=0xFFD166;
         t.blue=0x7AA2FF;
         t.violet=0xB18CFF;
         t.orange=0xFF9E64;
         t.cyan=0x5CE1E6;
         t.silver=0xC9CFE0;
         t.text=0xE4E8F5;
         t.muted=0x8189A6;
         t.neutral=0x8F96B3;
         t.panel=0x161A2E;
         t.border=0x2C3354;
         t.header=0x20264A;
         t.ink=0x0F1222;
         t.chart_bg=0x0F1222;
         t.chart_fg=0x8189A6;
         t.grid=0x1C2140;
         break;
      case XAU_THEME_CLASSIC:
         t.dark=true;
         t.bull=0x089981;
         t.bear=0xF23645;
         t.gold=0xF7C548;
         t.blue=0x2962FF;
         t.violet=0x7E57C2;
         t.orange=0xFF9800;
         t.cyan=0x00BCD4;
         t.silver=0xB2B5BE;
         t.text=0xD1D4DC;
         t.muted=0x787B86;
         t.neutral=0x787B86;
         t.panel=0x131722;
         t.border=0x2A2E39;
         t.header=0x1E222D;
         t.ink=0xFFFFFF;
         t.chart_bg=0x131722;
         t.chart_fg=0x787B86;
         t.grid=0x1E222D;
         break;
      case XAU_THEME_DAYLIGHT:
         t.dark=false;
         t.bull=0x089981;
         t.bear=0xF23645;
         t.gold=0xC98A00;
         t.blue=0x2962FF;
         t.violet=0x7E57C2;
         t.orange=0xEF6C00;
         t.cyan=0x0097A7;
         t.silver=0x6A6D78;
         t.text=0x131722;
         t.muted=0x787B86;
         t.neutral=0x9598A1;
         t.panel=0xFFFFFF;
         t.border=0xE0E3EB;
         t.header=0xF0F3FA;
         t.ink=0xFFFFFF;
         t.chart_bg=0xFFFFFF;
         t.chart_fg=0x787B86;
         t.grid=0xF0F3FA;
         break;
      default: // Midnight
         t.dark=true;
         t.bull=0x26D7A8;
         t.bear=0xFF5D73;
         t.gold=0xF6C453;
         t.blue=0x5B8CFF;
         t.violet=0xA77BFF;
         t.orange=0xFF9F45;
         t.cyan=0x3DD6F5;
         t.silver=0xC3C8D4;
         t.text=0xD7DBE5;
         t.muted=0x7D8496;
         t.neutral=0x8A90A2;
         t.panel=0x131722;
         t.border=0x2A2E39;
         t.header=0x1B2030;
         t.ink=0x0B0E14;
         t.chart_bg=0x0E1117;
         t.chart_fg=0x7D8496;
         t.grid=0x161B26;
         break;
     }
  }

#endif
//+------------------------------------------------------------------+
