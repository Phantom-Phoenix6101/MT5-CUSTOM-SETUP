//+------------------------------------------------------------------+
//|                                           XAU_MomentumMatrix.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| RSI with a value-gradient line and overbought / oversold glow,    |
//| RSI signal line, MACD histogram rescaled onto the RSI scale and   |
//| regular + hidden RSI divergences with connecting lines.           |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU Momentum Matrix - gradient RSI, signal, MACD histogram and divergences."
#property description "Smooth anti-aliased rendering."
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 21
#property indicator_plots   5

#property indicator_label1  "Momentum histogram"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "RSI"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "RSI signal"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Bullish divergence"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Bearish divergence"
#property indicator_type5   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

input group "RSI"
input ENUM_APPLIED_PRICE InpSource     = PRICE_CLOSE; // Source
input int                InpRsiLen     = 14;    // RSI length
input int                InpSignalLen  = 9;     // RSI signal length
input double             InpObLevel    = 70.0;  // Overbought level
input double             InpOsLevel    = 30.0;  // Oversold level
input group "MACD histogram"
input bool               InpShowHist   = true;  // Show momentum histogram
input int                InpMacdFast   = 12;    // MACD fast
input int                InpMacdSlow   = 26;    // MACD slow
input int                InpMacdSignal = 9;     // MACD signal
input group "Divergences"
input int                InpDivLookback= 5;     // Divergence pivot length
input int                InpDivMaxBars = 60;    // Divergence max distance (bars)
input bool               InpShowHidden = true;  // Show hidden divergences
input bool               InpDivLines   = true;  // Draw divergence lines
input group "Style"
input bool               InpGlow       = true;  // Soft glow on the RSI
input ENUM_XAU_THEME     InpTheme      = XAU_THEME_MIDNIGHT; // Colour theme

double BufHist[],BufRsi[],BufSignal[],BufBull[],BufBear[];
double BufGain[],BufLoss[],BufMFast[],BufMSlow[],BufMSig[],BufHistRaw[];
double BufPLRsi[],BufPLPrice[],BufPLBar[],BufPHRsi[],BufPHPrice[],BufPHBar[];
double BufBullType[],BufBullFrom[],BufBearType[],BufBearFrom[];

XauTheme   g_t;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;
uint       g_lut[256];
uint       g_hcols[];

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   SetIndexBuffer(0,BufHist,INDICATOR_DATA);
   SetIndexBuffer(1,BufRsi,INDICATOR_DATA);
   SetIndexBuffer(2,BufSignal,INDICATOR_DATA);
   SetIndexBuffer(3,BufBull,INDICATOR_DATA);
   SetIndexBuffer(4,BufBear,INDICATOR_DATA);
   SetIndexBuffer(5,BufGain,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,BufLoss,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,BufMFast,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,BufMSlow,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,BufMSig,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,BufHistRaw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,BufPLRsi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,BufPLPrice,INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,BufPLBar,INDICATOR_CALCULATIONS);
   SetIndexBuffer(14,BufPHRsi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(15,BufPHPrice,INDICATOR_CALCULATIONS);
   SetIndexBuffer(16,BufPHBar,INDICATOR_CALCULATIONS);
   SetIndexBuffer(17,BufBullType,INDICATOR_CALCULATIONS);
   SetIndexBuffer(18,BufBullFrom,INDICATOR_CALCULATIONS);
   SetIndexBuffer(19,BufBearType,INDICATOR_CALCULATIONS);
   SetIndexBuffer(20,BufBearFrom,INDICATOR_CALCULATIONS);
   for(int p=0; p<5; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_SHOW_DATA,false);

   //--- RSI value gradient: bear at 0, neutral at 50, bull at 100 (lut[0] = top = 100)
   uint bull=XRgb(g_t.bull,1.0),bear=XRgb(g_t.bear,1.0),neutral=XRgb(g_t.neutral,1.0);
   for(int j=0; j<256; j++)
     {
      double f=1.0-j/255.0;
      g_lut[j]=(f<0.5 ? XLerp(bear,neutral,f/0.5) : XLerp(neutral,bull,(f-0.5)/0.5));
     }

   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Momentum Matrix");
   IndicatorSetInteger(INDICATOR_DIGITS,2);
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

double PriceOf(const int i,const double &open[],const double &high[],const double &low[],const double &close[])
  {
   switch(InpSource)
     {
      case PRICE_OPEN:
         return(open[i]);
      case PRICE_HIGH:
         return(high[i]);
      case PRICE_LOW:
         return(low[i]);
      case PRICE_MEDIAN:
         return((high[i]+low[i])*0.5);
      case PRICE_TYPICAL:
         return((high[i]+low[i]+close[i])/3.0);
      case PRICE_WEIGHTED:
         return((high[i]+low[i]+2.0*close[i])*0.25);
      default:
         return(close[i]);
     }
  }

//--- pivot of the RSI confirmed at bar i (pivot bar = i - len)
double RsiPivot(const int i,const int len,const bool high)
  {
   int p=i-len;
   if(p-len<0)
      return(EMPTY_VALUE);
   double v=BufRsi[p];
   if(!XOk(v))
      return(EMPTY_VALUE);
   for(int k=1; k<=len; k++)
     {
      double l=BufRsi[p-k],r=BufRsi[p+k];
      if(!XOk(l) || !XOk(r))
         return(EMPTY_VALUE);
      if(high && (l>=v || r>v))
         return(EMPTY_VALUE);
      if(!high && (l<=v || r<v))
         return(EMPTY_VALUE);
     }
   return(v);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<3)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   int L=MathMax(InpDivLookback,1);
   for(int i=start; i<rates_total; i++)
     {
      double src=PriceOf(i,open,high,low,close);
      double prev_src=(i>0 ? PriceOf(i-1,open,high,low,close) : EMPTY_VALUE);

      //--- RSI (Wilder)
      if(i==0)
        {
         BufGain[i]=EMPTY_VALUE;
         BufLoss[i]=EMPTY_VALUE;
         BufRsi[i]=EMPTY_VALUE;
        }
      else
        {
         double ch=src-prev_src;
         BufGain[i]=XRmaStep(BufGain[i-1],MathMax(ch,0.0),InpRsiLen);
         BufLoss[i]=XRmaStep(BufLoss[i-1],MathMax(-ch,0.0),InpRsiLen);
         double up=BufGain[i],dn=BufLoss[i];
         BufRsi[i]=(dn==0.0 ? 100.0 : (up==0.0 ? 0.0 : 100.0-100.0/(1.0+up/dn)));
         if(i<InpRsiLen)
            BufRsi[i]=EMPTY_VALUE;
        }
      BufSignal[i]=XEmaStep(i>0 ? BufSignal[i-1] : EMPTY_VALUE,BufRsi[i],InpSignalLen);

      //--- MACD histogram rescaled into +/-25 around the 50 midline
      BufMFast[i]=XEmaStep(i>0 ? BufMFast[i-1] : EMPTY_VALUE,src,InpMacdFast);
      BufMSlow[i]=XEmaStep(i>0 ? BufMSlow[i-1] : EMPTY_VALUE,src,InpMacdSlow);
      double macd=BufMFast[i]-BufMSlow[i];
      BufMSig[i]=XEmaStep(i>0 ? BufMSig[i-1] : EMPTY_VALUE,macd,InpMacdSignal);
      BufHistRaw[i]=macd-BufMSig[i];
      double hmax=0.0;
      for(int j=MathMax(0,i-199); j<=i; j++)
         hmax=MathMax(hmax,MathAbs(BufHistRaw[j]));
      BufHist[i]=(InpShowHist && hmax>0.0 && i>=InpMacdSlow ? 50.0+25.0*BufHistRaw[i]/hmax : EMPTY_VALUE);

      //--- divergence state carried from the previous bar
      BufPLRsi[i]=(i>0 ? BufPLRsi[i-1] : EMPTY_VALUE);
      BufPLPrice[i]=(i>0 ? BufPLPrice[i-1] : EMPTY_VALUE);
      BufPLBar[i]=(i>0 ? BufPLBar[i-1] : -1.0);
      BufPHRsi[i]=(i>0 ? BufPHRsi[i-1] : EMPTY_VALUE);
      BufPHPrice[i]=(i>0 ? BufPHPrice[i-1] : EMPTY_VALUE);
      BufPHBar[i]=(i>0 ? BufPHBar[i-1] : -1.0);
      BufBull[i]=EMPTY_VALUE;
      BufBear[i]=EMPTY_VALUE;
      BufBullType[i]=0.0;
      BufBearType[i]=0.0;
      BufBullFrom[i]=-1.0;
      BufBearFrom[i]=-1.0;

      int p=i-L;
      if(p<0)
         continue;
      //--- markers live on the pivot bar; only bar i writes bar p, so clear it first
      BufBull[p]=EMPTY_VALUE;
      BufBear[p]=EMPTY_VALUE;
      BufBullType[p]=0.0;
      BufBearType[p]=0.0;

      double pl=RsiPivot(i,L,false);
      if(XOk(pl))
        {
         double price_low=low[p];
         int prev_bar=(int)BufPLBar[i];
         int gap=p-prev_bar;
         if(prev_bar>=0 && gap>=5 && gap<=InpDivMaxBars)
           {
            int type=0;
            if(price_low<BufPLPrice[i] && pl>BufPLRsi[i] && pl<50.0)
               type=1;
            else
               if(InpShowHidden && price_low>BufPLPrice[i] && pl<BufPLRsi[i])
                  type=2;
            if(type>0)
              {
               BufBull[p]=pl;
               BufBullType[p]=type;
               BufBullFrom[p]=prev_bar;
              }
           }
         BufPLRsi[i]=pl;
         BufPLPrice[i]=price_low;
         BufPLBar[i]=p;
        }

      double ph=RsiPivot(i,L,true);
      if(XOk(ph))
        {
         double price_high=high[p];
         int prev_bar=(int)BufPHBar[i];
         int gap=p-prev_bar;
         if(prev_bar>=0 && gap>=5 && gap<=InpDivMaxBars)
           {
            int type=0;
            if(price_high>BufPHPrice[i] && ph<BufPHRsi[i] && ph>50.0)
               type=1;
            else
               if(InpShowHidden && price_high<BufPHPrice[i] && ph>BufPHRsi[i])
                  type=2;
            if(type>0)
              {
               BufBear[p]=ph;
               BufBearType[p]=type;
               BufBearFrom[p]=prev_bar;
              }
           }
         BufPHRsi[i]=ph;
         BufPHPrice[i]=price_high;
         BufPHBar[i]=p;
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
uint LutAt(const double v)
  {
   int j=(int)MathRound((1.0-XClamp(v/100.0,0.0,1.0))*255.0);
   return(g_lut[j]);
  }

void DrawDivergence(const int p,const int from,const double value,const int type,const bool bull)
  {
   uint rgb=(bull ? g_t.bull : g_t.bear);
   double a=(type==1 ? 1.0 : 0.6);
   double x=g_map.X(p),y=g_map.Y(value);
   if(InpDivLines && from>=0 && from<g_total && XOk(BufRsi[from]))
     {
      double x0=g_map.X(from),y0=g_map.Y(BufRsi[from]);
      if(type==1)
         g_front.Line(x0,y0,x,y,XRgb(rgb,0.9),1.5);
      else
         g_front.Line(x0,y0,x,y,XRgb(rgb,0.6),1.2,4.0,3.0);
      g_front.Circle(x0,y0,2.5*g_front.K(),XRgb(rgb,a));
     }
   g_front.Circle(x,y,2.5*g_front.K(),XRgb(rgb,a));
   string text=(bull ? (type==1 ? "Bull" : "H Bull") : (type==1 ? "Bear" : "H Bear"));
   g_front.Pill(x,y,text,XRgb(rgb,a),XRgb(g_t.ink,1.0),bull ? XA_BELOW : XA_ABOVE,7.0);
  }

void Render()
  {
   if(g_total<3)
      return;
   int sub=ChartWindowFind();
   if(sub<0)
      sub=1;
   if(!g_map.Update(sub,g_total))
      return;
   if(!XBegin(g_back,"XAU.Momentum.back",g_map,true) || !XBegin(g_front,"XAU.Momentum.front",g_map,false))
      return;
   double k=g_front.K();
   int from=g_map.From(),to=g_map.To();
   int last=g_total-1;

   //--- neutral band, guides
   g_back.FillRect(0,g_map.Y(InpObLevel),g_map.width,g_map.Y(InpOsLevel),XRgb(g_t.violet,0.05));
   XLevel(g_back,g_map,InpObLevel,XRgb(g_t.muted,0.45),1.0,4.0,4.0);
   XLevel(g_back,g_map,InpOsLevel,XRgb(g_t.muted,0.45),1.0,4.0,4.0);
   XLevel(g_back,g_map,50.0,XRgb(g_t.muted,0.35),1.0,1.5,3.0);

   //--- MACD histogram
   if(InpShowHist)
     {
      if(ArraySize(g_hcols)!=g_total)
         ArrayResize(g_hcols,g_total);
      for(int i=from; i<=to; i++)
        {
         double h=BufHistRaw[i];
         bool rising=(i>0 && h>=BufHistRaw[i-1]);
         if(h>=0.0)
            g_hcols[i]=XRgb(g_t.bull,rising ? 0.80 : 0.38);
         else
            g_hcols[i]=XRgb(g_t.bear,rising ? 0.38 : 0.80);
        }
      XColumns(g_back,g_map,BufHist,50.0,g_hcols,0.6);
     }

   //--- overbought / oversold glow
   XFillBeyond(g_back,g_map,BufRsi,InpObLevel,true,XRgb(g_t.bear,0.35),0.15);
   XFillBeyond(g_back,g_map,BufRsi,InpOsLevel,false,XRgb(g_t.bull,0.35),0.15);

   //--- lines
   XStrokeSeries(g_front,g_map,BufSignal,XRgb(g_t.silver,0.6),1.0);
   XStrokeSeriesLut(g_front,g_map,BufRsi,g_lut,g_map.Y(100.0),g_map.Y(0.0),2.0,InpGlow ? 0.22 : 0.0);

   //--- divergences (lines may start left of the window, so look a little further back)
   for(int p=MathMax(0,from-InpDivMaxBars); p<=to; p++)
     {
      if(BufBullType[p]>0.0 && XOk(BufBull[p]))
         DrawDivergence(p,(int)BufBullFrom[p],BufBull[p],(int)BufBullType[p],true);
      if(BufBearType[p]>0.0 && XOk(BufBear[p]))
         DrawDivergence(p,(int)BufBearFrom[p],BufBear[p],(int)BufBearType[p],false);
     }

   //--- live value tag
   if(XOk(BufRsi[last]))
     {
      double x=g_map.X(last)+MathMax(2.0*g_map.spacing,8.0*k);
      g_front.Pill(x,g_map.Y(BufRsi[last]),DoubleToString(BufRsi[last],1),LutAt(BufRsi[last]),XRgb(g_t.ink,1.0),
                   XA_RIGHT,7.5);
     }

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
