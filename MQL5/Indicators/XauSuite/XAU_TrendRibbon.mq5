//+------------------------------------------------------------------+
//|                                              XAU_TrendRibbon.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| EMA trend ribbon with an ADX-weighted gradient cloud, 200 EMA     |
//| baseline, ATR trailing stop (Supertrend), BUY / SELL flip labels  |
//| and regime-coloured candles. Lines and fills are drawn on an      |
//| anti-aliased canvas; values stay in the Data Window.              |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU Trend Ribbon - EMA cloud, baseline, ATR trail, flips and regime candles."
#property description "Smooth anti-aliased rendering."
#property indicator_chart_window
#property indicator_buffers 20
#property indicator_plots   9

#property indicator_label1  "Regime open;Regime high;Regime low;Regime close"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_label2  "Fast EMA"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Slow EMA"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Baseline EMA"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "ATR trail"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "Trail direction"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "ADX"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "BUY flip"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "SELL flip"
#property indicator_type9   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

input group "Trend ribbon"
input int            InpFastLen       = 21;    // Fast EMA
input int            InpSlowLen       = 55;    // Slow EMA
input int            InpBaseLen       = 200;   // Baseline EMA
input group "ATR trailing stop"
input int            InpStAtrLen      = 10;    // Trail ATR length
input double         InpStFactor      = 3.0;   // Trail ATR factor
input group "Trend strength"
input int            InpAdxLen        = 14;    // ADX length
input double         InpAdxThreshold  = 20.0;  // ADX trend threshold
input group "Signals & display"
input bool           InpUseBaseFilter = true;  // Signals only with baseline trend
input bool           InpShowTrail     = true;  // Show ATR trailing stop
input bool           InpShowSignals   = true;  // Show BUY / SELL flips
input bool           InpShowBarColors = true;  // Colour candles by regime
input bool           InpGlow          = true;  // Soft glow on the baseline
input group "Style"
input ENUM_XAU_THEME InpTheme         = XAU_THEME_MIDNIGHT; // Colour theme

//--- plot buffers
double BufCO[],BufCH[],BufCL[],BufCC[],BufCColor[];
double BufFast[],BufSlow[],BufBase[],BufTrail[],BufDir[],BufAdx[],BufBuy[],BufSell[];
//--- calculation buffers
double BufAtr[],BufStLo[],BufStHi[],BufTrr[],BufPdm[],BufMdm[],BufMid[];

XauTheme   g_t;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;
uint       g_cFast[],g_cSlow[];
double     g_up[],g_dn[];

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   SetIndexBuffer(0,BufCO,INDICATOR_DATA);
   SetIndexBuffer(1,BufCH,INDICATOR_DATA);
   SetIndexBuffer(2,BufCL,INDICATOR_DATA);
   SetIndexBuffer(3,BufCC,INDICATOR_DATA);
   SetIndexBuffer(4,BufCColor,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5,BufFast,INDICATOR_DATA);
   SetIndexBuffer(6,BufSlow,INDICATOR_DATA);
   SetIndexBuffer(7,BufBase,INDICATOR_DATA);
   SetIndexBuffer(8,BufTrail,INDICATOR_DATA);
   SetIndexBuffer(9,BufDir,INDICATOR_DATA);
   SetIndexBuffer(10,BufAdx,INDICATOR_DATA);
   SetIndexBuffer(11,BufBuy,INDICATOR_DATA);
   SetIndexBuffer(12,BufSell,INDICATOR_DATA);
   SetIndexBuffer(13,BufAtr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(14,BufStLo,INDICATOR_CALCULATIONS);
   SetIndexBuffer(15,BufStHi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(16,BufTrr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(17,BufPdm,INDICATOR_CALCULATIONS);
   SetIndexBuffer(18,BufMdm,INDICATOR_CALCULATIONS);
   SetIndexBuffer(19,BufMid,INDICATOR_CALCULATIONS);
   for(int p=0; p<9; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   //--- regime candle palette: strong bull, bull, neutral, bear, strong bear
   PlotIndexSetInteger(0,PLOT_COLOR_INDEXES,5);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,0,XClr(g_t.bull));
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,1,XClr(XLerp(XRgb(g_t.bull,1.0),XRgb(g_t.neutral,1.0),0.45)&0xFFFFFF));
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,2,XClr(g_t.neutral));
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,3,XClr(XLerp(XRgb(g_t.bear,1.0),XRgb(g_t.neutral,1.0),0.45)&0xFFFFFF));
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,4,XClr(g_t.bear));
   PlotIndexSetInteger(0,PLOT_SHOW_DATA,false);

   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Trend Ribbon");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   g_gate.Init(120);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   g_gate.Stop();
   g_back.Destroy();
   g_front.Destroy();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<3)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   for(int i=start; i<rates_total; i++)
     {
      double c1=(i>0 ? close[i-1] : EMPTY_VALUE);
      //--- EMAs
      BufFast[i]=XEmaStep(i>0 ? BufFast[i-1] : EMPTY_VALUE,close[i],InpFastLen);
      BufSlow[i]=XEmaStep(i>0 ? BufSlow[i-1] : EMPTY_VALUE,close[i],InpSlowLen);
      BufBase[i]=XEmaStep(i>0 ? BufBase[i-1] : EMPTY_VALUE,close[i],InpBaseLen);
      BufMid[i]=(open[i]+close[i])*0.5;

      //--- Supertrend (TradingView ta.supertrend semantics: dir -1 = up)
      double tr=XTrueRange(high[i],low[i],c1);
      BufAtr[i]=XRmaStep(i>0 ? BufAtr[i-1] : EMPTY_VALUE,tr,InpStAtrLen);
      double src=(high[i]+low[i])*0.5;
      double up=src+InpStFactor*BufAtr[i];
      double lo=src-InpStFactor*BufAtr[i];
      int dir=1;
      if(i>0)
        {
         double plo=BufStLo[i-1];
         double phi=BufStHi[i-1];
         lo=((lo>plo || close[i-1]<plo) ? lo : plo);
         up=((up<phi || close[i-1]>phi) ? up : phi);
         if(BufTrail[i-1]==phi)
            dir=(close[i]>up ? -1 : 1);
         else
            dir=(close[i]<lo ? 1 : -1);
        }
      BufStLo[i]=lo;
      BufStHi[i]=up;
      BufDir[i]=dir;
      BufTrail[i]=(dir<0 ? lo : up);

      //--- ADX (Wilder / TradingView ta.dmi)
      double upm=(i>0 ? high[i]-high[i-1] : 0.0);
      double dnm=(i>0 ? low[i-1]-low[i] : 0.0);
      double pdm=((upm>dnm && upm>0.0) ? upm : 0.0);
      double mdm=((dnm>upm && dnm>0.0) ? dnm : 0.0);
      BufTrr[i]=XRmaStep(i>0 ? BufTrr[i-1] : EMPTY_VALUE,tr,InpAdxLen);
      BufPdm[i]=XRmaStep(i>0 ? BufPdm[i-1] : EMPTY_VALUE,pdm,InpAdxLen);
      BufMdm[i]=XRmaStep(i>0 ? BufMdm[i-1] : EMPTY_VALUE,mdm,InpAdxLen);
      double plus=(BufTrr[i]>0.0 ? 100.0*BufPdm[i]/BufTrr[i] : 0.0);
      double minus=(BufTrr[i]>0.0 ? 100.0*BufMdm[i]/BufTrr[i] : 0.0);
      double sum=plus+minus;
      double dx=100.0*MathAbs(plus-minus)/(sum==0.0 ? 1.0 : sum);
      BufAdx[i]=XRmaStep(i>0 ? BufAdx[i-1] : EMPTY_VALUE,dx,InpAdxLen);

      //--- regime
      bool trend_up=(BufFast[i]>BufSlow[i]);
      bool strong=(BufAdx[i]>=InpAdxThreshold);
      int regime=0;
      if(trend_up)
        {
         if(close[i]>BufFast[i] && strong)
            regime=2;
         else
            if(close[i]>=BufSlow[i])
               regime=1;
        }
      else
        {
         if(close[i]<BufFast[i] && strong)
            regime=-2;
         else
            if(close[i]<=BufSlow[i])
               regime=-1;
        }

      //--- flips
      bool flip_up=(i>0 && BufDir[i]<0 && BufDir[i-1]>0);
      bool flip_dn=(i>0 && BufDir[i]>0 && BufDir[i-1]<0);
      if(InpUseBaseFilter)
        {
         flip_up=flip_up && close[i]>BufBase[i];
         flip_dn=flip_dn && close[i]<BufBase[i];
        }
      BufBuy[i]=(InpShowSignals && flip_up ? low[i] : EMPTY_VALUE);
      BufSell[i]=(InpShowSignals && flip_dn ? high[i] : EMPTY_VALUE);

      //--- regime candles
      if(InpShowBarColors)
        {
         BufCO[i]=open[i];
         BufCH[i]=high[i];
         BufCL[i]=low[i];
         BufCC[i]=close[i];
         BufCColor[i]=(regime==2 ? 0 : regime==1 ? 1 : regime==-1 ? 3 : regime==-2 ? 4 : 2);
        }
      else
        {
         BufCO[i]=EMPTY_VALUE;
         BufCH[i]=EMPTY_VALUE;
         BufCL[i]=EMPTY_VALUE;
         BufCC[i]=EMPTY_VALUE;
         BufCColor[i]=2;
        }
     }
   g_total=rates_total;
   if(g_gate.Request(prev_calculated!=rates_total))
      Render();
   return(rates_total);
  }

void OnTimer()
  {
   if(g_gate.Pending())
      Render();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      Render();
  }

//+------------------------------------------------------------------+
uint CloudColor(const int i)
  {
   double a=0.06;
   if(XOk(BufAdx[i]))
      a=0.06+0.24*XClamp(BufAdx[i]/50.0,0.0,1.0);
   return(XRgb(BufFast[i]>BufSlow[i] ? g_t.bull : g_t.bear,a));
  }

void Render()
  {
   if(g_total<3)
      return;
   int sub=ChartWindowFind();
   if(sub<0)
      sub=0;
   if(!g_map.Update(sub,g_total))
      return;
   if(!XBegin(g_back,"XAU.TrendRibbon.back",g_map,true) || !XBegin(g_front,"XAU.TrendRibbon.front",g_map,false))
      return;
   if(ArraySize(g_cFast)!=g_total)
     {
      ArrayResize(g_cFast,g_total);
      ArrayResize(g_cSlow,g_total);
      ArrayResize(g_up,g_total);
      ArrayResize(g_dn,g_total);
     }
   int from=g_map.From(),to=g_map.To();

   //--- cloud, split exactly where the EMAs cross
   for(int i=from+1; i<=to; i++)
     {
      double fa=BufFast[i-1],sa=BufSlow[i-1],fb=BufFast[i],sb=BufSlow[i];
      if(!XOk(fa) || !XOk(sa) || !XOk(fb) || !XOk(sb))
         continue;
      double xa=g_map.X(i-1),xb=g_map.X(i);
      double da=fa-sa,db=fb-sb;
      if((da>0.0)==(db>0.0) || da==0.0 || db==0.0)
         g_back.Band(xa,g_map.Y(fa),g_map.Y(sa),xb,g_map.Y(fb),g_map.Y(sb),CloudColor(i),0.35);
      else
        {
         double t=da/(da-db);
         double xm=xa+t*(xb-xa);
         double ym=g_map.Y(fa+t*(fb-fa));
         g_back.Band(xa,g_map.Y(fa),g_map.Y(sa),xm,ym,ym,CloudColor(i-1),0.35);
         g_back.Band(xm,ym,ym,xb,g_map.Y(fb),g_map.Y(sb),CloudColor(i),0.35);
        }
     }

   //--- trailing stop: gradient fill from the trail towards the candle bodies
   if(InpShowTrail)
     {
      for(int i=from+1; i<=to; i++)
        {
         if(BufDir[i]!=BufDir[i-1] || !XOk(BufTrail[i-1]) || !XOk(BufTrail[i]))
            continue;
         uint c=XRgb(BufDir[i]<0 ? g_t.bull : g_t.bear,0.16);
         g_back.Band(g_map.X(i-1),g_map.Y(BufTrail[i-1]),g_map.Y(BufMid[i-1]),
                     g_map.X(i),g_map.Y(BufTrail[i]),g_map.Y(BufMid[i]),c,0.0);
        }
     }

   //--- lines
   for(int i=from; i<=to; i++)
     {
      bool up=(BufFast[i]>BufSlow[i]);
      g_cFast[i]=XRgb(up ? g_t.bull : g_t.bear,1.0);
      g_cSlow[i]=XRgb(up ? g_t.bull : g_t.bear,0.55);
      g_up[i]=(InpShowTrail && BufDir[i]<0 ? BufTrail[i] : EMPTY_VALUE);
      g_dn[i]=(InpShowTrail && BufDir[i]>0 ? BufTrail[i] : EMPTY_VALUE);
     }
   XStrokeSeries(g_front,g_map,BufBase,XRgb(g_t.gold,1.0),2.0,0.0,0.0,InpGlow ? 0.22 : 0.0);
   XStrokeSeriesColored(g_front,g_map,BufSlow,g_cSlow,1.0);
   XStrokeSeriesColored(g_front,g_map,BufFast,g_cFast,1.6);
   if(InpShowTrail)
     {
      XStrokeSeries(g_front,g_map,g_up,XRgb(g_t.bull,1.0),2.0);
      XStrokeSeries(g_front,g_map,g_dn,XRgb(g_t.bear,1.0),2.0);
     }

   //--- flip labels
   if(InpShowSignals)
     {
      for(int i=from; i<=to; i++)
        {
         if(XOk(BufBuy[i]))
            g_front.Pill(g_map.X(i),g_map.Y(BufBuy[i]),"BUY",XRgb(g_t.bull,1.0),XRgb(g_t.ink,1.0),XA_BELOW,8.0);
         if(XOk(BufSell[i]))
            g_front.Pill(g_map.X(i),g_map.Y(BufSell[i]),"SELL",XRgb(g_t.bear,1.0),XRgb(g_t.ink,1.0),XA_ABOVE,8.0);
        }
     }

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
