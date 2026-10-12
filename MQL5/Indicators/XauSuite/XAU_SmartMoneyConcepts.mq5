//+------------------------------------------------------------------+
//|                                       XAU_SmartMoneyConcepts.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Market structure (BOS / CHoCH), swing labels (HH / HL / LH / LL), |
//| order blocks, fair value gaps, equal highs / lows, liquidity      |
//| sweeps and premium / equilibrium / discount zones.                |
//| Structure is committed on closed bars only, so it never repaints. |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU Smart Money Concepts - BOS/CHoCH, order blocks, FVGs, liquidity, premium/discount."
#property description "Smooth anti-aliased rendering."
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   2

#property indicator_label1  "Sell-side sweep"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Buy-side sweep"
#property indicator_type2   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

input group "Structure"
input int            InpSwingLen     = 8;     // Swing length (bars each side)
input bool           InpShowStruct   = true;  // Show BOS / CHoCH
input int            InpStructCount  = 6;     // Structure breaks to keep
input bool           InpShowSwings   = true;  // Show HH / HL / LH / LL
input group "Zones"
input bool           InpShowOB       = true;  // Show order blocks
input int            InpObCount      = 3;     // Order blocks per side
input bool           InpShowFVG      = true;  // Show fair value gaps
input int            InpFvgCount     = 4;     // Fair value gaps per side
input double         InpFvgMinAtr    = 0.25;  // Min FVG size (x ATR)
input int            InpExtendBars   = 15;    // Extend active zones right (bars)
input group "Liquidity"
input bool           InpShowEq       = true;  // Show equal highs / lows (liquidity)
input double         InpEqThreshold  = 0.15;  // Equal high/low tolerance (x ATR)
input bool           InpShowSweeps   = true;  // Mark liquidity sweeps
input bool           InpShowZones    = true;  // Premium / discount zones
input group "Performance & style"
input int            InpMaxBars      = 5000;  // Bars to analyse
input ENUM_XAU_THEME InpTheme        = XAU_THEME_MIDNIGHT; // Colour theme

struct SmcZone
  {
   double            top;
   double            bottom;
   int               start;
   bool              bull;
   bool              active;
  };

struct SmcMark
  {
   double            level;
   int               i1;
   int               i2;
   string            text;
   bool              bull;
   bool              used;
  };

struct SmcSwing
  {
   double            price;
   int               idx;
   string            text;
   bool              high;
   bool              used;
  };

double BufSellSweep[],BufBuySweep[],BufAtr[];

XauTheme   g_t;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;

SmcZone  g_obs[];
SmcZone  g_fvgs[];
SmcMark  g_marks[];
SmcMark  g_eqs[];
SmcSwing g_swings[];
int      g_mark_next=0;
int      g_eq_next=0;
int      g_swing_next=0;
int      g_processed=-1;
double   g_sh_price=EMPTY_VALUE;
int      g_sh_idx=0;
bool     g_sh_broken=true;
bool     g_sh_swept=true;
double   g_sl_price=EMPTY_VALUE;
int      g_sl_idx=0;
bool     g_sl_broken=true;
bool     g_sl_swept=true;
int      g_trend=0;

//+------------------------------------------------------------------+
void ResetState()
  {
   ArrayResize(g_obs,2*MathMax(InpObCount,1));
   ArrayResize(g_fvgs,2*MathMax(InpFvgCount,1));
   ArrayResize(g_marks,MathMax(InpStructCount,1));
   ArrayResize(g_eqs,4);
   ArrayResize(g_swings,10);
   for(int i=0; i<ArraySize(g_obs); i++)
      g_obs[i].active=false;
   for(int i=0; i<ArraySize(g_fvgs); i++)
      g_fvgs[i].active=false;
   for(int i=0; i<ArraySize(g_marks); i++)
      g_marks[i].used=false;
   for(int i=0; i<ArraySize(g_eqs); i++)
      g_eqs[i].used=false;
   for(int i=0; i<ArraySize(g_swings); i++)
      g_swings[i].used=false;
   g_mark_next=0;
   g_eq_next=0;
   g_swing_next=0;
   g_processed=-1;
   g_sh_price=EMPTY_VALUE;
   g_sh_idx=0;
   g_sh_broken=true;
   g_sh_swept=true;
   g_sl_price=EMPTY_VALUE;
   g_sl_idx=0;
   g_sl_broken=true;
   g_sl_swept=true;
   g_trend=0;
  }

int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   SetIndexBuffer(0,BufSellSweep,INDICATOR_DATA);
   SetIndexBuffer(1,BufBuySweep,INDICATOR_DATA);
   SetIndexBuffer(2,BufAtr,INDICATOR_CALCULATIONS);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Smart Money Concepts");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   ResetState();
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
//| Pivot of `src` confirmed at bar i (pivot bar = i - len)           |
//+------------------------------------------------------------------+
double PivotHigh(const double &src[],const int i,const int len)
  {
   int p=i-len;
   if(p-len<0)
      return(EMPTY_VALUE);
   double v=src[p];
   for(int k=1; k<=len; k++)
     {
      if(src[p-k]>=v || src[p+k]>v)
         return(EMPTY_VALUE);
     }
   return(v);
  }

double PivotLow(const double &src[],const int i,const int len)
  {
   int p=i-len;
   if(p-len<0)
      return(EMPTY_VALUE);
   double v=src[p];
   for(int k=1; k<=len; k++)
     {
      if(src[p-k]<=v || src[p+k]<v)
         return(EMPTY_VALUE);
     }
   return(v);
  }

//+------------------------------------------------------------------+
void AddZone(SmcZone &pool[],const double top,const double bottom,const int start,const bool bull)
  {
   int n=ArraySize(pool);
   for(int j=0; j<n; j++)
      if(pool[j].active && pool[j].start==start && pool[j].bull==bull)
         return;
   int slot=-1;
   int oldest=0;
   for(int j=0; j<n; j++)
     {
      if(!pool[j].active)
        {
         slot=j;
         break;
        }
      if(pool[j].start<pool[oldest].start)
         oldest=j;
     }
   if(slot<0)
      slot=oldest;
   pool[slot].top=top;
   pool[slot].bottom=bottom;
   pool[slot].start=start;
   pool[slot].bull=bull;
   pool[slot].active=true;
  }

//--- order blocks die on a close through them; FVGs shrink as price fills them
void Mitigate(SmcZone &pool[],const bool shrink,const int i,const double &high[],const double &low[],
              const double &close[])
  {
   for(int j=0; j<ArraySize(pool); j++)
     {
      if(!pool[j].active)
         continue;
      if(pool[j].bull)
        {
         if((shrink && low[i]<=pool[j].bottom) || (!shrink && close[i]<pool[j].bottom))
            pool[j].active=false;
         else
            if(shrink && low[i]<pool[j].top)
               pool[j].top=low[i];
        }
      else
        {
         if((shrink && high[i]>=pool[j].top) || (!shrink && close[i]>pool[j].top))
            pool[j].active=false;
         else
            if(shrink && high[i]>pool[j].bottom)
               pool[j].bottom=high[i];
        }
     }
  }

//--- last opposite candle before the break (bearish candle for a bullish OB and vice versa)
int FindObBar(const int from_index,const bool bull,const int i,const double &open[],const double &high[],
              const double &low[],const double &close[])
  {
   int span=i-from_index;
   if(span<1)
      span=1;
   if(span>300)
      span=300;
   if(span>i)
      span=i;
   int best=i-1,best_any=i-1;
   bool found=false;
   for(int k=1; k<=span; k++)
     {
      int j=i-k;
      if(bull)
        {
         if(low[j]<low[best_any])
            best_any=j;
         if(close[j]<open[j] && (!found || low[j]<low[best]))
           {
            best=j;
            found=true;
           }
        }
      else
        {
         if(high[j]>high[best_any])
            best_any=j;
         if(close[j]>open[j] && (!found || high[j]>high[best]))
           {
            best=j;
            found=true;
           }
        }
     }
   return(found ? best : best_any);
  }

void AddMark(SmcMark &ring[],int &next,const double level,const int i1,const int i2,const string text,
             const bool bull)
  {
   ring[next].level=level;
   ring[next].i1=i1;
   ring[next].i2=i2;
   ring[next].text=text;
   ring[next].bull=bull;
   ring[next].used=true;
   next=(next+1)%ArraySize(ring);
  }

void AddSwing(const double price,const int idx,const string text,const bool high)
  {
   g_swings[g_swing_next].price=price;
   g_swings[g_swing_next].idx=idx;
   g_swings[g_swing_next].text=text;
   g_swings[g_swing_next].high=high;
   g_swings[g_swing_next].used=true;
   g_swing_next=(g_swing_next+1)%ArraySize(g_swings);
  }

//+------------------------------------------------------------------+
void ProcessBar(const int i,const double &open[],const double &high[],const double &low[],const double &close[])
  {
   Mitigate(g_obs,false,i,high,low,close);
   Mitigate(g_fvgs,true,i,high,low,close);

   double atr=BufAtr[i];
   double tol=(XOk(atr) ? InpEqThreshold*atr : 0.0);
   double ph=PivotHigh(high,i,InpSwingLen);
   double pl=PivotLow(low,i,InpSwingLen);
   int p=i-InpSwingLen;

   if(XOk(ph))
     {
      if(XOk(g_sh_price))
        {
         if(InpShowSwings)
            AddSwing(ph,p,ph>g_sh_price ? "HH" : "LH",true);
         if(InpShowEq && tol>0.0 && MathAbs(ph-g_sh_price)<=tol)
            AddMark(g_eqs,g_eq_next,(ph+g_sh_price)*0.5,g_sh_idx,p,"EQH",true);
        }
      g_sh_price=ph;
      g_sh_idx=p;
      g_sh_broken=false;
      g_sh_swept=false;
     }
   if(XOk(pl))
     {
      if(XOk(g_sl_price))
        {
         if(InpShowSwings)
            AddSwing(pl,p,pl<g_sl_price ? "LL" : "HL",false);
         if(InpShowEq && tol>0.0 && MathAbs(pl-g_sl_price)<=tol)
            AddMark(g_eqs,g_eq_next,(pl+g_sl_price)*0.5,g_sl_idx,p,"EQL",false);
        }
      g_sl_price=pl;
      g_sl_idx=p;
      g_sl_broken=false;
      g_sl_swept=false;
     }

   if(!g_sh_broken && XOk(g_sh_price) && close[i]>g_sh_price)
     {
      if(InpShowStruct)
         AddMark(g_marks,g_mark_next,g_sh_price,g_sh_idx,i,g_trend<0 ? "CHoCH" : "BOS",true);
      g_trend=1;
      g_sh_broken=true;
      if(InpShowOB)
        {
         int k=FindObBar(g_sh_idx,true,i,open,high,low,close);
         AddZone(g_obs,high[k],low[k],k,true);
        }
     }
   if(!g_sl_broken && XOk(g_sl_price) && close[i]<g_sl_price)
     {
      if(InpShowStruct)
         AddMark(g_marks,g_mark_next,g_sl_price,g_sl_idx,i,g_trend>0 ? "CHoCH" : "BOS",false);
      g_trend=-1;
      g_sl_broken=true;
      if(InpShowOB)
        {
         int k=FindObBar(g_sl_idx,false,i,open,high,low,close);
         AddZone(g_obs,high[k],low[k],k,false);
        }
     }

   if(InpShowFVG && i>2)
     {
      double gap_min=(XOk(atr) ? InpFvgMinAtr*atr : 0.0);
      if(low[i]>high[i-2] && close[i-1]>high[i-2] && low[i]-high[i-2]>=gap_min)
         AddZone(g_fvgs,low[i],high[i-2],i-1,true);
      if(high[i]<low[i-2] && close[i-1]<low[i-2] && low[i-2]-high[i]>=gap_min)
         AddZone(g_fvgs,low[i-2],high[i],i-1,false);
     }

   if(!g_sh_broken && !g_sh_swept && high[i]>g_sh_price && close[i]<g_sh_price)
      g_sh_swept=true;
   if(!g_sl_broken && !g_sl_swept && low[i]<g_sl_price && close[i]>g_sl_price)
      g_sl_swept=true;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<2*InpSwingLen+3)
      return(0);
   if(prev_calculated==0)
      ResetState();
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   int first_struct=MathMax(2*InpSwingLen+1,rates_total-MathMax(InpMaxBars,100));
   for(int i=start; i<rates_total; i++)
     {
      double tr=XTrueRange(high[i],low[i],i>0 ? close[i-1] : EMPTY_VALUE);
      BufAtr[i]=XRmaStep(i>0 ? BufAtr[i-1] : EMPTY_VALUE,tr,14);

      //--- sweeps use the swing state as it was before this bar
      double sell=EMPTY_VALUE,buy=EMPTY_VALUE;
      if(InpShowSweeps)
        {
         if(!g_sh_broken && !g_sh_swept && XOk(g_sh_price) && high[i]>g_sh_price && close[i]<g_sh_price)
            sell=high[i];
         if(!g_sl_broken && !g_sl_swept && XOk(g_sl_price) && low[i]<g_sl_price && close[i]>g_sl_price)
            buy=low[i];
        }
      BufSellSweep[i]=sell;
      BufBuySweep[i]=buy;

      //--- the forming bar is never committed
      if(i<=rates_total-2 && i>g_processed && i>=first_struct)
        {
         ProcessBar(i,open,high,low,close);
         g_processed=i;
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
void DrawZone(const SmcZone &z,const double right_x,const bool is_ob)
  {
   double k=g_back.K();
   double x1=g_map.X(z.start)-g_map.spacing*0.5;
   double y1=g_map.Y(z.top),y2=g_map.Y(z.bottom);
   uint rgb;
   if(is_ob)
      rgb=(z.bull ? g_t.bull : g_t.bear);
   else
      rgb=(z.bull ? g_t.cyan : g_t.orange);
   if(is_ob)
     {
      g_back.RoundRect(x1,y1,right_x,y2,2.0*k,XRgb(rgb,0.16),XRgb(rgb,0.55),1.0);
      g_back.FillRect(x1,y1,x1+2.0*k,y2,XRgb(rgb,0.85));
     }
   else
      g_back.RoundRect(x1,y1,right_x,y2,2.0*k,XRgb(rgb,0.14));
   if(MathAbs(y2-y1)>=9.0*k)
     {
      g_front.SetFont(XAU_FONT,7.0,FW_SEMIBOLD);
      g_front.Text(x1+5.0*k,MathMin(y1,y2)+1.0*k,is_ob ? "OB" : "FVG",XRgb(rgb,0.95),TA_LEFT|TA_TOP);
     }
   else
     {
      g_front.SetFont(XAU_FONT,7.0,FW_SEMIBOLD);
      g_front.Text(x1+5.0*k,MathMin(y1,y2)-1.0*k,is_ob ? "OB" : "FVG",XRgb(rgb,0.95),TA_LEFT|TA_BOTTOM);
     }
  }

void DrawMark(const SmcMark &m,const uint rgb,const double dash,const double gap)
  {
   double y=g_map.Y(m.level);
   double x1=g_map.X(m.i1),x2=g_map.X(m.i2);
   g_front.Line(x1,y,x2,y,XRgb(rgb,0.95),1.0,dash,gap);
   g_front.Pill((x1+x2)*0.5,y,m.text,XRgb(rgb,0.16),XRgb(rgb,1.0),m.bull ? XA_ABOVE : XA_BELOW,7.0,0,false);
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
   if(!XBegin(g_back,"XAU.SMC.back",g_map,true) || !XBegin(g_front,"XAU.SMC.front",g_map,false))
      return;
   int last=g_total-1;
   double k=g_front.K();
   double right_x=g_map.X(last+InpExtendBars);

   //--- premium / equilibrium / discount of the current dealing range
   if(InpShowZones && XOk(g_sh_price) && XOk(g_sl_price) && g_sh_price>g_sl_price)
     {
      double top=g_sh_price,bottom=g_sl_price,span=top-bottom;
      double x1=g_map.X(MathMin(g_sh_idx,g_sl_idx));
      g_back.FillRect(x1,g_map.Y(top),right_x,g_map.Y(top-0.05*span),XRgb(g_t.bear,0.10));
      g_back.FillRect(x1,g_map.Y(bottom+0.525*span),right_x,g_map.Y(bottom+0.475*span),XRgb(g_t.neutral,0.12));
      g_back.FillRect(x1,g_map.Y(bottom+0.05*span),right_x,g_map.Y(bottom),XRgb(g_t.bull,0.10));
      g_front.SetFont(XAU_FONT,7.5,FW_SEMIBOLD);
      g_front.Text(right_x-4.0*k,g_map.Y(top)+2.0*k,"Premium",XRgb(g_t.bear,0.9),TA_RIGHT|TA_TOP);
      g_front.Text(right_x-4.0*k,g_map.Y(bottom+0.5*span),"Equilibrium",XRgb(g_t.silver,0.9),TA_RIGHT|TA_VCENTER);
      g_front.Text(right_x-4.0*k,g_map.Y(bottom)-2.0*k,"Discount",XRgb(g_t.bull,0.9),TA_RIGHT|TA_BOTTOM);
     }

   for(int j=0; j<ArraySize(g_fvgs); j++)
      if(g_fvgs[j].active)
         DrawZone(g_fvgs[j],right_x,false);
   for(int j=0; j<ArraySize(g_obs); j++)
      if(g_obs[j].active)
         DrawZone(g_obs[j],right_x,true);

   for(int j=0; j<ArraySize(g_eqs); j++)
      if(g_eqs[j].used)
         DrawMark(g_eqs[j],g_t.gold,1.5,2.5);
   for(int j=0; j<ArraySize(g_marks); j++)
      if(g_marks[j].used)
         DrawMark(g_marks[j],g_marks[j].bull ? g_t.bull : g_t.bear,5.0,3.0);

   if(InpShowSwings)
     {
      g_front.SetFont(XAU_FONT,7.5,FW_SEMIBOLD);
      for(int j=0; j<ArraySize(g_swings); j++)
        {
         if(!g_swings[j].used)
            continue;
         double x=g_map.X(g_swings[j].idx);
         double y=g_map.Y(g_swings[j].price);
         if(g_swings[j].high)
            g_front.Text(x,y-4.0*k,g_swings[j].text,XRgb(g_t.silver,0.9),TA_CENTER|TA_BOTTOM);
         else
            g_front.Text(x,y+4.0*k,g_swings[j].text,XRgb(g_t.silver,0.9),TA_CENTER|TA_TOP);
        }
     }

   if(InpShowSweeps)
     {
      int from=g_map.From(),to=g_map.To();
      for(int i=from; i<=to; i++)
        {
         if(XOk(BufSellSweep[i]))
            g_front.Pill(g_map.X(i),g_map.Y(BufSellSweep[i]),"SWEEP",XRgb(g_t.orange,1.0),XRgb(g_t.ink,1.0),XA_ABOVE,7.0);
         if(XOk(BufBuySweep[i]))
            g_front.Pill(g_map.X(i),g_map.Y(BufBuySweep[i]),"SWEEP",XRgb(g_t.cyan,1.0),XRgb(g_t.ink,1.0),XA_BELOW,7.0);
        }
     }

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
