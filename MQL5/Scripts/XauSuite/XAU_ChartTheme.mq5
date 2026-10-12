//+------------------------------------------------------------------+
//|                                               XAU_ChartTheme.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Restyles the current chart to match an XAU Suite colour theme:    |
//| TradingView-like background, candle colours, quiet grid and axis. |
//| The chosen theme also becomes the suite theme, which indicators   |
//| set to "Suite theme" pick up the next time they load.             |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.10"
#property description "Apply an XAU Suite colour theme to the current chart."
#property script_show_inputs

#include <XauSuite/XauTheme.mqh>

input ENUM_XAU_THEME InpTheme      = XAU_THEME_MIDNIGHT; // Colour theme
input bool           InpShowGrid   = false; // Show grid
input bool           InpHollowBull = false; // Hollow bullish candles
input bool           InpHideVolume = true;  // Hide the volume histogram
input bool           InpChartShift = true;  // Leave space on the right for tags

void OnStart()
  {
   ENUM_XAU_THEME id=XauResolveTheme(InpTheme);
   XauSetSuiteTheme(id);
   XauTheme t;
   XauLoadTheme(id,t);
   XauApplyChartTheme(ChartID(),t,InpShowGrid,InpHollowBull,InpHideVolume,InpChartShift);
  }
//+------------------------------------------------------------------+
