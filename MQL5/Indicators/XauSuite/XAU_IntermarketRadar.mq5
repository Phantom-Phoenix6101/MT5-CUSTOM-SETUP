//+------------------------------------------------------------------+
//|                                         XAU_IntermarketRadar.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Rolling correlation of gold returns with the US dollar index and  |
//| silver, plus the gold / silver ratio z-score, with a read-out     |
//| card. Broker symbols are detected automatically (prefix / suffix  |
//| aware); without a dollar index CFD, DXY is synthesised from the   |
//| six ICE basket pairs.                                             |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "XAU Intermarket Radar - gold vs DXY and silver correlation, gold/silver ratio z-score."
#property description "Smooth anti-aliased rendering."
#property indicator_separate_window
#property indicator_minimum -1.05
#property indicator_maximum 1.05
#property indicator_buffers 9
#property indicator_plots   3

#property indicator_label1  "Gold/Silver ratio z-score (scaled /3)"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Gold vs DXY correlation"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Gold vs silver correlation"
#property indicator_type3   DRAW_NONE

#include <XauSuite/XauSuite.mqh>

input group "Symbols"
input string         InpDxySymbol    = "";   // US dollar index symbol (empty = auto / synthetic)
input string         InpSilverSymbol = "";   // Silver symbol (empty = auto)
input group "Analysis"
input int            InpCorrLen      = 50;   // Correlation length (bars)
input int            InpRatioLen     = 100;  // Gold/silver ratio z-score length
input int            InpMaxBars      = 3000; // Bars to analyse
input bool           InpShowPanel    = true; // Show intermarket read-out
input group "Style"
input ENUM_XAU_THEME InpTheme        = XAU_THEME_MIDNIGHT; // Colour theme

double BufZ[],BufDxyCorr[],BufXagCorr[];
double BufGoldRet[],BufDxyRet[],BufXagRet[],BufRatio[],BufDxy[],BufXag[];

XauTheme   g_t;
CXauCanvas g_back;
CXauCanvas g_front;
CXauMap    g_map;
CXauGate   g_gate;
int        g_total=0;
uint       g_zcols[],g_dcols[];
string     g_dxy="";        // real dollar index symbol, "" when synthetic
string     g_xag="";
string     g_basket[6];
double     g_basket_exp[6];
bool       g_basket_ok[6];
bool       g_synthetic=false;
bool       g_waiting=false;

//+------------------------------------------------------------------+
//| Symbol discovery                                                 |
//+------------------------------------------------------------------+
string g_pre="",g_suf="";

void DetectAffixes()
  {
   string up=_Symbol;
   StringToUpper(up);
   int pos=StringFind(up,"XAU");
   if(pos<0)
      pos=StringFind(up,"GOLD");
   if(pos<0)
      return;
   g_pre=StringSubstr(_Symbol,0,pos);
   int core=(StringFind(up,"XAU")==pos ? 6 : 4);
   if(StringLen(_Symbol)>pos+core)
      g_suf=StringSubstr(_Symbol,pos+core);
  }

bool SymbolUsable(const string name)
  {
   if(name=="")
      return(false);
   bool custom=false;
   if(!SymbolExist(name,custom))
      return(false);
   SymbolSelect(name,true);
   return(true);
  }

string Resolve(const string &candidates[])
  {
   for(int i=0; i<ArraySize(candidates); i++)
     {
      string c=candidates[i];
      if(SymbolUsable(g_pre+c+g_suf))
         return(g_pre+c+g_suf);
      if(SymbolUsable(c+g_suf))
         return(c+g_suf);
      if(SymbolUsable(c))
         return(c);
     }
   return("");
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   XauLoadTheme(InpTheme,g_t);
   SetIndexBuffer(0,BufZ,INDICATOR_DATA);
   SetIndexBuffer(1,BufDxyCorr,INDICATOR_DATA);
   SetIndexBuffer(2,BufXagCorr,INDICATOR_DATA);
   SetIndexBuffer(3,BufGoldRet,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,BufDxyRet,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,BufXagRet,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,BufRatio,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,BufDxy,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,BufXag,INDICATOR_CALCULATIONS);
   for(int p=0; p<3; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   DetectAffixes();
   string dxy_names[]= {"USDX","DXY","USDIDX","DX","USDINDEX","DOLLARINDEX","USIDX","DXY.cash","USDX.F","DX.f"};
   string xag_names[]= {"XAGUSD","SILVER","XAG/USD"};
   g_dxy=(InpDxySymbol!="" && SymbolUsable(InpDxySymbol) ? InpDxySymbol : (InpDxySymbol=="" ? Resolve(dxy_names) : ""));
   g_xag=(InpSilverSymbol!="" && SymbolUsable(InpSilverSymbol) ? InpSilverSymbol : Resolve(xag_names));

   //--- ICE dollar index basket: 50.14348112 * EURUSD^-0.576 * USDJPY^0.136 * GBPUSD^-0.119 * USDCAD^0.091 * USDSEK^0.042 * USDCHF^0.036
   string pairs[6]= {"EURUSD","USDJPY","GBPUSD","USDCAD","USDSEK","USDCHF"};
   double exps[6]= {-0.576,0.136,-0.119,0.091,0.042,0.036};
   g_synthetic=(g_dxy=="");
   for(int j=0; j<6; j++)
     {
      string one[1];
      one[0]=pairs[j];
      g_basket[j]=Resolve(one);
      g_basket_ok[j]=(g_basket[j]!="");
      g_basket_exp[j]=exps[j];
     }
   if(g_synthetic && !g_basket_ok[0])
      Print("XAU Intermarket Radar: no dollar index or EURUSD found - DXY correlation disabled");
   if(g_xag=="")
      Print("XAU Intermarket Radar: no silver symbol found - set it in the inputs");

   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Intermarket Radar");
   IndicatorSetInteger(INDICATOR_DIGITS,2);
   g_gate.Init(250);
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
//| Other-symbol data, aligned to the chart bar opening at t          |
//+------------------------------------------------------------------+
bool Synced(const string sym)
  {
   if(sym=="")
      return(true);
   Bars(sym,_Period);
   return((bool)SeriesInfoInteger(sym,_Period,SERIES_SYNCHRONIZED));
  }

double CloseAt(const string sym,const datetime t)
  {
   if(sym=="")
      return(EMPTY_VALUE);
   int sh=iBarShift(sym,_Period,t,false);
   if(sh<0)
      return(EMPTY_VALUE);
   // never look ahead: use the bar that opened at or before t
   if(iTime(sym,_Period,sh)>t)
      sh++;
   double c=iClose(sym,_Period,sh);
   return(c>0.0 ? c : EMPTY_VALUE);
  }

double DxyAt(const datetime t)
  {
   if(!g_synthetic)
      return(CloseAt(g_dxy,t));
   if(!g_basket_ok[0])
      return(EMPTY_VALUE);
   double v=50.14348112;
   for(int j=0; j<6; j++)
     {
      if(!g_basket_ok[j])
         continue;  // missing minor legs only rescale the level; returns are unaffected in sign and timing
      double c=CloseAt(g_basket[j],t);
      if(!XOk(c))
         return(EMPTY_VALUE);
      v*=MathPow(c,g_basket_exp[j]);
     }
   return(v);
  }

double Ret(const double cur,const double prev)
  {
   if(!XOk(cur) || !XOk(prev) || prev<=0.0)
      return(EMPTY_VALUE);
   return(cur/prev-1.0);
  }

double Corr(const double &x[],const double &y[],const int i,const int len)
  {
   double sx=0.0,sy=0.0,sxx=0.0,syy=0.0,sxy=0.0;
   int n=0;
   for(int j=MathMax(0,i-len+1); j<=i; j++)
     {
      if(!XOk(x[j]) || !XOk(y[j]))
         continue;
      sx+=x[j];
      sy+=y[j];
      sxx+=x[j]*x[j];
      syy+=y[j]*y[j];
      sxy+=x[j]*y[j];
      n++;
     }
   if(n<3)
      return(EMPTY_VALUE);
   double cov=sxy/n-(sx/n)*(sy/n);
   double vx=sxx/n-(sx/n)*(sx/n);
   double vy=syy/n-(sy/n)*(sy/n);
   if(vx<=0.0 || vy<=0.0)
      return(EMPTY_VALUE);
   return(XClamp(cov/MathSqrt(vx*vy),-1.0,1.0));
  }

double ZScore(const double &x[],const int i,const int len)
  {
   if(!XOk(x[i]))
      return(EMPTY_VALUE);
   double s=0.0,ss=0.0;
   int n=0;
   for(int j=MathMax(0,i-len+1); j<=i; j++)
     {
      if(!XOk(x[j]))
         continue;
      s+=x[j];
      ss+=x[j]*x[j];
      n++;
     }
   if(n<3)
      return(EMPTY_VALUE);
   double mean=s/n;
   double var=ss/n-mean*mean;
   if(var<=0.0)
      return(EMPTY_VALUE);
   return((x[i]-mean)/MathSqrt(var));
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<3)
      return(0);
   //--- wait for the other symbols' history before the first full pass
   bool ready=Synced(g_xag) && Synced(g_dxy);
   if(g_synthetic)
      for(int j=0; j<6; j++)
         if(g_basket_ok[j])
            ready=ready && Synced(g_basket[j]);
   if(!ready)
     {
      g_waiting=true;
      return(0);
     }
   g_waiting=false;

   int first=MathMax(1,rates_total-MathMax(InpMaxBars,InpRatioLen+10));
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   for(int i=start; i<rates_total; i++)
     {
      if(i<first)
        {
         BufZ[i]=EMPTY_VALUE;
         BufDxyCorr[i]=EMPTY_VALUE;
         BufXagCorr[i]=EMPTY_VALUE;
         BufGoldRet[i]=EMPTY_VALUE;
         BufDxyRet[i]=EMPTY_VALUE;
         BufXagRet[i]=EMPTY_VALUE;
         BufRatio[i]=EMPTY_VALUE;
         BufDxy[i]=EMPTY_VALUE;
         BufXag[i]=EMPTY_VALUE;
         continue;
        }
      BufDxy[i]=DxyAt(time[i]);
      BufXag[i]=CloseAt(g_xag,time[i]);
      BufGoldRet[i]=Ret(close[i],close[i-1]);
      BufDxyRet[i]=Ret(BufDxy[i],BufDxy[i-1]);
      BufXagRet[i]=Ret(BufXag[i],BufXag[i-1]);
      BufRatio[i]=(XOk(BufXag[i]) ? close[i]/BufXag[i] : EMPTY_VALUE);
      BufDxyCorr[i]=Corr(BufGoldRet,BufDxyRet,i,InpCorrLen);
      BufXagCorr[i]=Corr(BufGoldRet,BufXagRet,i,InpCorrLen);
      double z=ZScore(BufRatio,i,InpRatioLen);
      BufZ[i]=(XOk(z) ? z/3.0 : EMPTY_VALUE);
     }
   g_total=rates_total;
   if(g_gate.Request(prev_calculated!=rates_total))
      Render();
   return(rates_total);
  }

void OnTimer()
  {
   if(g_waiting)
     {
      // history finished loading while the market is quiet: force a full recalculation
      bool ready=Synced(g_xag) && Synced(g_dxy);
      if(ready)
         ChartSetSymbolPeriod(0,_Symbol,_Period);
      return;
     }
   if(g_gate.Pending())
      Render();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      Render();
  }

//+------------------------------------------------------------------+
uint DxyState(const double c,string &state)
  {
   if(!XOk(c))
     {
      state="n/a";
      return(g_t.neutral);
     }
   if(c<=-0.4)
     {
      state="normal inverse";
      return(g_t.blue);
     }
   if(c>=0.4)
     {
      state="moving together";
      return(g_t.orange);
     }
   if(c>=0.2)
     {
      state="weakening";
      return(g_t.orange);
     }
   state="decoupled";
   return(g_t.neutral);
  }

uint XagState(const double c,string &state)
  {
   if(!XOk(c))
     {
      state="n/a";
      return(g_t.neutral);
     }
   if(c>=0.4)
     {
      state="in sync";
      return(g_t.silver);
     }
   if(c<=-0.4)
     {
      state="inverse (unusual)";
      return(g_t.orange);
     }
   state="decoupled";
   return(g_t.neutral);
  }

void PanelRow(const double x,const double y,const double w,const string name,const string value,const string state,
              const uint rgb)
  {
   double k=g_front.K();
   g_front.Circle(x+4.0*k,y,3.0*k,XRgb(rgb,1.0));
   g_front.SetFont(XAU_FONT,7.5,FW_SEMIBOLD);
   g_front.Text(x+12.0*k,y,name,XRgb(g_t.text,0.95),TA_LEFT|TA_VCENTER);
   g_front.SetFont(XAU_FONT,8.0,FW_BOLD);
   g_front.Text(x+86.0*k,y,value,XRgb(rgb,1.0),TA_RIGHT|TA_VCENTER);
   double cw=0.0,ch=0.0;
   g_front.PillSize(state,7.0,cw,ch);
   g_front.Pill(x+w-cw*0.5,y,state,XRgb(rgb,0.18),XRgb(rgb,1.0),XA_CENTER,7.0);
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
   if(!XBegin(g_back,"XAU.Radar.back",g_map,true) || !XBegin(g_front,"XAU.Radar.front",g_map,false))
      return;
   double k=g_front.K();
   int from=g_map.From(),to=g_map.To();
   int last=g_total-1;

   XLevel(g_back,g_map,0.0,XRgb(g_t.muted,0.5),1.0);
   XLevel(g_back,g_map,0.5,XRgb(g_t.muted,0.35),1.0,4.0,4.0);
   XLevel(g_back,g_map,-0.5,XRgb(g_t.muted,0.35),1.0,4.0,4.0);

   if(ArraySize(g_zcols)!=g_total)
     {
      ArrayResize(g_zcols,g_total);
      ArrayResize(g_dcols,g_total);
     }
   string s;
   for(int i=from; i<=to; i++)
     {
      g_zcols[i]=(XOk(BufZ[i]) && BufZ[i]>=0.0 ? XRgb(g_t.gold,0.50) : XRgb(g_t.silver,0.40));
      g_dcols[i]=XRgb(DxyState(BufDxyCorr[i],s),1.0);
     }
   XColumns(g_back,g_map,BufZ,0.0,g_zcols,0.5);
   XStrokeSeries(g_front,g_map,BufXagCorr,XRgb(g_t.silver,0.85),1.2);
   XStrokeSeriesColored(g_front,g_map,BufDxyCorr,g_dcols,2.0,0.2);

   //--- live value tags
   double xt=g_map.X(last)+MathMax(2.0*g_map.spacing,8.0*k);
   XauTag tags[];
   int n=0;
   if(XOk(BufDxyCorr[last]))
      XAddTag(tags,n,g_map.Y(BufDxyCorr[last]),"DXY "+DoubleToString(BufDxyCorr[last],2),
              XRgb(DxyState(BufDxyCorr[last],s),1.0),XRgb(g_t.ink,1.0));
   if(XOk(BufXagCorr[last]))
      XAddTag(tags,n,g_map.Y(BufXagCorr[last]),"XAG "+DoubleToString(BufXagCorr[last],2),XRgb(g_t.silver,0.9),
              XRgb(g_t.ink,1.0));
   XDrawTags(g_front,tags,n,xt,7.0);

   //--- read-out card (below the sub-window caption)
   if(InpShowPanel)
     {
      double w=250.0*k,row=18.0*k;
      double h=34.0*k+3.0*row;
      double x=8.0*k,y=20.0*k;
      if(y+h>g_map.height-4.0*k)
         y=MathMax(2.0*k,g_map.height-h-4.0*k);
      g_front.Card(x,y,w,h,XRgb(g_t.panel,0.92),XRgb(g_t.border,1.0),XRgb(g_t.gold,0.9));
      g_front.SetFont(XAU_FONT,7.5,FW_BOLD);
      g_front.Text(x+10.0*k,y+9.0*k,"INTERMARKET",XRgb(g_t.gold,1.0),TA_LEFT|TA_TOP);
      g_front.SetFont(XAU_FONT,7.0,FW_NORMAL);
      g_front.Text(x+w-10.0*k,y+9.0*k,IntegerToString(InpCorrLen)+"-bar returns"+(g_synthetic ? " | synthetic DXY" : ""),
                   XRgb(g_t.muted,1.0),TA_RIGHT|TA_TOP);
      double ry=y+34.0*k;
      string st;
      uint c=DxyState(BufDxyCorr[last],st);
      PanelRow(x+10.0*k,ry,w-20.0*k,"DXY",XNum(BufDxyCorr[last],2),st,c);
      c=XagState(BufXagCorr[last],st);
      PanelRow(x+10.0*k,ry+row,w-20.0*k,"Silver",XNum(BufXagCorr[last],2),st,c);
      double ratio=BufRatio[last];
      double z=(XOk(BufZ[last]) ? BufZ[last]*3.0 : EMPTY_VALUE);
      string zs=(XOk(z) ? "z "+XSigned(z,2) : "z n/a");
      uint zc=(XOk(z) && z>=0.0 ? g_t.gold : g_t.silver);
      PanelRow(x+10.0*k,ry+2.0*row,w-20.0*k,"Au/Ag",XNum(ratio,1),zs,zc);
     }

   g_back.Flush();
   g_front.Flush();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
