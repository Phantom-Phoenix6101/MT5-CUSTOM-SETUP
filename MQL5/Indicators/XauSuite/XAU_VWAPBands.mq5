//+------------------------------------------------------------------+
//|                                                XAU_VWAPBands.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Anchored VWAP (day / week / month on the NY 17:00 trading day)    |
//| with three volume-weighted standard deviation bands, gradient     |
//| stretch / extreme zones and the previous period's closing VWAP.   |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU VWAP Bands - anchored VWAP with 1/2/3 sigma bands and previous period VWAP."
#property description "Smooth anti-aliased rendering."
#property indicator_chart_window
#property indicator_buffers 17
#property indicator_plots   8

#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Upper 1"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Lower 1"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Upper 2"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Lower 2"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "Upper 3"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "Lower 3"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "Previous period VWAP"
#property indicator_type8   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

enum ENUM_XAU_ANCHOR_PERIOD
  {
   XAU_ANCHOR_DAY=0,   // Day
   XAU_ANCHOR_WEEK=1,  // Week
   XAU_ANCHOR_MONTH=2  // Month
  };

input group "VWAP"
input ENUM_APPLIED_PRICE     InpSource   = PRICE_TYPICAL;  // Source
input ENUM_APPLIED_VOLUME    InpVolume   = VOLUME_TICK;    // Volume
input ENUM_XAU_ANCHOR_PERIOD InpAnchor   = XAU_ANCHOR_DAY; // Anchor period
input double                 InpMult1    = 1.0;   // Band 1 (sigma)
input double                 InpMult2    = 2.0;   // Band 2 (sigma)
input double                 InpMult3    = 3.0;   // Band 3 (sigma)
input bool                   InpShowPrev = true;  // Show previous period VWAP close
input bool                   InpShowTags = true;  // VWAP price tags
input bool                   InpGlow     = true;  // Soft glow on the VWAP
input group "Time"
input ENUM_XAU_DAY_ROLL      InpDayRoll   = XAU_ROLL_NY17; // Trading day starts at
input double                 InpServerGMT = 99;    // Server GMT offset, hours (99 = auto-detect)
input ENUM_XAU_DST           InpServerDST = XAU_DST_US; // Server daylight-saving rule
input group "Style"
input ENUM_XAU_THEME         InpTheme     = XAU_THEME_MIDNIGHT; // Colour theme

double BufVwap[],BufU1[],BufL1[],BufU2[],BufL2[],BufU3[],BufL3[],BufPrev[];
double BufSPV[],BufSPPV[],BufSV[],BufSP[],BufSPP[],BufCnt[],BufPrevRaw[],BufRaw[],BufKey[];

XauTheme   g_t;
CXauClock  g_clock;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   g_clock.Init(InpServerGMT,InpServerDST);
   SetIndexBuffer(0,BufVwap,INDICATOR_DATA);
   SetIndexBuffer(1,BufU1,INDICATOR_DATA);
   SetIndexBuffer(2,BufL1,INDICATOR_DATA);
   SetIndexBuffer(3,BufU2,INDICATOR_DATA);
   SetIndexBuffer(4,BufL2,INDICATOR_DATA);
   SetIndexBuffer(5,BufU3,INDICATOR_DATA);
   SetIndexBuffer(6,BufL3,INDICATOR_DATA);
   SetIndexBuffer(7,BufPrev,INDICATOR_DATA);
   SetIndexBuffer(8,BufSPV,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,BufSPPV,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,BufSV,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,BufSP,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,BufSPP,INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,BufCnt,INDICATOR_CALCULATIONS);
   SetIndexBuffer(14,BufPrevRaw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(15,BufRaw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(16,BufKey,INDICATOR_CALCULATIONS);
   for(int p=0; p<8; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU VWAP Bands");
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

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<2)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   for(int i=start; i<rates_total; i++)
     {
      long key=g_clock.DayKey(time[i],InpDayRoll);
      BufKey[i]=(double)key;
      bool reset=(i==0);
      if(i>0)
        {
         long pkey=(long)BufKey[i-1];
         bool new_day=(key!=pkey);
         if(InpAnchor==XAU_ANCHOR_DAY)
            reset=new_day;
         else
            if(InpAnchor==XAU_ANCHOR_WEEK)
               reset=new_day && (g_clock.DayOfWeek(key)<g_clock.DayOfWeek(pkey) || key-pkey>=7);
            else
               reset=new_day && g_clock.MonthOfKey(key)!=g_clock.MonthOfKey(pkey);
        }

      double price=PriceOf(i,open,high,low,close);
      double vol=(double)(InpVolume==VOLUME_REAL ? volume[i] : tick_volume[i]);
      if(vol<0.0)
         vol=0.0;

      double spv=0.0,sppv=0.0,sv=0.0,sp=0.0,spp=0.0,cnt=0.0;
      double prev=EMPTY_VALUE;
      if(reset)
         prev=(i>0 ? BufRaw[i-1] : EMPTY_VALUE);
      else
        {
         spv=BufSPV[i-1];
         sppv=BufSPPV[i-1];
         sv=BufSV[i-1];
         sp=BufSP[i-1];
         spp=BufSPP[i-1];
         cnt=BufCnt[i-1];
         prev=BufPrevRaw[i-1];
        }
      spv+=price*vol;
      sppv+=price*price*vol;
      sv+=vol;
      sp+=price;
      spp+=price*price;
      cnt+=1.0;
      BufSPV[i]=spv;
      BufSPPV[i]=sppv;
      BufSV[i]=sv;
      BufSP[i]=sp;
      BufSPP[i]=spp;
      BufCnt[i]=cnt;
      BufPrevRaw[i]=prev;

      //--- equal-weighted fallback when the feed carries no volume
      double vwap=EMPTY_VALUE,dev=0.0;
      if(sv>0.0)
        {
         vwap=spv/sv;
         dev=MathSqrt(MathMax(sppv/sv-vwap*vwap,0.0));
        }
      else
        {
         vwap=sp/cnt;
         dev=MathSqrt(MathMax(spp/cnt-vwap*vwap,0.0));
        }
      BufRaw[i]=vwap;

      if(reset)
        {
         BufVwap[i]=EMPTY_VALUE;
         BufU1[i]=EMPTY_VALUE;
         BufL1[i]=EMPTY_VALUE;
         BufU2[i]=EMPTY_VALUE;
         BufL2[i]=EMPTY_VALUE;
         BufU3[i]=EMPTY_VALUE;
         BufL3[i]=EMPTY_VALUE;
         BufPrev[i]=EMPTY_VALUE;
         continue;
        }
      BufVwap[i]=vwap;
      BufU1[i]=vwap+InpMult1*dev;
      BufL1[i]=vwap-InpMult1*dev;
      BufU2[i]=vwap+InpMult2*dev;
      BufL2[i]=vwap-InpMult2*dev;
      BufU3[i]=vwap+InpMult3*dev;
      BufL3[i]=vwap-InpMult3*dev;
      BufPrev[i]=(InpShowPrev ? prev : EMPTY_VALUE);
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
   if(g_total<2)
      return;
   int sub=ChartWindowFind();
   if(sub<0)
      sub=0;
   if(!g_map.Update(sub,g_total))
      return;
   if(!XBegin(g_back,"XAU.VWAP.back",g_map,true) || !XBegin(g_front,"XAU.VWAP.front",g_map,false))
      return;

   //--- zones: value band, then stretch and extreme gradients fading towards the VWAP
   XFillSeries(g_back,g_map,BufU1,BufL1,XRgb(g_t.gold,0.05));
   XFillSeries(g_back,g_map,BufU2,BufU1,XRgb(g_t.bear,0.08),0.45);
   XFillSeries(g_back,g_map,BufU3,BufU2,XRgb(g_t.bear,0.15),0.55);
   XFillSeries(g_back,g_map,BufL2,BufL1,XRgb(g_t.bull,0.08),0.45);
   XFillSeries(g_back,g_map,BufL3,BufL2,XRgb(g_t.bull,0.15),0.55);

   //--- band edges
   XStrokeSeries(g_front,g_map,BufU1,XRgb(g_t.bear,0.35),1.0);
   XStrokeSeries(g_front,g_map,BufL1,XRgb(g_t.bull,0.35),1.0);
   XStrokeSeries(g_front,g_map,BufU2,XRgb(g_t.bear,0.55),1.0);
   XStrokeSeries(g_front,g_map,BufL2,XRgb(g_t.bull,0.55),1.0);
   XStrokeSeries(g_front,g_map,BufU3,XRgb(g_t.bear,0.80),1.0);
   XStrokeSeries(g_front,g_map,BufL3,XRgb(g_t.bull,0.80),1.0);
   XStrokeSeries(g_front,g_map,BufPrev,XRgb(g_t.gold,0.60),1.0,1.5,2.5);
   XStrokeSeries(g_front,g_map,BufVwap,XRgb(g_t.gold,1.0),2.0,0.0,0.0,InpGlow ? 0.25 : 0.0);

   if(InpShowTags)
     {
      int last=g_total-1;
      double x=g_map.X(last)+MathMax(3.0*g_map.spacing,10.0*g_front.K());
      XauTag tags[];
      int n=0;
      if(XOk(BufVwap[last]))
         XAddTag(tags,n,g_map.Y(BufVwap[last]),"VWAP "+DoubleToString(BufVwap[last],2),XRgb(g_t.gold,1.0),
                 XRgb(g_t.ink,1.0));
      if(XOk(BufU3[last]))
         XAddTag(tags,n,g_map.Y(BufU3[last]),"+"+DoubleToString(InpMult3,1)+ShortToString(0x03C3),XRgb(g_t.bear,0.85),
                 XRgb(g_t.ink,1.0));
      if(XOk(BufL3[last]))
         XAddTag(tags,n,g_map.Y(BufL3[last]),"-"+DoubleToString(InpMult3,1)+ShortToString(0x03C3),XRgb(g_t.bull,0.85),
                 XRgb(g_t.ink,1.0));
      if(XOk(BufPrev[last]))
         XAddTag(tags,n,g_map.Y(BufPrev[last]),"pVWAP "+DoubleToString(BufPrev[last],2),XRgb(g_t.gold,0.55),
                 XRgb(g_t.ink,1.0));
      XDrawTags(g_front,tags,n,x,7.5);
     }

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
