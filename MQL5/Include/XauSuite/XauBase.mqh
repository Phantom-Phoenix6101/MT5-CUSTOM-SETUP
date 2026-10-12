//+------------------------------------------------------------------+
//|                                                     XauBase.mqh  |
//|                     XAU Suite for MetaTrader 5 - core helpers    |
//|  Numeric helpers, ARGB colour maths and incremental averages.     |
//+------------------------------------------------------------------+
#ifndef XAU_BASE_MQH
#define XAU_BASE_MQH

#define XAU_FONT "Segoe UI"

//+------------------------------------------------------------------+
//| Numbers                                                          |
//+------------------------------------------------------------------+
bool XOk(const double v)
  {
   return(v!=EMPTY_VALUE && MathIsValidNumber(v));
  }

double XClamp(const double v,const double lo,const double hi)
  {
   if(v<lo)
      return(lo);
   if(v>hi)
      return(hi);
   return(v);
  }

//--- empty-aware max/min (same semantics as the Indie fmax/fmin helpers)
double XMax(const double a,const double b)
  {
   if(!XOk(a))
      return(b);
   if(!XOk(b))
      return(a);
   return(a>b ? a : b);
  }

double XMin(const double a,const double b)
  {
   if(!XOk(a))
      return(b);
   if(!XOk(b))
      return(a);
   return(a<b ? a : b);
  }

//--- one step of an exponential moving average, seeded with the first value
double XEmaStep(const double prev,const double v,const int len)
  {
   if(!XOk(v))
      return(prev);
   if(!XOk(prev))
      return(v);
   double a=2.0/(len+1.0);
   return(prev+a*(v-prev));
  }

//--- one step of Wilder's moving average (RMA), seeded with the first value
double XRmaStep(const double prev,const double v,const int len)
  {
   if(!XOk(v))
      return(prev);
   if(!XOk(prev))
      return(v);
   return(prev+(v-prev)/(double)len);
  }

double XTrueRange(const double h,const double l,const double prev_close)
  {
   if(!XOk(prev_close))
      return(h-l);
   return(MathMax(h-l,MathMax(MathAbs(h-prev_close),MathAbs(l-prev_close))));
  }

string XNum(const double v,const int digits)
  {
   if(!XOk(v))
      return("-");
   return(DoubleToString(v,digits));
  }

string XSigned(const double v,const int digits)
  {
   if(!XOk(v))
      return("-");
   return((v>=0.0 ? "+" : "")+DoubleToString(v,digits));
  }

//+------------------------------------------------------------------+
//| Colours                                                          |
//| Canvas colours are uint ARGB (0xAARRGGBB), not premultiplied.     |
//| Palette entries are plain 0xRRGGBB and get an alpha when used.    |
//+------------------------------------------------------------------+
uint XArgb(const int r,const int g,const int b,const double a)
  {
   int alpha=(int)MathRound(XClamp(a,0.0,1.0)*255.0);
   return(((uint)alpha<<24)|((uint)(r&0xFF)<<16)|((uint)(g&0xFF)<<8)|(uint)(b&0xFF));
  }

uint XRgb(const uint rgb,const double a)
  {
   int alpha=(int)MathRound(XClamp(a,0.0,1.0)*255.0);
   return(((uint)alpha<<24)|(rgb&0x00FFFFFF));
  }

//--- scale the alpha channel of an ARGB colour
uint XFade(const uint argb,const double k)
  {
   double a=(double)(argb>>24)*XClamp(k,0.0,1.0);
   return(((uint)MathRound(a)<<24)|(argb&0x00FFFFFF));
  }

//--- linear blend of two ARGB colours, all four channels
uint XLerp(const uint c1,const uint c2,const double t)
  {
   double k=XClamp(t,0.0,1.0);
   int a=(int)MathRound(((c1>>24)&0xFF)+(((double)((c2>>24)&0xFF))-((c1>>24)&0xFF))*k);
   int r=(int)MathRound(((c1>>16)&0xFF)+(((double)((c2>>16)&0xFF))-((c1>>16)&0xFF))*k);
   int g=(int)MathRound(((c1>>8)&0xFF)+(((double)((c2>>8)&0xFF))-((c1>>8)&0xFF))*k);
   int b=(int)MathRound((c1&0xFF)+(((double)(c2&0xFF))-(c1&0xFF))*k);
   return(((uint)a<<24)|((uint)r<<16)|((uint)g<<8)|(uint)b);
  }

//--- 0xRRGGBB -> MQL5 color (0x00BBGGRR) for native plots and chart properties
color XClr(const uint rgb)
  {
   uint r=(rgb>>16)&0xFF;
   uint g=(rgb>>8)&0xFF;
   uint b=rgb&0xFF;
   return((color)((b<<16)|(g<<8)|r));
  }

//--- "XAUUSD.m" -> "XAU/USD" for display
string XPrettySymbol(const string sym)
  {
   if(StringLen(sym)>=6)
     {
      string base=StringSubstr(sym,0,3);
      string quote=StringSubstr(sym,3,3);
      string up=base+quote;
      StringToUpper(up);
      if(StringSubstr(up,0,3)=="XAU" || StringSubstr(up,0,3)=="XAG")
         return(StringSubstr(up,0,3)+"/"+StringSubstr(up,3,3));
     }
   return(sym);
  }

string XTfName(const ENUM_TIMEFRAMES tf_in)
  {
   ENUM_TIMEFRAMES tf=(tf_in==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : tf_in);
   int sec=PeriodSeconds(tf);
   if(sec>=2419200)
      return(IntegerToString(sec/2592000>0 ? sec/2592000 : 1)+"M");
   if(sec>=604800)
      return(IntegerToString(sec/604800)+"W");
   if(sec>=86400)
      return(IntegerToString(sec/86400)+"D");
   if(sec>=3600)
      return(IntegerToString(sec/3600)+"H");
   return(IntegerToString(sec/60)+"m");
  }

#endif
//+------------------------------------------------------------------+
