//+------------------------------------------------------------------+
//|                                                    XauChart.mqh  |
//|      XAU Suite for MetaTrader 5 - chart mapping and series drawing|
//|                                                                  |
//| Bar indexes are non-series (0 = oldest bar), as in OnCalculate.   |
//| Fractional and future indexes are allowed, so drawings can extend |
//| to the right of the last bar.                                     |
//+------------------------------------------------------------------+
#ifndef XAU_CHART_MQH
#define XAU_CHART_MQH

#include "XauCanvas.mqh"

//+------------------------------------------------------------------+
//| Bar/price <-> pixel mapping for one chart window                  |
//+------------------------------------------------------------------+
class CXauMap
  {
public:
   int               sub;
   int               width;
   int               height;
   int               total;
   int               first;     // series index of the leftmost visible bar
   int               visible;   // bars that fit in the window
   int               idx_first; // non-series index of the leftmost visible bar
   double            spacing;   // pixels per bar
   double            x0;        // x of the leftmost visible bar centre
   double            pmax;
   double            pmin;

                     CXauMap(void) : sub(0),width(0),height(0),total(0),first(0),visible(0),idx_first(0),
                     spacing(1.0),x0(0.0),pmax(1.0),pmin(0.0) {}

   bool              Update(const int subwin,const int bars_total)
     {
      sub=subwin;
      total=bars_total;
      width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
      height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,sub);
      first=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR);
      visible=(int)ChartGetInteger(0,CHART_WIDTH_IN_BARS);
      pmax=ChartGetDouble(0,CHART_PRICE_MAX,sub);
      pmin=ChartGetDouble(0,CHART_PRICE_MIN,sub);
      if(width<=0 || height<=0 || total<=0 || !(pmax>pmin))
         return(false);
      int scale=(int)ChartGetInteger(0,CHART_SCALE);
      spacing=(double)(1<<(int)XClamp(scale,0,5));
      if(first>total-1)
         first=total-1;
      if(first<0)
         first=0;
      idx_first=total-1-first;
      x0=spacing*0.5;
      datetime t0=iTime(_Symbol,_Period,first);
      int xa=0,ya=0;
      if(t0>0 && ChartTimePriceToXY(0,sub,t0,pmax,xa,ya))
        {
         x0=(double)xa;
         // measure the real bar pitch from two bars further right
         int k=MathMin(first,16);
         if(k>0)
           {
            datetime t1=iTime(_Symbol,_Period,first-k);
            int xb=0,yb=0;
            if(t1>0 && ChartTimePriceToXY(0,sub,t1,pmax,xb,yb) && xb>xa)
               spacing=(double)(xb-xa)/(double)k;
           }
        }
      return(true);
     }

   double            X(const double idx) const   { return(x0+(idx-idx_first)*spacing); }
   double            Y(const double price) const { return((pmax-price)/(pmax-pmin)*height); }
   double            Price(const double y) const { return(pmax-y/height*(pmax-pmin)); }
   int               From(void) const            { return(MathMax(0,idx_first-1)); }
   int               To(void) const              { return(MathMin(total-1,idx_first+visible+1)); }
   int               Last(void) const            { return(total-1); }
  };

//+------------------------------------------------------------------+
//| Redraw throttle: chart events redraw at once, ticks at most every |
//| min_ms; skipped ticks are picked up by the timer.                 |
//+------------------------------------------------------------------+
class CXauGate
  {
private:
   uint              m_last;
   uint              m_ms;
   bool              m_dirty;
public:
                     CXauGate(void) : m_last(0),m_ms(120),m_dirty(true) {}
   void              Init(const int min_ms)
     {
      m_ms=(uint)MathMax(min_ms,30);
      m_dirty=true;
      EventSetMillisecondTimer((int)m_ms);
     }
   void              Stop(void) { EventKillTimer(); }
   bool              Request(const bool force)
     {
      uint now=GetTickCount();
      if(force || now-m_last>=m_ms)
        {
         m_last=now;
         m_dirty=false;
         return(true);
        }
      m_dirty=true;
      return(false);
     }
   bool              Pending(void)
     {
      if(!m_dirty)
         return(false);
      m_dirty=false;
      m_last=GetTickCount();
      return(true);
     }
   void              Touch(void) { m_dirty=true; }
  };

//+------------------------------------------------------------------+
//| Attach a full-window canvas layer and clear it for a new frame    |
//+------------------------------------------------------------------+
bool XBegin(CXauCanvas &cv,const string name,const CXauMap &m,const bool back)
  {
   string obj=name+"."+IntegerToString(m.sub);
   if(!cv.Attach(obj,m.sub,back))
      return(false);
   if(!cv.Place(0,0,m.width,m.height))
      return(false);
   cv.Clear();
   return(true);
  }

//+------------------------------------------------------------------+
//| Series drawing over the visible range                             |
//+------------------------------------------------------------------+
void XPush(double &xs[],double &ys[],int &n,const double x,const double y)
  {
   if(n>=ArraySize(xs))
     {
      ArrayResize(xs,n+256);
      ArrayResize(ys,n+256);
     }
   xs[n]=x;
   ys[n]=y;
   n++;
  }

//--- stroke a buffer, breaking at empty values; glow > 0 adds a soft halo of that alpha
void XStrokeSeries(CXauCanvas &cv,const CXauMap &m,const double &buf[],const uint c,const double width,
                   const double dash=0.0,const double gap=0.0,const double glow=0.0)
  {
   double xs[],ys[];
   int n=0;
   int from=m.From(),to=m.To();
   for(int i=from; i<=to+1; i++)
     {
      bool ok=(i<=to && XOk(buf[i]));
      if(ok)
        {
         XPush(xs,ys,n,m.X(i),m.Y(buf[i]));
         continue;
        }
      if(n>0)
        {
         if(glow>0.0)
            cv.Polyline(xs,ys,n,XFade(c,glow),width+6.0,0.0,0.0,6.0);
         cv.Polyline(xs,ys,n,c,width,dash,gap);
        }
      n=0;
     }
  }

//--- stroke a buffer whose colour changes per bar (cols[i] = ARGB, 0 = gap).
//--- Each segment takes the colour of the bar it ends on, like TradingView.
void XStrokeSeriesColored(CXauCanvas &cv,const CXauMap &m,const double &buf[],const uint &cols[],
                          const double width,const double glow=0.0)
  {
   double xs[],ys[];
   int n=0;
   uint cur=0;
   int from=m.From(),to=m.To();
   for(int i=from; i<=to+1; i++)
     {
      bool ok=(i<=to && XOk(buf[i]) && cols[i]!=0);
      if(ok && (n==0 || cols[i]==cur))
        {
         XPush(xs,ys,n,m.X(i),m.Y(buf[i]));
         cur=cols[i];
         continue;
        }
      if(n>1)
        {
         if(glow>0.0)
            cv.Polyline(xs,ys,n,XFade(cur,glow),width+6.0,0.0,0.0,6.0);
         cv.Polyline(xs,ys,n,cur,width);
        }
      if(ok)
        {
         // colour change: the new run starts at the previous point
         double px=xs[n-1],py=ys[n-1];
         n=0;
         XPush(xs,ys,n,px,py);
         XPush(xs,ys,n,m.X(i),m.Y(buf[i]));
         cur=cols[i];
        }
      else
         n=0;
     }
  }

//--- stroke a buffer coloured by its vertical position through a lookup table
//--- (lut[0] at y_top ... lut[n-1] at y_bottom), e.g. an oscillator gradient
void XStrokeSeriesLut(CXauCanvas &cv,const CXauMap &m,const double &buf[],const uint &lut[],const double y_top,
                      const double y_bottom,const double width,const double glow=0.0)
  {
   double xs[],ys[];
   int n=0;
   int from=m.From(),to=m.To();
   for(int i=from; i<=to+1; i++)
     {
      bool ok=(i<=to && XOk(buf[i]));
      if(ok)
        {
         XPush(xs,ys,n,m.X(i),m.Y(buf[i]));
         continue;
        }
      if(n>0)
        {
         if(glow>0.0)
            cv.PolylineLut(xs,ys,n,lut,y_top,y_bottom,width+6.0,glow,6.0);
         cv.PolylineLut(xs,ys,n,lut,y_top,y_bottom,width);
        }
      n=0;
     }
  }

//--- fill between two buffers (fade = alpha multiplier at the b side)
void XFillSeries(CXauCanvas &cv,const CXauMap &m,const double &a[],const double &b[],const uint c,
                 const double fade=1.0)
  {
   int from=m.From(),to=m.To();
   for(int i=from+1; i<=to; i++)
     {
      if(!XOk(a[i-1]) || !XOk(b[i-1]) || !XOk(a[i]) || !XOk(b[i]))
         continue;
      cv.Band(m.X(i-1),m.Y(a[i-1]),m.Y(b[i-1]),m.X(i),m.Y(a[i]),m.Y(b[i]),c,fade);
     }
  }

//--- fill between a buffer and a level, only where the buffer is beyond it
void XFillBeyond(CXauCanvas &cv,const CXauMap &m,const double &buf[],const double level,const bool above,
                 const uint c,const double fade=1.0)
  {
   int from=m.From(),to=m.To();
   double yl=m.Y(level);
   for(int i=from+1; i<=to; i++)
     {
      double va=buf[i-1],vb=buf[i];
      if(!XOk(va) || !XOk(vb))
         continue;
      double da=(above ? va-level : level-va);
      double db=(above ? vb-level : level-vb);
      if(da<=0.0 && db<=0.0)
         continue;
      double xa=m.X(i-1),xb=m.X(i);
      if(da>0.0 && db>0.0)
        {
         cv.Band(xa,m.Y(va),yl,xb,m.Y(vb),yl,c,fade);
         continue;
        }
      double t=da/(da-db);
      double xm=xa+t*(xb-xa);
      if(da>0.0)
         cv.Band(xa,m.Y(va),yl,xm,yl,yl,c,fade);
      else
         cv.Band(xm,yl,yl,xb,m.Y(vb),yl,c,fade);
     }
  }

//--- histogram columns from base to value (cols[i] = ARGB, 0 = skip)
void XColumns(CXauCanvas &cv,const CXauMap &m,const double &buf[],const double base,const uint &cols[],
              const double rel_width)
  {
   double w=MathMax(m.spacing*rel_width,1.0);
   double yb=m.Y(base);
   double rad=(w>=4.0 ? MathMin(2.0*cv.K(),w/3.0) : 0.0);
   int from=m.From(),to=m.To();
   for(int i=from; i<=to; i++)
     {
      if(!XOk(buf[i]) || cols[i]==0)
         continue;
      double x=m.X(i);
      double y=m.Y(buf[i]);
      if(rad>0.0)
         cv.RoundRect(x-w*0.5,MathMin(y,yb),x+w*0.5,MathMax(y,yb),rad,cols[i]);
      else
         cv.FillRect(x-w*0.5,MathMin(y,yb),x+w*0.5,MathMax(y,yb),cols[i]);
     }
  }

//--- full-height background tint per bar, merged into runs so no seams appear
void XBackground(CXauCanvas &cv,const CXauMap &m,const uint &cols[])
  {
   int from=m.From(),to=m.To();
   int run=-1;
   uint cur=0;
   for(int i=from; i<=to+1; i++)
     {
      uint c=(i<=to ? cols[i] : 0);
      if(run>=0 && c!=cur)
        {
         cv.FillRect(m.X(run)-m.spacing*0.5,0,m.X(i-1)+m.spacing*0.5,m.height,cur);
         run=-1;
        }
      if(run<0 && c!=0)
        {
         run=i;
         cur=c;
        }
     }
  }

//--- horizontal guide line across the window
void XLevel(CXauCanvas &cv,const CXauMap &m,const double price,const uint c,const double width,
            const double dash=0.0,const double gap=0.0)
  {
   double y=m.Y(price);
   cv.Line(0,y,m.width,y,c,width,dash,gap);
  }

//+------------------------------------------------------------------+
//| Right-edge price tags, stacked so they never overlap              |
//+------------------------------------------------------------------+
struct XauTag
  {
   double            y;
   string            text;
   uint              bg;
   uint              fg;
  };

void XAddTag(XauTag &tags[],int &n,const double y,const string text,const uint bg,const uint fg)
  {
   if(n>=ArraySize(tags))
      ArrayResize(tags,n+8);
   tags[n].y=y;
   tags[n].text=text;
   tags[n].bg=bg;
   tags[n].fg=fg;
   n++;
  }

//--- draws pills right of x; tags are sorted by y and pushed apart by their height
void XDrawTags(CXauCanvas &cv,XauTag &tags[],const int n,const double x,const double points=8.0)
  {
   if(n<=0)
      return;
   for(int i=1; i<n; i++)
     {
      XauTag v=tags[i];
      int j=i-1;
      while(j>=0 && tags[j].y>v.y)
        {
         tags[j+1]=tags[j];
         j--;
        }
      tags[j+1]=v;
     }
   double w=0.0,h=0.0;
   cv.PillSize("0",points,w,h);
   double gap=h+2.0*cv.K();
   // push down from the top, then pull back up if the stack ran off the bottom
   for(int i=1; i<n; i++)
      if(tags[i].y-tags[i-1].y<gap)
         tags[i].y=tags[i-1].y+gap;
   double limit=cv.Height()-h*0.5-2.0;
   if(tags[n-1].y>limit)
     {
      tags[n-1].y=limit;
      for(int i=n-2; i>=0; i--)
         if(tags[i+1].y-tags[i].y<gap)
            tags[i].y=tags[i+1].y-gap;
     }
   for(int i=0; i<n; i++)
      cv.Pill(x,tags[i].y,tags[i].text,tags[i].bg,tags[i].fg,XA_RIGHT,points);
  }

#endif
//+------------------------------------------------------------------+
