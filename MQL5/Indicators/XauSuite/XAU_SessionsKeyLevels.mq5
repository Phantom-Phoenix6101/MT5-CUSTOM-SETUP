//+------------------------------------------------------------------+
//|                                        XAU_SessionsKeyLevels.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Asia / London / New York session boxes with their range, previous |
//| day high / low / close, daily open, previous week high / low,     |
//| weekly open and psychological round levels, with stacked price    |
//| tags on the right. Sessions are DST-aware in their own time zone. |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU Sessions & Key Levels - session boxes, PDH/PDL/PDC, daily & weekly opens, round levels."
#property description "Smooth anti-aliased rendering."
#property indicator_chart_window
#property indicator_buffers 22
#property indicator_plots   7

#property indicator_label1  "Prev day high"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Prev day low"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Prev day close"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Daily open"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Prev week high"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "Prev week low"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "Weekly open"
#property indicator_type7   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

input group "Sessions"
input bool              InpShowSessions = true;  // Show session boxes
input bool              InpShowAsia     = true;  // Asia session
input int               InpAsiaStart    = 9;     // Asia start hour (Tokyo time)
input int               InpAsiaEnd      = 15;    // Asia end hour (Tokyo time)
input bool              InpShowLondon   = true;  // London session
input int               InpLondonStart  = 8;     // London start hour (London time)
input int               InpLondonEnd    = 16;    // London end hour (London time)
input bool              InpShowNY       = true;  // New York session
input int               InpNYStart      = 8;     // New York start hour (NY time)
input int               InpNYEnd        = 17;    // New York end hour (NY time)
input int               InpSessionDays  = 3;     // Session boxes to keep (days)
input group "Key levels"
input bool              InpShowDaily    = true;  // Previous day H/L/C + daily open
input bool              InpShowWeekly   = true;  // Previous week H/L + weekly open
input bool              InpShowRound    = true;  // Psychological round levels
input double            InpRoundStep    = 50.0;  // Round level step ($)
input int               InpRoundCount   = 2;     // Round levels each side
input bool              InpShowTags     = true;  // Level price tags
input group "Time"
input ENUM_XAU_DAY_ROLL InpDayRoll      = XAU_ROLL_NY17; // Trading day starts at
input double            InpServerGMT    = 99;    // Server GMT offset, hours (99 = auto-detect)
input ENUM_XAU_DST      InpServerDST    = XAU_DST_US; // Server daylight-saving rule
input group "Style"
input ENUM_XAU_THEME    InpTheme        = XAU_THEME_AUTO; // Colour theme

double BufPdh[],BufPdl[],BufPdc[],BufDOpen[],BufPwh[],BufPwl[],BufWOpen[];
double BufKey[],BufDCount[],BufDHigh[],BufDLow[],BufDOpenRaw[],BufPH[],BufPL[],BufPC[];
double BufWCount[],BufWHigh[],BufWLow[],BufWOpenRaw[],BufPWH[],BufPWL[];
double BufSess[];   // bit mask: 1 Asia, 2 London, 4 New York

XauTheme   g_t;
CXauClock  g_clock;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;
double     g_high[],g_low[];

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   g_clock.Init(InpServerGMT,InpServerDST);
   SetIndexBuffer(0,BufPdh,INDICATOR_DATA);
   SetIndexBuffer(1,BufPdl,INDICATOR_DATA);
   SetIndexBuffer(2,BufPdc,INDICATOR_DATA);
   SetIndexBuffer(3,BufDOpen,INDICATOR_DATA);
   SetIndexBuffer(4,BufPwh,INDICATOR_DATA);
   SetIndexBuffer(5,BufPwl,INDICATOR_DATA);
   SetIndexBuffer(6,BufWOpen,INDICATOR_DATA);
   SetIndexBuffer(7,BufKey,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,BufDCount,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,BufDHigh,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,BufDLow,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,BufDOpenRaw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,BufPH,INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,BufPL,INDICATOR_CALCULATIONS);
   SetIndexBuffer(14,BufPC,INDICATOR_CALCULATIONS);
   SetIndexBuffer(15,BufWCount,INDICATOR_CALCULATIONS);
   SetIndexBuffer(16,BufWHigh,INDICATOR_CALCULATIONS);
   SetIndexBuffer(17,BufWLow,INDICATOR_CALCULATIONS);
   SetIndexBuffer(18,BufWOpenRaw,INDICATOR_CALCULATIONS);
   SetIndexBuffer(19,BufPWH,INDICATOR_CALCULATIONS);
   SetIndexBuffer(20,BufPWL,INDICATOR_CALCULATIONS);
   SetIndexBuffer(21,BufSess,INDICATOR_CALCULATIONS);
   for(int p=0; p<7; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Sessions & Key Levels");
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
   if(rates_total<2)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   ArrayResize(g_high,rates_total);
   ArrayResize(g_low,rates_total);
   double tf_sec=(double)PeriodSeconds();
   bool day_on=InpShowDaily && tf_sec<86400.0;
   bool week_on=InpShowWeekly && tf_sec<604800.0;
   bool intraday=tf_sec<14400.0;

   for(int i=start; i<rates_total; i++)
     {
      g_high[i]=high[i];
      g_low[i]=low[i];
      long key=g_clock.DayKey(time[i],InpDayRoll);
      BufKey[i]=(double)key;
      bool new_day=false;
      bool new_week=false;
      if(i>0)
        {
         long pkey=(long)BufKey[i-1];
         new_day=(key!=pkey);
         new_week=new_day && (g_clock.DayOfWeek(key)<g_clock.DayOfWeek(pkey) || key-pkey>=7);
        }

      //--- day
      double pcount=(i>0 ? BufDCount[i-1] : 0.0);
      BufPH[i]=(i>0 ? BufPH[i-1] : EMPTY_VALUE);
      BufPL[i]=(i>0 ? BufPL[i-1] : EMPTY_VALUE);
      BufPC[i]=(i>0 ? BufPC[i-1] : EMPTY_VALUE);
      if(new_day)
        {
         BufDCount[i]=pcount+1.0;
         // the first, partially loaded day is not published as a "previous day"
         if(pcount>=1.0)
           {
            BufPH[i]=BufDHigh[i-1];
            BufPL[i]=BufDLow[i-1];
            BufPC[i]=close[i-1];
           }
         BufDHigh[i]=high[i];
         BufDLow[i]=low[i];
         BufDOpenRaw[i]=open[i];
        }
      else
        {
         BufDCount[i]=pcount;
         BufDHigh[i]=XMax(i>0 ? BufDHigh[i-1] : EMPTY_VALUE,high[i]);
         BufDLow[i]=XMin(i>0 ? BufDLow[i-1] : EMPTY_VALUE,low[i]);
         BufDOpenRaw[i]=(i>0 ? BufDOpenRaw[i-1] : EMPTY_VALUE);
        }

      //--- week
      double wcount=(i>0 ? BufWCount[i-1] : 0.0);
      BufPWH[i]=(i>0 ? BufPWH[i-1] : EMPTY_VALUE);
      BufPWL[i]=(i>0 ? BufPWL[i-1] : EMPTY_VALUE);
      if(new_week)
        {
         BufWCount[i]=wcount+1.0;
         if(wcount>=1.0)
           {
            BufPWH[i]=BufWHigh[i-1];
            BufPWL[i]=BufWLow[i-1];
           }
         BufWHigh[i]=high[i];
         BufWLow[i]=low[i];
         BufWOpenRaw[i]=open[i];
        }
      else
        {
         BufWCount[i]=wcount;
         BufWHigh[i]=XMax(i>0 ? BufWHigh[i-1] : EMPTY_VALUE,high[i]);
         BufWLow[i]=XMin(i>0 ? BufWLow[i-1] : EMPTY_VALUE,low[i]);
         BufWOpenRaw[i]=(i>0 ? BufWOpenRaw[i-1] : EMPTY_VALUE);
        }

      //--- published levels; a new period starts with a gap so lines do not join
      BufPdh[i]=(day_on && !new_day ? BufPH[i] : EMPTY_VALUE);
      BufPdl[i]=(day_on && !new_day ? BufPL[i] : EMPTY_VALUE);
      BufPdc[i]=(day_on && !new_day ? BufPC[i] : EMPTY_VALUE);
      BufDOpen[i]=(day_on && !new_day && BufDCount[i]>=1.0 ? BufDOpenRaw[i] : EMPTY_VALUE);
      BufPwh[i]=(week_on && !new_week ? BufPWH[i] : EMPTY_VALUE);
      BufPwl[i]=(week_on && !new_week ? BufPWL[i] : EMPTY_VALUE);
      BufWOpen[i]=(week_on && !new_week && BufWCount[i]>=1.0 ? BufWOpenRaw[i] : EMPTY_VALUE);

      //--- session membership
      int mask=0;
      if(intraday)
        {
         if(g_clock.InSession(time[i],XAU_ZONE_TOKYO,InpAsiaStart,InpAsiaEnd))
            mask|=1;
         if(g_clock.InSession(time[i],XAU_ZONE_LONDON,InpLondonStart,InpLondonEnd))
            mask|=2;
         if(g_clock.InSession(time[i],XAU_ZONE_NEWYORK,InpNYStart,InpNYEnd))
            mask|=4;
        }
      BufSess[i]=mask;
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
void DrawSessions(const int bit,const string name,const uint rgb,const int min_idx)
  {
   int last=g_total-1;
   int from=g_map.From(),to=g_map.To();
   int rs=-1;
   double hi=0.0,lo=0.0;
   for(int i=min_idx; i<=last+1; i++)
     {
      bool inside=(i<=last && (((int)BufSess[i])&bit)!=0);
      if(inside)
        {
         if(rs<0)
           {
            rs=i;
            hi=g_high[i];
            lo=g_low[i];
           }
         else
           {
            hi=MathMax(hi,g_high[i]);
            lo=MathMin(lo,g_low[i]);
           }
         continue;
        }
      if(rs<0)
         continue;
      int re=i-1;
      if(re>=from && rs<=to)
        {
         double half=g_map.spacing*0.5;
         double x1=g_map.X(rs)-half,x2=g_map.X(re)+half;
         double y1=g_map.Y(hi),y2=g_map.Y(lo);
         double k=g_back.K();
         g_back.RoundRect(x1,y1,x2,y2,3.0*k,XRgb(rgb,0.07),XRgb(rgb,0.40),1.0);
         g_back.RoundRect(x1,y1,x2,y1+2.0*k,1.0*k,XRgb(rgb,0.55));
         g_front.SetFont(XAU_FONT,7.5,FW_SEMIBOLD);
         g_front.Text(x1+3.0*k,y1-3.0*k,name+"  "+DoubleToString(hi-lo,2),XRgb(rgb,0.95),TA_LEFT|TA_BOTTOM);
        }
      rs=-1;
     }
  }

void Render()
  {
   if(g_total<2)
      return;
   int sub=ChartWindowFind();
   if(sub<0)
      sub=0;
   if(!g_map.Update(sub,g_total))
      return;
   if(!XBegin(g_back,"XAU.Sessions.back",g_map,true) || !XBegin(g_front,"XAU.Sessions.front",g_map,false))
      return;
   int last=g_total-1;
   double k=g_front.K();

   //--- session boxes over the last N trading days
   if(InpShowSessions && PeriodSeconds()<14400)
     {
      int min_idx=last;
      long cur=(long)BufKey[last];
      int days=1;
      for(int i=last; i>=0; i--)
        {
         if((long)BufKey[i]!=cur)
           {
            cur=(long)BufKey[i];
            days++;
            if(days>InpSessionDays)
               break;
           }
         min_idx=i;
        }
      if(InpShowAsia)
         DrawSessions(1,"ASIA",g_t.violet,min_idx);
      if(InpShowLondon)
         DrawSessions(2,"LONDON",g_t.blue,min_idx);
      if(InpShowNY)
         DrawSessions(4,"NEW YORK",g_t.orange,min_idx);
     }

   //--- level lines
   XStrokeSeries(g_front,g_map,BufPdh,XRgb(g_t.bull,0.95),1.0);
   XStrokeSeries(g_front,g_map,BufPdl,XRgb(g_t.bear,0.95),1.0);
   XStrokeSeries(g_front,g_map,BufPdc,XRgb(g_t.silver,0.75),1.0,1.5,2.5);
   XStrokeSeries(g_front,g_map,BufDOpen,XRgb(g_t.gold,0.95),1.0,5.0,4.0);
   XStrokeSeries(g_front,g_map,BufPwh,XRgb(g_t.blue,0.95),2.0);
   XStrokeSeries(g_front,g_map,BufPwl,XRgb(g_t.violet,0.95),2.0);
   XStrokeSeries(g_front,g_map,BufWOpen,XRgb(g_t.orange,0.95),1.0,5.0,4.0);

   double x_last=g_map.X(last);
   double x_tag=x_last+MathMax(4.0*g_map.spacing,22.0*k);

   //--- extensions + tags for the live levels
   if(InpShowTags)
     {
      XauTag tags[];
      int n=0;
      string names[7]= {"PDH","PDL","PDC","DO","PWH","PWL","WO"};
      uint   cols[7];
      cols[0]=g_t.bull;
      cols[1]=g_t.bear;
      cols[2]=g_t.silver;
      cols[3]=g_t.gold;
      cols[4]=g_t.blue;
      cols[5]=g_t.violet;
      cols[6]=g_t.orange;
      double vals[7];
      vals[0]=BufPdh[last];
      vals[1]=BufPdl[last];
      vals[2]=BufPdc[last];
      vals[3]=BufDOpen[last];
      vals[4]=BufPwh[last];
      vals[5]=BufPwl[last];
      vals[6]=BufWOpen[last];
      for(int j=0; j<7; j++)
        {
         if(!XOk(vals[j]))
            continue;
         double y=g_map.Y(vals[j]);
         g_front.Line(x_last,y,x_tag,y,XRgb(cols[j],0.55),1.0,2.0,2.0);
         XAddTag(tags,n,y,names[j]+" "+DoubleToString(vals[j],2),XRgb(cols[j],0.92),XRgb(g_t.ink,1.0));
        }
      XDrawTags(g_front,tags,n,x_tag,7.5);
     }

   //--- psychological round numbers around the current price
   double px=iClose(_Symbol,_Period,0);
   if(InpShowRound && px>0.0 && InpRoundStep>0.0)
     {
      double base=MathFloor(px/InpRoundStep)*InpRoundStep;
      int left=MathMax(0,last-150);
      double x1=g_map.X(left);
      double x2=x_last+MathMax(12.0*g_map.spacing,70.0*k);
      g_front.SetFont(XAU_FONT,7.5,FW_NORMAL);
      for(int j=0; j<2*InpRoundCount; j++)
        {
         double lvl=base+(double)(j-InpRoundCount+1)*InpRoundStep;
         double y=g_map.Y(lvl);
         g_front.Line(x1,y,x2,y,XRgb(g_t.silver,0.40),1.0,1.5,3.0);
         g_front.Text(x2+3.0*k,y,DoubleToString(lvl,0),XRgb(g_t.silver,0.85),TA_LEFT|TA_VCENTER);
        }
     }

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
