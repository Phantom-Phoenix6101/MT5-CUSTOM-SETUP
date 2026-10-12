//+------------------------------------------------------------------+
//|                                            XAU_OneClickSetup.mq5 |
//|                                     XAU Suite for MetaTrader 5   |
//|                                                                  |
//| Builds the complete gold workspace in one click:                 |
//|   D1  Bias       - Trend Ribbon, Smart Money Concepts            |
//|   H4  Structure  - Smart Money Concepts, Volume Profile,         |
//|                    Sessions & Key Levels                         |
//|   H1  Plan       - Sessions & Key Levels, VWAP Bands,            |
//|                    Intermarket Radar, Command Center             |
//|   M15 Execution  - Trend Ribbon, Sessions & Key Levels, VWAP,    |
//|                    ADR & Volatility, Momentum Matrix,            |
//|                    Command Center                                |
//|   H1  DXY / Silver context charts with the Trend Ribbon          |
//| Every chart gets the chosen theme. Indicators use their default  |
//| inputs and follow the suite theme set here.                      |
//| Compile Indicators\XauSuite before running this script.          |
//+------------------------------------------------------------------+
#property copyright   "XAU Suite"
#property version     "1.00"
#property description "One-click XAU Suite setup: opens and styles the D1 / H4 / H1 / M15 gold workspace"
#property description "and attaches the right indicators to every chart."
#property script_show_inputs

#include <XauSuite/XauTheme.mqh>

enum ENUM_XAU_LAYOUT
  {
   XAU_LAYOUT_WORKSPACE=0, // Full workspace (opens D1 / H4 / H1 / M15 charts)
   XAU_LAYOUT_EXECUTION=1, // Execution set on this chart only
   XAU_LAYOUT_PLAN=2,      // Plan set on this chart only
   XAU_LAYOUT_STRUCTURE=3  // Structure set on this chart only
  };

input ENUM_XAU_LAYOUT InpLayout        = XAU_LAYOUT_WORKSPACE; // What to set up
input ENUM_XAU_THEME  InpTheme         = XAU_THEME_MIDNIGHT;   // Colour theme
input string          InpGoldSymbol    = "";    // Gold symbol (empty = auto-detect)
input bool            InpContextCharts = true;  // Also open DXY and silver charts
input bool            InpCloseOthers   = false; // Close all other charts first
input bool            InpShowGrid      = false; // Show chart grid

#define XAU_DIR "XauSuite\\"

XauTheme g_t;
int      g_added=0;
int      g_failed=0;
string   g_pre="";
string   g_suf="";

//+------------------------------------------------------------------+
//| Symbols                                                          |
//+------------------------------------------------------------------+
bool Usable(const string name)
  {
   if(name=="")
      return(false);
   bool custom=false;
   if(!SymbolExist(name,custom))
      return(false);
   return(SymbolSelect(name,true));
  }

//--- shortest symbol containing `key`, Market Watch first, then the whole server list
string FindContaining(const string key)
  {
   for(int pass=0; pass<2; pass++)
     {
      bool selected=(pass==0);
      string best="";
      int n=SymbolsTotal(selected);
      for(int i=0; i<n; i++)
        {
         string s=SymbolName(i,selected);
         string u=s;
         StringToUpper(u);
         if(StringFind(u,key)>=0 && (best=="" || StringLen(s)<StringLen(best)))
            best=s;
        }
      if(best!="" && Usable(best))
         return(best);
     }
   return("");
  }

string FindGold()
  {
   if(InpGoldSymbol!="")
      return(Usable(InpGoldSymbol) ? InpGoldSymbol : "");
   string u=_Symbol;
   StringToUpper(u);
   if(StringFind(u,"XAUUSD")>=0 || StringFind(u,"GOLD")>=0)
      return(_Symbol);
   string s=FindContaining("XAUUSD");
   if(s=="")
      s=FindContaining("GOLD");
   return(s);
  }

//--- remember the broker prefix / suffix around "XAUUSD" (e.g. "XAUUSD.m" -> ".m")
void DetectAffixes(const string gold)
  {
   string u=gold;
   StringToUpper(u);
   int pos=StringFind(u,"XAUUSD");
   if(pos<0)
      return;
   g_pre=StringSubstr(gold,0,pos);
   if(StringLen(gold)>pos+6)
      g_suf=StringSubstr(gold,pos+6);
  }

string Resolve(const string &names[])
  {
   for(int i=0; i<ArraySize(names); i++)
     {
      if(Usable(g_pre+names[i]+g_suf))
         return(g_pre+names[i]+g_suf);
      if(Usable(names[i]+g_suf))
         return(names[i]+g_suf);
      if(Usable(names[i]))
         return(names[i]);
     }
   return("");
  }

//+------------------------------------------------------------------+
//| Charts and indicators                                            |
//+------------------------------------------------------------------+
bool HasIndicator(const long chart,const string short_name)
  {
   int windows=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL);
   for(int w=0; w<windows; w++)
     {
      int n=ChartIndicatorsTotal(chart,w);
      for(int i=0; i<n; i++)
         if(ChartIndicatorName(chart,w,i)==short_name)
            return(true);
     }
   return(false);
  }

//--- attach Indicators\XauSuite\<file> with its default inputs
void Add(const long chart,const string file,const string short_name,const bool own_window)
  {
   if(chart<=0)
      return;
   if(HasIndicator(chart,short_name))
      return;
   string sym=ChartSymbol(chart);
   ENUM_TIMEFRAMES tf=ChartPeriod(chart);
   int h=iCustom(sym,tf,XAU_DIR+file);
   if(h==INVALID_HANDLE)
     {
      PrintFormat("XAU Setup: cannot load %s (error %d) - compile Indicators\\XauSuite in MetaEditor first",
                  file,GetLastError());
      g_failed++;
      return;
     }
   int sub=(own_window ? (int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL) : 0);
   if(!ChartIndicatorAdd(chart,sub,h))
     {
      PrintFormat("XAU Setup: could not add %s to %s %s (error %d)",file,sym,EnumToString(tf),GetLastError());
      g_failed++;
      return;
     }
   g_added++;
  }

long Open(const string sym,const ENUM_TIMEFRAMES tf)
  {
   long id=ChartOpen(sym,tf);
   if(id<=0)
     {
      PrintFormat("XAU Setup: could not open %s %s (error %d)",sym,EnumToString(tf),GetLastError());
      return(0);
     }
   XauApplyChartTheme(id,g_t,InpShowGrid,false,true,true);
   return(id);
  }

void Bias(const long c)
  {
   Add(c,"XAU_TrendRibbon","XAU Trend Ribbon",false);
   Add(c,"XAU_SmartMoneyConcepts","XAU Smart Money Concepts",false);
  }

void Structure(const long c)
  {
   Add(c,"XAU_SmartMoneyConcepts","XAU Smart Money Concepts",false);
   Add(c,"XAU_VolumeProfile","XAU Volume Profile",false);
   Add(c,"XAU_SessionsKeyLevels","XAU Sessions & Key Levels",false);
  }

void Plan(const long c)
  {
   Add(c,"XAU_SessionsKeyLevels","XAU Sessions & Key Levels",false);
   Add(c,"XAU_VWAPBands","XAU VWAP Bands",false);
   Add(c,"XAU_CommandCenter","XAU Command Center",false);
   Add(c,"XAU_IntermarketRadar","XAU Intermarket Radar",true);
  }

void Execution(const long c)
  {
   Add(c,"XAU_TrendRibbon","XAU Trend Ribbon",false);
   Add(c,"XAU_SessionsKeyLevels","XAU Sessions & Key Levels",false);
   Add(c,"XAU_VWAPBands","XAU VWAP Bands",false);
   Add(c,"XAU_ADRVolatility","XAU ADR & Volatility",false);
   Add(c,"XAU_CommandCenter","XAU Command Center",false);
   Add(c,"XAU_MomentumMatrix","XAU Momentum Matrix",true);
  }

void CloseOtherCharts()
  {
   long me=ChartID();
   long ids[];
   int n=0;
   long id=ChartFirst();
   while(id>=0)
     {
      if(id!=me)
        {
         ArrayResize(ids,n+1);
         ids[n++]=id;
        }
      id=ChartNext(id);
     }
   for(int i=0; i<n; i++)
      ChartClose(ids[i]);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   //--- theme first, so every indicator loads with it
   ENUM_XAU_THEME theme=XauResolveTheme(InpTheme);
   GlobalVariableSet(XAU_THEME_GV,(double)theme);
   XauLoadTheme(theme,g_t);

   if(InpLayout!=XAU_LAYOUT_WORKSPACE)
     {
      long me=ChartID();
      XauApplyChartTheme(me,g_t,InpShowGrid,false,true,true);
      if(InpLayout==XAU_LAYOUT_EXECUTION)
         Execution(me);
      else
         if(InpLayout==XAU_LAYOUT_PLAN)
            Plan(me);
         else
            Structure(me);
      ChartRedraw(me);
      PrintFormat("XAU Setup: %d indicators added to this chart, %d failed",g_added,g_failed);
      return;
     }

   string gold=FindGold();
   if(gold=="")
     {
      MessageBox("No gold symbol found on this account.\nSet 'Gold symbol' in the script inputs "+
                 "to the exact name shown in Market Watch (e.g. XAUUSD.m).","XAU Suite setup",MB_OK|MB_ICONWARNING);
      return;
     }
   DetectAffixes(gold);
   if(InpCloseOthers)
      CloseOtherCharts();

   //--- context first, execution last so it ends up as the active chart
   if(InpContextCharts)
     {
      string dxy_names[]= {"USDX","DXY","USDIDX","DX","USDINDEX","DOLLARINDEX","USIDX","DXY.cash","USDX.F","DX.f"};
      string xag_names[]= {"XAGUSD","SILVER"};
      string dxy=Resolve(dxy_names);
      string xag=Resolve(xag_names);
      if(dxy!="")
         Add(Open(dxy,PERIOD_H1),"XAU_TrendRibbon","XAU Trend Ribbon",false);
      else
         Print("XAU Setup: no dollar index CFD on this account - Intermarket Radar uses a synthetic DXY instead");
      if(xag!="")
         Add(Open(xag,PERIOD_H1),"XAU_TrendRibbon","XAU Trend Ribbon",false);
     }
   Bias(Open(gold,PERIOD_D1));
   Structure(Open(gold,PERIOD_H4));
   Plan(Open(gold,PERIOD_H1));
   Execution(Open(gold,PERIOD_M15));

   string msg=StringFormat("XAU Suite workspace ready for %s.\n\n%d indicators added",gold,g_added);
   if(g_failed>0)
      msg+=StringFormat(", %d failed - check the Experts tab (compile Indicators\\XauSuite first)",g_failed);
   msg+=".\n\nTip: Window > Tile Windows (Alt+R) to see every chart at once, then\n"+
        "File > Profiles > Save As to keep this workspace.";
   MessageBox(msg,"XAU Suite setup",MB_OK|(g_failed>0 ? MB_ICONWARNING : MB_ICONINFORMATION));
  }
//+------------------------------------------------------------------+
