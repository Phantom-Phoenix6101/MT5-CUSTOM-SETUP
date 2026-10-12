//+------------------------------------------------------------------+
//|                                            XAU_CommandCenter.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| One-glance dashboard: multi-timeframe trend / RSI / ADX matrix,   |
//| weighted bias verdict with gauge, active session, daily change,   |
//| ADR usage, position in the day's range, distance to PDH / PDL,    |
//| ATR volatility regime and a plain-language read.                  |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU Command Center - multi-timeframe bias dashboard with ADR, PDH/PDL and volatility."
#property description "Smooth anti-aliased rendering."
#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   0

#include <XauSuite/XauSuite.mqh>

enum ENUM_XAU_CORNER
  {
   XAU_CORNER_TR=0, // Top right
   XAU_CORNER_TL=1, // Top left
   XAU_CORNER_BR=2, // Bottom right
   XAU_CORNER_BL=3  // Bottom left
  };

input group "Timeframes"
input ENUM_TIMEFRAMES   InpTf1       = PERIOD_M15; // Time frame 1
input ENUM_TIMEFRAMES   InpTf2       = PERIOD_H1;  // Time frame 2
input ENUM_TIMEFRAMES   InpTf3       = PERIOD_H4;  // Time frame 3
input ENUM_TIMEFRAMES   InpTf4       = PERIOD_D1;  // Time frame 4
input group "Day"
input int               InpAdrLen    = 14;   // ADR length (days)
input ENUM_XAU_DAY_ROLL InpDayRoll   = XAU_ROLL_NY17; // Trading day starts at
input double            InpServerGMT = 99;   // Server GMT offset, hours (99 = auto-detect)
input ENUM_XAU_DST      InpServerDST = XAU_DST_US; // Server daylight-saving rule
input group "Layout & style"
input ENUM_XAU_CORNER   InpCorner    = XAU_CORNER_TR; // Dashboard position
input int               InpFontSize  = 11;   // Size (11 = default)
input int               InpMargin    = 12;   // Distance from the chart edge (px)
input ENUM_XAU_THEME    InpTheme     = XAU_THEME_AUTO; // Colour theme

double BufKey[],BufDHigh[],BufDLow[],BufDOpen[],BufOrd[],BufPHigh[],BufPLow[],BufGain[],BufLoss[],BufRsi[],BufAtr[];

XauTheme        g_t;
CXauClock       g_clock;
CXauCanvas      g_cv;
CXauGate        g_gate;
int             g_total=0;
double          g_ranges[];
double          g_last_close=0.0;
datetime        g_last_time=0;
ENUM_TIMEFRAMES g_tfs[4];
int             g_hFast[4],g_hSlow[4],g_hRsi[4],g_hAdx[4];
double          g_s=1.0;   // layout scale = DPI x size input

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   g_clock.Init(InpServerGMT,InpServerDST);
   SetIndexBuffer(0,BufKey,INDICATOR_CALCULATIONS);
   SetIndexBuffer(1,BufDHigh,INDICATOR_CALCULATIONS);
   SetIndexBuffer(2,BufDLow,INDICATOR_CALCULATIONS);
   SetIndexBuffer(3,BufDOpen,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,BufOrd,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,BufPHigh,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,BufPLow,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,BufGain,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,BufLoss,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,BufRsi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,BufAtr,INDICATOR_CALCULATIONS);
   g_tfs[0]=InpTf1;
   g_tfs[1]=InpTf2;
   g_tfs[2]=InpTf3;
   g_tfs[3]=InpTf4;
   for(int j=0; j<4; j++)
     {
      g_hFast[j]=iMA(_Symbol,g_tfs[j],20,0,MODE_EMA,PRICE_CLOSE);
      g_hSlow[j]=iMA(_Symbol,g_tfs[j],50,0,MODE_EMA,PRICE_CLOSE);
      g_hRsi[j]=iRSI(_Symbol,g_tfs[j],14,PRICE_CLOSE);
      g_hAdx[j]=iADXWilder(_Symbol,g_tfs[j],14);
     }
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Command Center");
   g_gate.Init(300);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   g_gate.Stop();
   g_cv.Destroy();
   for(int j=0; j<4; j++)
     {
      if(g_hFast[j]!=INVALID_HANDLE)
         IndicatorRelease(g_hFast[j]);
      if(g_hSlow[j]!=INVALID_HANDLE)
         IndicatorRelease(g_hSlow[j]);
      if(g_hRsi[j]!=INVALID_HANDLE)
         IndicatorRelease(g_hRsi[j]);
      if(g_hAdx[j]!=INVALID_HANDLE)
         IndicatorRelease(g_hAdx[j]);
     }
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
   for(int i=start; i<rates_total; i++)
     {
      long key=g_clock.DayKey(time[i],InpDayRoll);
      BufKey[i]=(double)key;
      bool new_day=(i>0 && key!=(long)BufKey[i-1]);
      int ord=(i>0 ? (int)BufOrd[i-1] : 0);
      BufPHigh[i]=(i>0 ? BufPHigh[i-1] : EMPTY_VALUE);
      BufPLow[i]=(i>0 ? BufPLow[i-1] : EMPTY_VALUE);
      if(new_day)
        {
         if(ord>=1)
           {
            BufPHigh[i]=BufDHigh[i-1];
            BufPLow[i]=BufDLow[i-1];
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

      double ch=(i>0 ? close[i]-close[i-1] : 0.0);
      BufGain[i]=XRmaStep(i>0 ? BufGain[i-1] : EMPTY_VALUE,MathMax(ch,0.0),14);
      BufLoss[i]=XRmaStep(i>0 ? BufLoss[i-1] : EMPTY_VALUE,MathMax(-ch,0.0),14);
      double up=BufGain[i],dn=BufLoss[i];
      BufRsi[i]=(i<14 ? EMPTY_VALUE : (dn==0.0 ? 100.0 : (up==0.0 ? 0.0 : 100.0-100.0/(1.0+up/dn))));
      double tr=XTrueRange(high[i],low[i],i>0 ? close[i-1] : EMPTY_VALUE);
      BufAtr[i]=XRmaStep(i>0 ? BufAtr[i-1] : EMPTY_VALUE,tr,14);
     }
   g_total=rates_total;
   g_last_close=close[rates_total-1];
   g_last_time=time[rates_total-1];
   if(g_gate.Request(prev_calculated!=rates_total))
      Render();
   return(rates_total);
  }

void OnTimer()
  {
   // the timer also refreshes the higher time frames when the chart time frame is quiet
   g_gate.Touch();
   if(g_gate.Pending())
      Render();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      Render();
  }

//+------------------------------------------------------------------+
//| Multi-timeframe trend read: same rules as the Indie SecTrend      |
//+------------------------------------------------------------------+
bool ReadTf(const int j,double &bias,double &rsi,double &adx)
  {
   bias=EMPTY_VALUE;
   rsi=EMPTY_VALUE;
   adx=EMPTY_VALUE;
   double f[],s[],r[],a[];
   ArraySetAsSeries(f,true);
   ArraySetAsSeries(s,true);
   if(CopyBuffer(g_hFast[j],0,0,2,f)<2)
      return(false);
   double c=iClose(_Symbol,g_tfs[j],0);
   if(c<=0.0)
      return(false);
   bool have_slow=(CopyBuffer(g_hSlow[j],0,0,1,s)==1 && XOk(s[0]) && Bars(_Symbol,g_tfs[j])>=50);
   bias=0.0;
   if(have_slow)
     {
      if(c>f[0] && f[0]>s[0])
         bias=1.0;
      else
         if(c<f[0] && f[0]<s[0])
            bias=-1.0;
         else
            if(f[0]>s[0])
               bias=0.5;
            else
               if(f[0]<s[0])
                  bias=-0.5;
     }
   else
     {
      // short histories on high time frames fall back to price vs a rising / falling fast EMA
      if(c>f[0] && f[0]>=f[1])
         bias=1.0;
      else
         if(c<f[0] && f[0]<=f[1])
            bias=-1.0;
     }
   if(CopyBuffer(g_hRsi[j],0,0,1,r)==1)
      rsi=r[0];
   if(CopyBuffer(g_hAdx[j],0,0,1,a)==1)
      adx=a[0];
   return(true);
  }

//+------------------------------------------------------------------+
//| Drawing helpers                                                  |
//+------------------------------------------------------------------+
double S(const double v) { return(v*g_s); }

void TrendChip(const double cx,const double cy,const double bias)
  {
   uint rgb=g_t.neutral;
   string text="FLAT";
   int dir=0;
   bool strong=false;
   if(XOk(bias) && bias!=0.0)
     {
      dir=(bias>0.0 ? 1 : -1);
      strong=(MathAbs(bias)>=1.0);
      rgb=(dir>0 ? g_t.bull : g_t.bear);
      text=(dir>0 ? (strong ? "BULL" : "bull") : (strong ? "BEAR" : "bear"));
     }
   else
      if(!XOk(bias))
         text="-";
   double w=S(64.0),h=S(17.0);
   double l=cx-w*0.5,t=cy-h*0.5;
   g_cv.RoundRect(l,t,l+w,t+h,h*0.5,XRgb(rgb,strong ? 0.24 : 0.13));
   double ix=l+S(13.0),iy=cy,sz=S(4.0);
   if(dir>0)
      g_cv.Triangle(ix-sz,iy+sz*0.8,ix+sz,iy+sz*0.8,ix,iy-sz,XRgb(rgb,strong ? 1.0 : 0.6));
   else
      if(dir<0)
         g_cv.Triangle(ix-sz,iy-sz*0.8,ix+sz,iy-sz*0.8,ix,iy+sz,XRgb(rgb,strong ? 1.0 : 0.6));
      else
         g_cv.RoundRect(ix-sz*0.8,iy-sz*0.8,ix+sz*0.8,iy+sz*0.8,S(1.0),XRgb(rgb,0.8));
   g_cv.SetFont(XAU_FONT,7.5*g_s/g_cv.K(),FW_BOLD);
   g_cv.Text(l+w-S(10.0),cy,text,XRgb(rgb,1.0),TA_RIGHT|TA_VCENTER);
  }

void Chip(const double x,const double cy,const string text,const uint rgb,const double pt,const bool right_align)
  {
   double w=0.0,h=0.0;
   g_cv.PillSize(text,pt,w,h);
   double cx=(right_align ? x-w*0.5 : x+w*0.5);
   g_cv.Pill(cx,cy,text,XRgb(rgb,0.20),XRgb(rgb,1.0),XA_CENTER,pt);
  }

void Label(const double x,const double y,const string text,const uint c,const double pt,const uint weight,const uint align)
  {
   g_cv.SetFont(XAU_FONT,pt*g_s/g_cv.K(),weight);
   g_cv.Text(x,y,text,c,align);
  }

void Divider(const double x,const double y,const double w)
  {
   g_cv.FillRect(x,y,x+w,y+MathMax(1.0,g_cv.K()),XRgb(g_t.border,1.0));
  }

//+------------------------------------------------------------------+
void Render()
  {
   if(g_total<3)
      return;
   int last=g_total-1;
   g_s=g_cv.K()*XClamp(InpFontSize/11.0,0.7,1.8);

   //--- data
   double bias[4],rsi[4],adx[4];
   double score=0.0,weight=0.0;
   double weights[4]= {1.0,1.0,1.5,2.0};
   for(int j=0; j<4; j++)
     {
      ReadTf(j,bias[j],rsi[j],adx[j]);
      if(XOk(bias[j]))
        {
         score+=bias[j]*weights[j];
         weight+=weights[j];
        }
     }
   double score_pct=(weight>0.0 ? 100.0*score/weight : EMPTY_VALUE);
   string verdict="NEUTRAL";
   uint vrgb=g_t.neutral;
   if(XOk(score_pct))
     {
      if(score_pct>=60.0)
        {
         verdict="STRONG BULL";
         vrgb=g_t.bull;
        }
      else
         if(score_pct>=20.0)
           {
            verdict="BULLISH";
            vrgb=g_t.bull;
           }
         else
            if(score_pct<=-60.0)
              {
               verdict="STRONG BEAR";
               vrgb=g_t.bear;
              }
            else
               if(score_pct<=-20.0)
                 {
                  verdict="BEARISH";
                  vrgb=g_t.bear;
                 }
     }

   string session="Off-hours";
   bool lon=g_clock.InSession(g_last_time,XAU_ZONE_LONDON,8,16);
   bool ny=g_clock.InSession(g_last_time,XAU_ZONE_NEWYORK,8,17);
   if(lon && ny)
      session="London / NY overlap";
   else
      if(ny)
         session="New York";
      else
         if(lon)
            session="London";
         else
            if(g_clock.InSession(g_last_time,XAU_ZONE_TOKYO,9,15))
               session="Asia";

   double px=g_last_close;
   double dopen=BufDOpen[last];
   double day_change=(XOk(dopen) && dopen>0.0 ? 100.0*(px-dopen)/dopen : EMPTY_VALUE);
   double used=BufDHigh[last]-BufDLow[last];
   double adr=EMPTY_VALUE;
   int done=(int)BufOrd[last]-1;
   if(done>0 && ArraySize(g_ranges)>=done)
     {
      int take=MathMin(InpAdrLen,done);
      double sum=0.0;
      for(int j=done-take; j<done; j++)
         sum+=g_ranges[j];
      adr=sum/take;
     }
   double pos=(used>0.0 ? 100.0*(px-BufDLow[last])/used : EMPTY_VALUE);
   double pdh=BufPHigh[last],pdl=BufPLow[last];
   double atr=BufAtr[last];
   int cnt=0,avail=0;
   for(int j=1; j<=100 && last-j>=0; j++)
     {
      avail++;
      if(BufAtr[last-j]<=atr)
         cnt++;
     }
   double rank=(avail>0 ? 100.0*cnt/avail : 50.0);
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
   double rsi0=BufRsi[last];
   string plan="Range: fade extremes or wait for a break";
   if(XOk(score_pct) && score_pct>=20.0)
      plan=(rsi0<70.0 ? "Buy pullbacks" : "Bullish but stretched: wait for a dip");
   else
      if(XOk(score_pct) && score_pct<=-20.0)
         plan=(rsi0>30.0 ? "Sell rallies" : "Bearish but stretched: wait for a bounce");

   //--- layout
   double pad=S(14.0);
   double W=S(318.0);
   double row=S(23.0);
   double info=S(21.0);
   double H=pad+S(26.0)+S(18.0)+S(12.0)+S(18.0)+4.0*row+S(12.0)+S(46.0)+S(10.0)+5.0*info+S(10.0)+S(20.0)+pad;
   double shadow=S(6.0);
   int cw=(int)MathCeil(W+2.0*shadow),ch=(int)MathCeil(H+2.0*shadow);
   int chart_w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int chart_h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int m=(int)MathRound(InpMargin*g_cv.K());
   int cx=(InpCorner==XAU_CORNER_TL || InpCorner==XAU_CORNER_BL ? m : chart_w-cw-m);
   int cy=(InpCorner==XAU_CORNER_BR || InpCorner==XAU_CORNER_BL ? chart_h-ch-m : m);
   if(cx<0)
      cx=0;
   if(cy<0)
      cy=0;
   if(!g_cv.Attach("XAU.CommandCenter",0,false) || !g_cv.Place(cx,cy,cw,ch))
      return;
   g_cv.Clear();

   double x0=shadow,y0=shadow;
   g_cv.Card(x0,y0,W,H,XRgb(g_t.panel,0.94),XRgb(g_t.border,1.0),XRgb(g_t.gold,0.95));
   double l=x0+pad,r=x0+W-pad,iw=W-2.0*pad;
   double y=y0+pad;

   //--- header: symbol, price, change
   Label(l,y+S(9.0),XPrettySymbol(_Symbol),XRgb(g_t.gold,1.0),11.0,FW_BOLD,TA_LEFT|TA_VCENTER);
   Label(l+S(84.0),y+S(9.0),DoubleToString(px,_Digits),XRgb(g_t.text,1.0),11.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   if(XOk(day_change))
     {
      uint crgb=(day_change>=0.0 ? g_t.bull : g_t.bear);
      double w=0.0,h=0.0;
      string ct=XSigned(day_change,2)+"%";
      g_cv.PillSize(ct,8.0*g_s/g_cv.K(),w,h);
      g_cv.Pill(r-w*0.5,y+S(9.0),ct,XRgb(crgb,1.0),XRgb(g_t.ink,1.0),XA_CENTER,8.0*g_s/g_cv.K());
     }
   y+=S(26.0);
   g_cv.Circle(l+S(4.0),y+S(8.0),S(3.5),XRgb(session=="Off-hours" ? g_t.muted : g_t.gold,1.0));
   Label(l+S(13.0),y+S(8.0),session,XRgb(session=="Off-hours" ? g_t.muted : g_t.gold,1.0),8.0,FW_SEMIBOLD,
         TA_LEFT|TA_VCENTER);
   Label(r,y+S(8.0),TimeToString(g_last_time,TIME_MINUTES)+" server",XRgb(g_t.muted,1.0),7.5,FW_NORMAL,
         TA_RIGHT|TA_VCENTER);
   y+=S(18.0);
   Divider(l,y+S(5.0),iw);
   y+=S(12.0);

   //--- timeframe matrix
   double c1=l+S(44.0),c2=l+S(170.0),c3=r;
   Label(l,y+S(8.0),"TF",XRgb(g_t.muted,1.0),7.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   Label(c1+S(32.0),y+S(8.0),"TREND",XRgb(g_t.muted,1.0),7.0,FW_SEMIBOLD,TA_CENTER|TA_VCENTER);
   Label(c2,y+S(8.0),"RSI",XRgb(g_t.muted,1.0),7.0,FW_SEMIBOLD,TA_CENTER|TA_VCENTER);
   Label(c3,y+S(8.0),"ADX",XRgb(g_t.muted,1.0),7.0,FW_SEMIBOLD,TA_RIGHT|TA_VCENTER);
   y+=S(18.0);
   for(int j=0; j<4; j++)
     {
      double cyr=y+row*0.5;
      if(j%2==0)
         g_cv.RoundRect(l-S(6.0),y+S(1.0),r+S(6.0),y+row-S(1.0),S(5.0),XRgb(g_t.border,0.35));
      Label(l,cyr,XTfName(g_tfs[j]),XRgb(g_t.gold,1.0),8.5,FW_BOLD,TA_LEFT|TA_VCENTER);
      TrendChip(c1+S(32.0),cyr,bias[j]);
      uint rc=g_t.text;
      if(XOk(rsi[j]))
        {
         if(rsi[j]>=70.0)
            rc=g_t.bear;
         else
            if(rsi[j]<=30.0)
               rc=g_t.bull;
            else
               if(rsi[j]>=55.0)
                  rc=g_t.bull;
               else
                  if(rsi[j]<=45.0)
                     rc=g_t.bear;
        }
      Label(c2,cyr,XNum(rsi[j],1),XRgb(rc,1.0),8.5,FW_SEMIBOLD,TA_CENTER|TA_VCENTER);
      string at=XNum(adx[j],0);
      uint ac=g_t.text;
      if(XOk(adx[j]))
        {
         if(adx[j]>=25.0)
           {
            at=at+" trend";
            ac=g_t.gold;
           }
         else
            if(adx[j]<18.0)
              {
               at=at+" range";
               ac=g_t.muted;
              }
        }
      else
         ac=g_t.muted;
      Label(c3,cyr,at,XRgb(ac,1.0),8.0,FW_SEMIBOLD,TA_RIGHT|TA_VCENTER);
      y+=row;
     }
   Divider(l,y+S(5.0),iw);
   y+=S(12.0);

   //--- bias verdict + gauge
   Label(l,y+S(10.0),"BIAS",XRgb(g_t.muted,1.0),7.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   double vw=0.0,vh=0.0;
   g_cv.PillSize(verdict,9.0*g_s/g_cv.K(),vw,vh);
   g_cv.Pill(l+S(44.0)+vw*0.5,y+S(10.0),verdict,XRgb(vrgb,1.0),XRgb(g_t.ink,1.0),XA_CENTER,9.0*g_s/g_cv.K());
   Label(r,y+S(10.0),XSigned(score_pct,0)+"%",XRgb(vrgb,1.0),10.0,FW_BOLD,TA_RIGHT|TA_VCENTER);
   double gy=y+S(28.0),gh=S(6.0);
   int seg=40;
   for(int q=0; q<seg; q++)
     {
      double f=(q+0.5)/seg;
      uint c=(f<0.5 ? XLerp(XRgb(g_t.bear,0.9),XRgb(g_t.neutral,0.35),f/0.5)
              : XLerp(XRgb(g_t.neutral,0.35),XRgb(g_t.bull,0.9),(f-0.5)/0.5));
      double sx=l+iw*q/seg,ex=l+iw*(q+1)/seg;
      if(q==0)
         g_cv.RoundRect(sx,gy,ex+gh,gy+gh,gh*0.5,c);
      else
         if(q==seg-1)
            g_cv.RoundRect(sx-gh,gy,ex,gy+gh,gh*0.5,c);
         else
            g_cv.FillRect(sx,gy,ex,gy+gh,c);
     }
   g_cv.FillRect(l+iw*0.5-S(0.5),gy-S(3.0),l+iw*0.5+S(0.5),gy+gh+S(3.0),XRgb(g_t.muted,0.8));
   if(XOk(score_pct))
     {
      double mx=l+iw*XClamp((score_pct+100.0)/200.0,0.0,1.0);
      g_cv.Circle(mx,gy+gh*0.5,S(6.0),XRgb(g_t.panel,1.0),XRgb(vrgb,1.0),S(2.0));
     }
   Label(l,gy+gh+S(9.0),"bear",XRgb(g_t.muted,1.0),7.0,FW_NORMAL,TA_LEFT|TA_VCENTER);
   Label(r,gy+gh+S(9.0),"bull",XRgb(g_t.muted,1.0),7.0,FW_NORMAL,TA_RIGHT|TA_VCENTER);
   y+=S(46.0);
   Divider(l,y+S(4.0),iw);
   y+=S(10.0);

   //--- info rows
   double vx=l+S(84.0);
   //  ADR usage
   double cyr=y+info*0.5;
   Label(l,cyr,"ADR("+IntegerToString(InpAdrLen)+")",XRgb(g_t.muted,1.0),8.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   if(XOk(adr) && adr>0.0)
     {
      double pct=100.0*used/adr;
      uint fc=(pct>=100.0 ? g_t.orange : (pct>=70.0 ? g_t.gold : g_t.bull));
      Label(vx,cyr,"$"+DoubleToString(adr,2),XRgb(g_t.text,1.0),8.5,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
      g_cv.Bar(vx+S(62.0),cyr-S(3.0),iw-S(84.0)-S(62.0)-S(40.0),S(6.0),pct/100.0,XRgb(g_t.border,1.0),XRgb(fc,1.0));
      Label(r,cyr,DoubleToString(pct,0)+"%",XRgb(fc,1.0),8.5,FW_BOLD,TA_RIGHT|TA_VCENTER);
     }
   else
      Label(vx,cyr,"-",XRgb(g_t.muted,1.0),8.5,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   y+=info;
   //  position in the day's range
   cyr=y+info*0.5;
   Label(l,cyr,"Day range",XRgb(g_t.muted,1.0),8.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   if(XOk(pos))
     {
      double bx=vx,bw=iw-S(84.0)-S(40.0);
      g_cv.RoundRect(bx,cyr-S(3.0),bx+bw,cyr+S(3.0),S(3.0),XRgb(g_t.border,1.0));
      double mx=bx+bw*XClamp(pos/100.0,0.0,1.0);
      uint pc=(pos>=50.0 ? g_t.bull : g_t.bear);
      g_cv.Circle(mx,cyr,S(5.0),XRgb(pc,1.0),XRgb(g_t.panel,1.0),S(1.5));
      Label(r,cyr,DoubleToString(pos,0)+"%",XRgb(pc,1.0),8.5,FW_BOLD,TA_RIGHT|TA_VCENTER);
     }
   y+=info;
   //  PDH / PDL
   cyr=y+info*0.5;
   Label(l,cyr,"PDH",XRgb(g_t.muted,1.0),8.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   Label(vx,cyr,XNum(pdh,2),XRgb(g_t.bear,1.0),8.5,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   Label(r,cyr,XOk(pdh) ? XSigned(pdh-px,2)+" away" : "-",XRgb(g_t.text,0.85),8.0,FW_NORMAL,TA_RIGHT|TA_VCENTER);
   y+=info;
   cyr=y+info*0.5;
   Label(l,cyr,"PDL",XRgb(g_t.muted,1.0),8.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   Label(vx,cyr,XNum(pdl,2),XRgb(g_t.bull,1.0),8.5,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   Label(r,cyr,XOk(pdl) ? XSigned(px-pdl,2)+" above" : "-",XRgb(g_t.text,0.85),8.0,FW_NORMAL,TA_RIGHT|TA_VCENTER);
   y+=info;
   //  ATR regime
   cyr=y+info*0.5;
   Label(l,cyr,"ATR(14)",XRgb(g_t.muted,1.0),8.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   Label(vx,cyr,"$"+XNum(atr,2),XRgb(g_t.text,1.0),8.5,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);
   Chip(r,cyr,regime,regime_rgb,7.0*g_s/g_cv.K(),true);
   y+=info;
   Divider(l,y+S(4.0),iw);
   y+=S(10.0);

   //--- plain-language read
   g_cv.RoundRect(l-S(6.0),y,r+S(6.0),y+S(20.0),S(6.0),XRgb(vrgb,0.12));
   g_cv.FillRect(l-S(6.0),y+S(4.0),l-S(4.0),y+S(16.0),XRgb(vrgb,1.0));
   Label(l+S(4.0),y+S(10.0),plan,XRgb(vrgb==g_t.neutral ? g_t.text : vrgb,1.0),8.0,FW_SEMIBOLD,TA_LEFT|TA_VCENTER);

   g_cv.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
