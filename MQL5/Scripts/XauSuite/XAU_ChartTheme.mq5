//+------------------------------------------------------------------+
//|                                               XAU_ChartTheme.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Restyles the current chart to match an XAU Suite colour theme:    |
//| TradingView-like background, candle colours, quiet grid and axis. |
//| Save the result as a template (Charts > Templates > Save) to      |
//| reuse it.                                                         |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
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
   XauTheme t;
   XauLoadTheme(InpTheme,t);
   long id=ChartID();
   ChartSetInteger(id,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(id,CHART_FOREGROUND,false); // keep the canvas front layers above the candles
   ChartSetInteger(id,CHART_SHOW_GRID,InpShowGrid);
   ChartSetInteger(id,CHART_COLOR_BACKGROUND,XClr(t.chart_bg));
   ChartSetInteger(id,CHART_COLOR_FOREGROUND,XClr(t.chart_fg));
   ChartSetInteger(id,CHART_COLOR_GRID,XClr(t.grid));
   ChartSetInteger(id,CHART_COLOR_CHART_UP,XClr(t.bull));
   ChartSetInteger(id,CHART_COLOR_CHART_DOWN,XClr(t.bear));
   ChartSetInteger(id,CHART_COLOR_CANDLE_BULL,InpHollowBull ? XClr(t.chart_bg) : XClr(t.bull));
   ChartSetInteger(id,CHART_COLOR_CANDLE_BEAR,XClr(t.bear));
   ChartSetInteger(id,CHART_COLOR_CHART_LINE,XClr(t.gold));
   ChartSetInteger(id,CHART_COLOR_VOLUME,XClr(t.muted));
   ChartSetInteger(id,CHART_COLOR_BID,XClr(t.gold));
   ChartSetInteger(id,CHART_COLOR_ASK,XClr(t.muted));
   ChartSetInteger(id,CHART_COLOR_LAST,XClr(t.text));
   ChartSetInteger(id,CHART_COLOR_STOP_LEVEL,XClr(t.bear));
   if(InpHideVolume)
      ChartSetInteger(id,CHART_SHOW_VOLUMES,CHART_VOLUME_HIDE);
   ChartSetInteger(id,CHART_SHIFT,InpChartShift);
   if(InpChartShift)
      ChartSetDouble(id,CHART_SHIFT_SIZE,12.0);
   ChartSetInteger(id,CHART_SHOW_PERIOD_SEP,false);
   ChartSetInteger(id,CHART_SHOW_OHLC,true);
   ChartSetInteger(id,CHART_SHOW_BID_LINE,true);
   ChartRedraw(id);
  }
//+------------------------------------------------------------------+
