//+------------------------------------------------------------------+
//|                                            XAU_ADRVolatility.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Average daily range targets with exhaustion zones (dynamic or     |
//| from the daily open), a squeeze / expansion volatility regime     |
//| background and an ADR / ATR read-out card.                        |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU ADR & Volatility - ADR targets, exhaustion zones, squeeze/expansion regime, info card."
#property description "Smooth anti-aliased rendering."
#property indicator_chart_window
#property indicator_buffers 15
#property indicator_plots   4

#property indicator_label1  "ADR high target"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "ADR high zone edge"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "ADR low target"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "ADR low zone edge"
#property indicator_type4   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

enum ENUM_XAU_ADR_MODE
  {
   XAU_ADR_DYNAMIC=0,  // Dynamic (from day high / low)
   XAU_ADR_FROM_OPEN=1 // From open (open +/- ADR/2)
  };

input group "ADR"
input int               InpAdrLen     = 14;    // ADR length (days)
input ENUM_XAU_ADR_MODE InpProjection = XAU_ADR_DYNAMIC; // ADR target mode
input double            InpZonePct    = 15.0;  // Exhaustion zone depth (% of ADR)
input group "Volatility"
input int               InpAtrLen     = 14;    // ATR length
input bool              InpShowRegime = true;  // Volatility regime background
input bool              InpShowPanel  = true;  // Show ADR info card
input bool              InpShowTags   = true;  // ADR target price tags
input group "Time"
input ENUM_XAU_DAY_ROLL InpDayRoll    = XAU_ROLL_NY17; // Trading day starts at
input double            InpServerGMT  = 99;    // Server GMT offset, hours (99 = auto-detect)
input ENUM_XAU_DST      InpServerDST  = XAU_DST_US; // Server daylight-saving rule
input group "Style"
input ENUM_XAU_THEME    InpTheme      = XAU_THEME_MIDNIGHT; // Colour theme

double BufHi[],BufHiIn[],BufLo[],BufLoIn[];
double BufKey[],BufDHigh[],BufDLow[],BufDOpen[],BufOrd[],BufAtr[],BufKcEma[],BufAtr20[],BufRegime[],BufRank[],BufAdr[];

XauTheme   g_t;
CXauClock  g_clock;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;
double     g_ranges[];   // completed day ranges, by day ordinal - 1
uint       g_bg[];

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   g_clock.Init(InpServerGMT,InpServerDST);
   SetIndexBuffer(0,BufHi,INDICATOR_DATA);
   SetIndexBuffer(1,BufHiIn,INDICATOR_DATA);
   SetIndexBuffer(2,BufLo,INDICATOR_DATA);
   SetIndexBuffer(3,BufLoIn,INDICATOR_DATA);
   SetIndexBuffer(4,BufKey,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,BufDHigh,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,BufDLow,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,BufDOpen,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,BufOrd,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,BufAtr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,BufKcEma,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,BufAtr20,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,BufRegime,INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,BufRank,INDICATOR_CALCULATIONS);
   SetIndexBuffer(14,BufAdr,INDICATOR_CALCULATIONS);
   for(int p=0; p<4; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU ADR & Volatility");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   g_gate.Init(150);
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
   if(prev_calculated==0)
      ArrayResize(g_ranges,0);
   bool intraday=PeriodSeconds()<86400;
   for(int i=start; i<rates_total; i++)
     {
      long key=g_clock.DayKey(time[i],InpDayRoll);
      BufKey[i]=(double)key;
      bool new_day=(i>0 && key!=(long)BufKey[i-1]);
      int ord=(i>0 ? (int)BufOrd[i-1] : 0);
      if(new_day)
        {
         // the first, partial day is skipped; writing by ordinal keeps live ticks idempotent
         if(ord>=1)
           {
            if(ArraySize(g_ranges)<ord)
               ArrayResize(g_ranges,ord,256);
            g_ranges[ord-1]=BufDHigh[i-1]-BufDLow[i-1];
           }
         ord++;
         BufDHigh[i]=high[i];
         BufDLow[i]=low[i];
         BufDOpen[i]=open[i];
        }
      else
        {
         BufDHigh[i]=XMax(i>0 ? BufDHigh[i-1] : EMPTY_VALUE,high[i]);
         BufDLow[i]=XMin(i>0 ? BufDLow[i-1] : EMPTY_VALUE,low[i]);
         BufDOpen[i]=(i>0 ? BufDOpen[i-1] : EMPTY_VALUE);
        }
      BufOrd[i]=ord;

      //--- ADR over the completed days before this one
      double adr=EMPTY_VALUE;
      int done=ord-1;
      if(done>0 && ArraySize(g_ranges)>=done)
        {
         int take=MathMin(InpAdrLen,done);
         double sum=0.0;
         for(int j=done-take; j<done; j++)
            sum+=g_ranges[j];
         adr=sum/take;
        }
      BufAdr[i]=adr;

      //--- ATR, its percent rank, Bollinger vs Keltner squeeze
      double tr=XTrueRange(high[i],low[i],i>0 ? close[i-1] : EMPTY_VALUE);
      BufAtr[i]=XRmaStep(i>0 ? BufAtr[i-1] : EMPTY_VALUE,tr,InpAtrLen);
      BufAtr20[i]=XRmaStep(i>0 ? BufAtr20[i-1] : EMPTY_VALUE,tr,20);
      BufKcEma[i]=XEmaStep(i>0 ? BufKcEma[i-1] : EMPTY_VALUE,close[i],20);
      int cnt=0,avail=0;
      for(int j=1; j<=100 && i-j>=0; j++)
        {
         avail++;
         if(BufAtr[i-j]<=BufAtr[i])
            cnt++;
        }
      BufRank[i]=(avail>0 ? 100.0*cnt/avail : 50.0);
      int regime=0;
      if(i>=19)
        {
         double sum=0.0,sq=0.0;
         for(int j=i-19; j<=i; j++)
           {
            sum+=close[j];
            sq+=close[j]*close[j];
           }
         double mean=sum/20.0;
         double sd=MathSqrt(MathMax(sq/20.0-mean*mean,0.0));
         double bb_up=mean+2.0*sd,bb_lo=mean-2.0*sd;
         bool squeeze=(bb_up<BufKcEma[i]+1.5*BufAtr20[i]) && (bb_lo>BufKcEma[i]-1.5*BufAtr20[i]);
         if(squeeze)
            regime=1;
         else
            if(BufRank[i]>=80.0)
               regime=2;
        }
      BufRegime[i]=regime;

      //--- targets
      double hi=EMPTY_VALUE,lo=EMPTY_VALUE,depth=0.0;
      bool valid=(ord>=1 && intraday && XOk(adr));
      if(valid)
        {
         if(InpProjection==XAU_ADR_DYNAMIC)
           {
            hi=BufDLow[i]+adr;
            lo=BufDHigh[i]-adr;
           }
         else
           {
            hi=BufDOpen[i]+adr*0.5;
            lo=BufDOpen[i]-adr*0.5;
           }
         depth=adr*InpZonePct/100.0;
        }
      bool show=(valid && !new_day);
      BufHi[i]=(show ? hi : EMPTY_VALUE);
      BufHiIn[i]=(show ? hi-depth : EMPTY_VALUE);
      BufLo[i]=(show ? lo : EMPTY_VALUE);
      BufLoIn[i]=(show ? lo+depth : EMPTY_VALUE);
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
void DrawPanel()
  {
   int last=g_total-1;
   double adr=BufAdr[last];
   if(!XOk(adr) || adr<=0.0 || PeriodSeconds()>=86400)
      return;
   double k=g_front.K();
   double used=BufDHigh[last]-BufDLow[last];
   double pct=100.0*used/adr;
   double rank=BufRank[last];
   string regime="NORMAL";
   uint regime_rgb=g_t.neutral;
   if(rank>=80.0)
     {
      regime="EXPANDING";
      regime_rgb=g_t.orange;
     }
   else
      if(rank<=20.0)
        {
         regime="COMPRESSED";
         regime_rgb=g_t.violet;
        }

   double w=236.0*k,h=86.0*k,pad=12.0*k;
   double x=g_map.width-w-14.0*k;
   double y=g_map.height-h-14.0*k;
   g_front.Card(x,y,w,h,XRgb(g_t.panel,0.92),XRgb(g_t.border,1.0),XRgb(g_t.gold,0.9));

   g_front.SetFont(XAU_FONT,7.5,FW_SEMIBOLD);
   g_front.Text(x+pad,y+pad,"ADR ("+IntegerToString(InpAdrLen)+"D)",XRgb(g_t.muted,1.0),TA_LEFT|TA_TOP);
   g_front.SetFont(XAU_FONT,10.0,FW_BOLD);
   g_front.Text(x+w-pad,y+pad-2.0*k,"$"+DoubleToString(adr,2),XRgb(g_t.gold,1.0),TA_RIGHT|TA_TOP);

   uint fill=(pct>=100.0 ? g_t.bear : (pct>=70.0 ? g_t.gold : g_t.bull));
   double by=y+34.0*k;
   g_front.Bar(x+pad,by,w-2.0*pad,6.0*k,pct/100.0,XRgb(g_t.border,1.0),XRgb(fill,1.0));
   g_front.SetFont(XAU_FONT,7.5,FW_NORMAL);
   g_front.Text(x+pad,by+10.0*k,"Today $"+DoubleToString(used,2),XRgb(g_t.text,0.95),TA_LEFT|TA_TOP);
   g_front.SetFont(XAU_FONT,7.5,FW_SEMIBOLD);
   g_front.Text(x+w-pad,by+10.0*k,DoubleToString(pct,0)+"% used",XRgb(fill,1.0),TA_RIGHT|TA_TOP);

   g_front.SetFont(XAU_FONT,7.5,FW_NORMAL);
   g_front.Text(x+pad,y+h-pad,"ATR("+IntegerToString(InpAtrLen)+") $"+XNum(BufAtr[last],2),XRgb(g_t.text,0.95),
                TA_LEFT|TA_BOTTOM);
   double cw=0.0,ch=0.0;
   g_front.PillSize(regime,7.0,cw,ch);
   g_front.Pill(x+w-pad-cw*0.5,y+h-pad-ch*0.5,regime,XRgb(regime_rgb,0.20),XRgb(regime_rgb,1.0),XA_CENTER,7.0);
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
   if(!XBegin(g_back,"XAU.ADR.back",g_map,true) || !XBegin(g_front,"XAU.ADR.front",g_map,false))
      return;
   int last=g_total-1;
   double k=g_front.K();

   if(InpShowRegime)
     {
      if(ArraySize(g_bg)!=g_total)
         ArrayResize(g_bg,g_total);
      int from=g_map.From(),to=g_map.To();
      uint squeeze=XRgb(g_t.violet,0.07),expansion=XRgb(g_t.orange,0.05);
      for(int i=from; i<=to; i++)
         g_bg[i]=(BufRegime[i]==1.0 ? squeeze : (BufRegime[i]==2.0 ? expansion : 0));
      XBackground(g_back,g_map,g_bg);
     }

   XFillSeries(g_back,g_map,BufHi,BufHiIn,XRgb(g_t.bear,0.16),0.25);
   XFillSeries(g_back,g_map,BufLo,BufLoIn,XRgb(g_t.bull,0.16),0.25);
   XStrokeSeries(g_front,g_map,BufHi,XRgb(g_t.bear,0.9),1.0,5.0,4.0);
   XStrokeSeries(g_front,g_map,BufLo,XRgb(g_t.bull,0.9),1.0,5.0,4.0);

   if(InpShowTags && XOk(BufHi[last]) && XOk(BufLo[last]))
     {
      double x=g_map.X(last)+MathMax(3.0*g_map.spacing,10.0*k);
      XauTag tags[];
      int n=0;
      XAddTag(tags,n,g_map.Y(BufHi[last]),"ADR H "+DoubleToString(BufHi[last],2),XRgb(g_t.bear,0.9),XRgb(g_t.ink,1.0));
      XAddTag(tags,n,g_map.Y(BufLo[last]),"ADR L "+DoubleToString(BufLo[last],2),XRgb(g_t.bull,0.9),XRgb(g_t.ink,1.0));
      XDrawTags(g_front,tags,n,x,7.5);
     }

   if(InpShowPanel)
      DrawPanel();

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
