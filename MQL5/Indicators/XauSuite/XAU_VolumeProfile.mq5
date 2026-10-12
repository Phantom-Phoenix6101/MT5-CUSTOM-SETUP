//+------------------------------------------------------------------+
//|                                            XAU_VolumeProfile.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Volume profile over a fixed lookback or the visible range, split  |
//| into buying / selling volume, with POC, value area (VAH / VAL)    |
//| and the previous trading day's POC / VAH / VAL as step lines.     |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU Volume Profile - split buy/sell profile, POC, value area, previous day levels."
#property description "Smooth anti-aliased rendering."
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   3

#property indicator_label1  "Prev day POC"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Prev day VAH"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Prev day VAL"
#property indicator_type3   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

enum ENUM_XAU_PROFILE_RANGE
  {
   XAU_RANGE_LOOKBACK=0, // Fixed lookback (bars)
   XAU_RANGE_VISIBLE=1   // Visible range
  };

enum ENUM_XAU_PLACEMENT
  {
   XAU_PLACE_RIGHT=0, // Right
   XAU_PLACE_LEFT=1   // Left
  };

input group "Profile"
input ENUM_XAU_PROFILE_RANGE InpRange     = XAU_RANGE_LOOKBACK; // Profile range
input int                    InpLookback  = 300;   // Profile lookback (bars)
input int                    InpRows      = 24;    // Profile rows
input double                 InpVaPct     = 70.0;  // Value area (%)
input double                 InpWidthPct  = 30.0;  // Profile width (% of range)
input ENUM_XAU_PLACEMENT     InpPlacement = XAU_PLACE_RIGHT; // Profile anchored to
input bool                   InpSplit     = true;  // Split buy / sell volume
input bool                   InpShowLevels= true;  // Show POC / VAH / VAL lines
input ENUM_APPLIED_VOLUME    InpVolume    = VOLUME_TICK; // Volume
input group "Previous day"
input bool                   InpShowPrevDay = true; // Previous day POC / VAH / VAL
input ENUM_XAU_DAY_ROLL      InpDayRoll   = XAU_ROLL_NY17; // Trading day starts at
input double                 InpServerGMT = 99;    // Server GMT offset, hours (99 = auto-detect)
input ENUM_XAU_DST           InpServerDST = XAU_DST_US; // Server daylight-saving rule
input group "Style"
input ENUM_XAU_THEME         InpTheme     = XAU_THEME_AUTO; // Colour theme

double BufPoc[],BufVah[],BufVal[];
double BufKey[],BufDayStart[],BufPocRaw[],BufVahRaw[],BufValRaw[];

XauTheme   g_t;
CXauClock  g_clock;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;
double     g_o[],g_h[],g_l[],g_c[],g_v[];
//--- last built profile
double     g_up[],g_dn[];
double     g_range_lo=0.0,g_row=0.0;
int        g_poc=0,g_va_lo=0,g_va_hi=0;

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   g_clock.Init(InpServerGMT,InpServerDST);
   SetIndexBuffer(0,BufPoc,INDICATOR_DATA);
   SetIndexBuffer(1,BufVah,INDICATOR_DATA);
   SetIndexBuffer(2,BufVal,INDICATOR_DATA);
   SetIndexBuffer(3,BufKey,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,BufDayStart,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,BufPocRaw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,BufVahRaw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,BufValRaw,INDICATOR_CALCULATIONS);
   for(int p=0; p<3; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   ArrayResize(g_up,MathMax(InpRows,2));
   ArrayResize(g_dn,MathMax(InpRows,2));
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Volume Profile");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   g_gate.Init(200);
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
//| Build a profile over bars [a, b]. Each bar's volume is spread     |
//| over the rows its high-low range covers; no volume = equal weight |
//+------------------------------------------------------------------+
bool Build(const int a,const int b,const int rows,const double va_pct)
  {
   if(b<a || rows<2)
      return(false);
   double lo=EMPTY_VALUE,hi=EMPTY_VALUE,total_vol=0.0;
   for(int k=a; k<=b; k++)
     {
      hi=XMax(hi,g_h[k]);
      lo=XMin(lo,g_l[k]);
      if(g_v[k]>0.0)
         total_vol+=g_v[k];
     }
   if(!XOk(lo) || !XOk(hi) || hi<=lo)
      return(false);
   double row=(hi-lo)/rows;
   for(int r=0; r<rows; r++)
     {
      g_up[r]=0.0;
      g_dn[r]=0.0;
     }
   for(int k=a; k<=b; k++)
     {
      double h=g_h[k],l=g_l[k];
      double v=(total_vol>0.0 ? g_v[k] : 1.0);
      if(v<=0.0)
         continue;
      int r0=(int)MathFloor((l-lo)/row);
      int r1=(int)MathFloor((h-lo)/row);
      r0=(int)XClamp(r0,0,rows-1);
      r1=(int)XClamp(r1,0,rows-1);
      double span=h-l;
      bool up=(g_c[k]>=g_o[k]);
      for(int r=r0; r<=r1; r++)
        {
         double share=1.0;
         if(span>0.0)
           {
            double row_lo=lo+r*row;
            double top=MathMin(h,row_lo+row);
            double bot=MathMax(l,row_lo);
            share=MathMax((top-bot)/span,0.0);
           }
         else
            if(r1>r0)
               share=1.0/(r1-r0+1);
         if(up)
            g_up[r]+=v*share;
         else
            g_dn[r]+=v*share;
        }
     }
   int poc=0;
   double total=0.0;
   for(int r=0; r<rows; r++)
     {
      double t=g_up[r]+g_dn[r];
      total+=t;
      if(t>g_up[poc]+g_dn[poc])
         poc=r;
     }
   if(total<=0.0)
      return(false);
   int va_lo=poc,va_hi=poc;
   double acc=g_up[poc]+g_dn[poc];
   double target=total*va_pct/100.0;
   while(acc<target && (va_lo>0 || va_hi<rows-1))
     {
      double below=(va_lo>0 ? g_up[va_lo-1]+g_dn[va_lo-1] : -1.0);
      double above=(va_hi<rows-1 ? g_up[va_hi+1]+g_dn[va_hi+1] : -1.0);
      if(above>=below)
        {
         va_hi++;
         acc+=above;
        }
      else
        {
         va_lo--;
         acc+=below;
        }
     }
   g_range_lo=lo;
   g_row=row;
   g_poc=poc;
   g_va_lo=va_lo;
   g_va_hi=va_hi;
   return(true);
  }

double PocPrice() { return(g_range_lo+(g_poc+0.5)*g_row); }
double VahPrice() { return(g_range_lo+(g_va_hi+1)*g_row); }
double ValPrice() { return(g_range_lo+g_va_lo*g_row); }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<3)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   ArrayResize(g_o,rates_total);
   ArrayResize(g_h,rates_total);
   ArrayResize(g_l,rates_total);
   ArrayResize(g_c,rates_total);
   ArrayResize(g_v,rates_total);
   int rows=MathMax(InpRows,2);
   bool intraday=PeriodSeconds()<86400;
   for(int i=start; i<rates_total; i++)
     {
      g_o[i]=open[i];
      g_h[i]=high[i];
      g_l[i]=low[i];
      g_c[i]=close[i];
      g_v[i]=(double)(InpVolume==VOLUME_REAL ? volume[i] : tick_volume[i]);

      long key=g_clock.DayKey(time[i],InpDayRoll);
      BufKey[i]=(double)key;
      bool new_day=(i>0 && key!=(long)BufKey[i-1]);
      BufDayStart[i]=(i>0 ? BufDayStart[i-1] : -1.0);
      BufPocRaw[i]=(i>0 ? BufPocRaw[i-1] : EMPTY_VALUE);
      BufVahRaw[i]=(i>0 ? BufVahRaw[i-1] : EMPTY_VALUE);
      BufValRaw[i]=(i>0 ? BufValRaw[i-1] : EMPTY_VALUE);
      if(new_day)
        {
         int ds=(int)BufDayStart[i-1];
         if(InpShowPrevDay && ds>=0 && i-ds>1 && intraday && Build(ds,i-1,rows,InpVaPct))
           {
            BufPocRaw[i]=PocPrice();
            BufVahRaw[i]=VahPrice();
            BufValRaw[i]=ValPrice();
           }
         BufDayStart[i]=i;
        }
      bool hide=(new_day || !InpShowPrevDay);
      BufPoc[i]=(hide ? EMPTY_VALUE : BufPocRaw[i]);
      BufVah[i]=(hide ? EMPTY_VALUE : BufVahRaw[i]);
      BufVal[i]=(hide ? EMPTY_VALUE : BufValRaw[i]);
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
void Render()
  {
   if(g_total<3)
      return;
   int sub=ChartWindowFind();
   if(sub<0)
      sub=0;
   if(!g_map.Update(sub,g_total))
      return;
   if(!XBegin(g_back,"XAU.VolumeProfile.back",g_map,true) || !XBegin(g_front,"XAU.VolumeProfile.front",g_map,false))
      return;
   double k=g_front.K();
   int last=g_total-1;

   //--- previous day levels
   XStrokeSeries(g_front,g_map,BufPoc,XRgb(g_t.gold,0.90),2.0);
   XStrokeSeries(g_front,g_map,BufVah,XRgb(g_t.blue,0.80),1.0,5.0,4.0);
   XStrokeSeries(g_front,g_map,BufVal,XRgb(g_t.blue,0.80),1.0,5.0,4.0);

   //--- profile range
   int a,b;
   if(InpRange==XAU_RANGE_VISIBLE)
     {
      a=MathMax(0,g_map.idx_first);
      b=MathMin(last,g_map.idx_first+g_map.visible-1);
     }
   else
     {
      b=last;
      a=MathMax(0,last-InpLookback+1);
     }
   int rows=MathMax(InpRows,2);
   if(b-a>=2 && Build(a,b,rows,InpVaPct))
     {
      double half=g_map.spacing*0.5;
      double xl=g_map.X(a)-half,xr=g_map.X(b)+half;
      double full_w=(xr-xl)*InpWidthPct/100.0;
      bool right=(InpPlacement==XAU_PLACE_RIGHT);
      double anchor=(right ? xr : xl);
      double dir=(right ? -1.0 : 1.0);
      double max_total=0.0;
      for(int r=0; r<rows; r++)
         max_total=MathMax(max_total,g_up[r]+g_dn[r]);

      //--- faint value-area backdrop across the range
      g_back.FillRect(xl,g_map.Y(VahPrice()),xr,g_map.Y(ValPrice()),XRgb(g_t.blue,0.035));

      if(max_total>0.0)
        {
         for(int r=0; r<rows; r++)
           {
            double row_lo=g_range_lo+r*g_row;
            double yt=g_map.Y(row_lo+g_row*0.92);
            double yb=g_map.Y(row_lo+g_row*0.08);
            double rad=MathMin(2.0*k,(yb-yt)*0.5);
            bool in_va=(r>=g_va_lo && r<=g_va_hi);
            bool is_poc=(r==g_poc);
            double up_w=full_w*g_up[r]/max_total;
            double dn_w=full_w*g_dn[r]/max_total;
            if(InpSplit)
              {
               uint cu=(is_poc ? XRgb(g_t.gold,0.85) : XRgb(g_t.bull,in_va ? 0.55 : 0.22));
               uint cd=(is_poc ? XRgb(g_t.gold,0.65) : XRgb(g_t.bear,in_va ? 0.55 : 0.22));
               double x1=anchor,x2=anchor+dir*up_w,x3=anchor+dir*(up_w+dn_w);
               if(up_w>0.0)
                  g_back.RoundRect(MathMin(x1,x2),yt,MathMax(x1,x2),yb,rad,cu);
               if(dn_w>0.0)
                  g_back.RoundRect(MathMin(x2,x3),yt,MathMax(x2,x3),yb,rad,cd);
              }
            else
              {
               uint c=(is_poc ? XRgb(g_t.gold,0.85) : in_va ? XRgb(g_t.blue,0.45) : XRgb(g_t.neutral,0.25));
               double x2=anchor+dir*(up_w+dn_w);
               if(up_w+dn_w>0.0)
                  g_back.RoundRect(MathMin(anchor,x2),yt,MathMax(anchor,x2),yb,rad,c);
              }
           }
        }

      if(InpShowLevels)
        {
         double poc=PocPrice(),vah=VahPrice(),val=ValPrice();
         g_front.Line(xl,g_map.Y(poc),xr,g_map.Y(poc),XRgb(g_t.gold,0.95),2.0);
         g_front.Line(xl,g_map.Y(vah),xr,g_map.Y(vah),XRgb(g_t.blue,0.85),1.0,5.0,4.0);
         g_front.Line(xl,g_map.Y(val),xr,g_map.Y(val),XRgb(g_t.blue,0.85),1.0,5.0,4.0);
         XauTag tags[];
         int n=0;
         XAddTag(tags,n,g_map.Y(poc),"POC "+DoubleToString(poc,2),XRgb(g_t.gold,1.0),XRgb(g_t.ink,1.0));
         XAddTag(tags,n,g_map.Y(vah),"VAH "+DoubleToString(vah,2),XRgb(g_t.blue,0.9),XRgb(0xFFFFFF,1.0));
         XAddTag(tags,n,g_map.Y(val),"VAL "+DoubleToString(val,2),XRgb(g_t.blue,0.9),XRgb(0xFFFFFF,1.0));
         XDrawTags(g_front,tags,n,xr+2.0*k,7.5);
        }
     }

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
