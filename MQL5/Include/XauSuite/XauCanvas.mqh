//+------------------------------------------------------------------+
//|                                                   XauCanvas.mqh  |
//|          XAU Suite for MetaTrader 5 - anti-aliased ARGB canvas    |
//|                                                                  |
//| MT5 draws indicator plots with aliased 1-pixel GDI lines. This    |
//| canvas renders into a 32-bit ARGB bitmap shown by an               |
//| OBJ_BITMAP_LABEL instead, so every primitive gets sub-pixel        |
//| coverage:                                                          |
//|   - strokes are distance-field capsules (round caps and joins),    |
//|     accumulated in a coverage mask so translucent polylines never  |
//|     double-blend at their joints; optional dash pattern and soft   |
//|     feather for glows                                              |
//|   - fills between two curves are rasterised per pixel column with  |
//|     fractional top/bottom coverage and an optional alpha gradient  |
//|   - rounded rectangles, circles and triangles use signed distance  |
//|     functions                                                     |
//|   - text uses the terminal's anti-aliased font renderer            |
//|                                                                  |
//| Coordinates are in physical pixels. Stroke widths, dash lengths   |
//| and widget paddings are in logical pixels and get scaled by the   |
//| screen DPI.                                                       |
//+------------------------------------------------------------------+
#ifndef XAU_CANVAS_MQH
#define XAU_CANVAS_MQH

#include "XauBase.mqh"

enum ENUM_XAU_ANCHOR
  {
   XA_CENTER=0, // box centred on the point
   XA_ABOVE=1,  // box above the point, pointer down
   XA_BELOW=2,  // box below the point, pointer up
   XA_RIGHT=3,  // box right of the point, pointer left
   XA_LEFT=4    // box left of the point, pointer right
  };

class CXauCanvas
  {
private:
   string            m_obj;
   string            m_res;
   int               m_sub;
   int               m_x;
   int               m_y;
   int               m_w;
   int               m_h;
   bool              m_ready;
   double            m_k;
   uint              m_px[];
   uchar             m_mask[];
   int               m_rx0[];    // per-row covered span of the mask
   int               m_rx1[];
   int               m_mx0;
   int               m_my0;
   int               m_mx1;
   int               m_my1;
   string            m_face;
   int               m_size;
   uint              m_weight;
   //--- current stroke segment
   double            m_sx;
   double            m_sy;
   double            m_sdx;
   double            m_sdy;
   double            m_sinv;
   double            m_slen;
   double            m_shw;
   double            m_sf;
   double            m_sdash;
   double            m_speriod;
   double            m_sarc;
   bool              m_sdashed;

   void              BlendA(const int idx,const uint c,uint sa);
   void              Cover(const int idx,const uint c,const double cov);
   void              MaskReset(void);
   void              MaskPx(const int px,const int py);
   void              MaskSeg(const double x1,const double y1,const double x2,const double y2,double &arc);
   void              MaskFlush(const uint c);
   void              MaskFlushLut(const uint &lut[],const double y0,const double y1,const double alpha);
   void              MaskStroke(const double &xs[],const double &ys[],const int n,const double width,
                                const double dash,const double gap,const double feather);

public:
                     CXauCanvas(void);
                    ~CXauCanvas(void) { Destroy(); }

   bool              Attach(const string name,const int sub,const bool back);
   bool              Place(const int x,const int y,const int w,const int h);
   void              Destroy(void);
   void              Clear(void)          { if(m_w>0) ArrayInitialize(m_px,0); }
   bool              Flush(void);
   bool              Ready(void) const    { return(m_ready && m_w>0 && m_h>0); }
   int               Width(void) const    { return(m_w); }
   int               Height(void) const   { return(m_h); }
   double            K(void) const        { return(m_k); }

   //--- strokes (width / dash in logical px)
   void              Polyline(const double &xs[],const double &ys[],const int n,const uint c,const double width,
                              const double dash=0.0,const double gap=0.0,const double feather=1.0);
   void              PolylineLut(const double &xs[],const double &ys[],const int n,const uint &lut[],
                                 const double y_top,const double y_bottom,const double width,
                                 const double alpha=1.0,const double feather=1.0);
   void              Line(const double x1,const double y1,const double x2,const double y2,const uint c,
                          const double width,const double dash=0.0,const double gap=0.0);
   //--- fills (physical px)
   void              Band(const double xa,const double ya1,const double ya2,const double xb,const double yb1,
                          const double yb2,const uint c,const double fade=1.0);
   void              FillRect(const double x1,const double y1,const double x2,const double y2,const uint c);
   void              RoundRect(const double x1,const double y1,const double x2,const double y2,const double radius,
                               const uint fill,const uint border=0,const double border_width=1.0);
   void              Circle(const double cx,const double cy,const double r,const uint fill,const uint border=0,
                            const double border_width=1.0);
   void              Triangle(double x1,double y1,double x2,double y2,double x3,double y3,const uint c);
   //--- text
   void              SetFont(const string face,const double points,const uint weight=FW_NORMAL);
   void              Text(const double x,const double y,const string text,const uint c,
                          const uint align=TA_LEFT|TA_TOP);
   void              TextSize(const string text,int &w,int &h);
   //--- widgets
   void              PillSize(const string text,const double points,double &w,double &h);
   void              Pill(const double x,const double y,const string text,const uint bg,const uint fg,
                          const ENUM_XAU_ANCHOR anchor,const double points=8.0,const uint border=0,
                          const bool pointer=true);
   void              Card(const double x,const double y,const double w,const double h,const uint bg,
                          const uint border,const uint accent=0);
   void              Bar(const double x,const double y,const double w,const double h,const double frac,
                         const uint track,const uint fill);
  };

//+------------------------------------------------------------------+
CXauCanvas::CXauCanvas(void) : m_sub(0),m_x(-1),m_y(-1),m_w(0),m_h(0),m_ready(false),
   m_mx0(0),m_my0(0),m_mx1(-1),m_my1(-1),m_size(-90),m_weight(FW_NORMAL)
  {
   m_face=XAU_FONT;
   double dpi=(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   m_k=XClamp(dpi/96.0,1.0,3.0);
  }

//+------------------------------------------------------------------+
//| Object / resource lifetime                                       |
//+------------------------------------------------------------------+
bool CXauCanvas::Attach(const string name,const int sub,const bool back)
  {
   if(m_ready && m_obj==name && m_sub==sub && ObjectFind(0,m_obj)>=0)
      return(true);
   Destroy();
   m_obj=name;
   m_res="::"+name;
   m_sub=sub;
   if(ObjectFind(0,m_obj)>=0)
      ObjectDelete(0,m_obj);
   if(!ObjectCreate(0,m_obj,OBJ_BITMAP_LABEL,sub,0,0))
      return(false);
   ObjectSetInteger(0,m_obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,m_obj,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,m_obj,OBJPROP_BACK,back);
   ObjectSetInteger(0,m_obj,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,m_obj,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,m_obj,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,m_obj,OBJPROP_ZORDER,0);
   ObjectSetString(0,m_obj,OBJPROP_TOOLTIP,"\n");
   m_x=-1;
   m_y=-1;
   m_w=0;
   m_h=0;
   m_ready=true;
   return(true);
  }

bool CXauCanvas::Place(const int x,const int y,const int w,const int h)
  {
   if(!m_ready || w<=0 || h<=0)
      return(false);
   if(x!=m_x || y!=m_y)
     {
      ObjectSetInteger(0,m_obj,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,m_obj,OBJPROP_YDISTANCE,y);
      m_x=x;
      m_y=y;
     }
   if(w!=m_w || h!=m_h)
     {
      if(ArrayResize(m_px,w*h)<0 || ArrayResize(m_mask,w*h)<0 || ArrayResize(m_rx0,h)<0 || ArrayResize(m_rx1,h)<0)
        {
         m_w=0;
         m_h=0;
         return(false);
        }
      m_w=w;
      m_h=h;
      ArrayInitialize(m_px,0);
      ArrayInitialize(m_mask,0);
      ArrayInitialize(m_rx0,w);
      ArrayInitialize(m_rx1,-1);
      ObjectSetInteger(0,m_obj,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,m_obj,OBJPROP_YSIZE,h);
      if(!ResourceCreate(m_res,m_px,m_w,m_h,0,0,m_w,COLOR_FORMAT_ARGB_NORMALIZE))
         return(false);
      ObjectSetString(0,m_obj,OBJPROP_BMPFILE,m_res);
     }
   return(true);
  }

void CXauCanvas::Destroy(void)
  {
   if(m_ready)
     {
      ObjectDelete(0,m_obj);
      ResourceFree(m_res);
     }
   m_ready=false;
   m_w=0;
   m_h=0;
   ArrayFree(m_px);
   ArrayFree(m_mask);
   ArrayFree(m_rx0);
   ArrayFree(m_rx1);
  }

bool CXauCanvas::Flush(void)
  {
   if(!Ready())
      return(false);
   return(ResourceCreate(m_res,m_px,m_w,m_h,0,0,m_w,COLOR_FORMAT_ARGB_NORMALIZE));
  }

//+------------------------------------------------------------------+
//| Source-over blending in non-premultiplied ARGB                   |
//+------------------------------------------------------------------+
void CXauCanvas::BlendA(const int idx,const uint c,uint sa)
  {
   if(sa==0)
      return;
   if(sa>255)
      sa=255;
   uint d=m_px[idx];
   uint da=d>>24;
   if(sa==255 || da==0)
     {
      m_px[idx]=(sa<<24)|(c&0x00FFFFFF);
      return;
     }
   uint dw=(da*(255-sa)+127)/255;
   uint oa=sa+dw;
   uint half=oa/2;
   uint r=(((c>>16)&0xFF)*sa+((d>>16)&0xFF)*dw+half)/oa;
   uint g=(((c>>8)&0xFF)*sa+((d>>8)&0xFF)*dw+half)/oa;
   uint b=((c&0xFF)*sa+(d&0xFF)*dw+half)/oa;
   m_px[idx]=(oa<<24)|(r<<16)|(g<<8)|b;
  }

void CXauCanvas::Cover(const int idx,const uint c,const double cov)
  {
   if(cov<=0.0)
      return;
   double a=(double)(c>>24)*(cov>1.0 ? 1.0 : cov);
   BlendA(idx,c,(uint)(a+0.5));
  }

//+------------------------------------------------------------------+
//| Stroke rasteriser                                                |
//+------------------------------------------------------------------+
void CXauCanvas::MaskReset(void)
  {
   m_mx0=m_w;
   m_my0=m_h;
   m_mx1=-1;
   m_my1=-1;
  }

//--- coverage of pixel (px,py) by the current capsule segment
void CXauCanvas::MaskPx(const int px,const int py)
  {
   double cx=px+0.5;
   double cy=py+0.5;
   double t=0.0;
   if(m_sinv>0.0)
     {
      t=((cx-m_sx)*m_sdx+(cy-m_sy)*m_sdy)*m_sinv;
      if(t<0.0)
         t=0.0;
      else
         if(t>1.0)
            t=1.0;
     }
   double qx=m_sx+m_sdx*t-cx;
   double qy=m_sy+m_sdy*t-cy;
   double d=MathSqrt(qx*qx+qy*qy);
   double cov=(m_shw+m_sf*0.5-d)/m_sf;
   if(cov<=0.0)
      return;
   if(cov>1.0)
      cov=1.0;
   if(m_sdashed)
     {
      double s=m_sarc+t*m_slen;
      double ph=MathMod(s,m_speriod);
      if(ph>=m_sdash)
         return;
      double edge=MathMin(ph,m_sdash-ph)+0.5;
      if(edge<1.0)
         cov*=edge;
     }
   uchar v=(uchar)(cov*255.0+0.5);
   int idx=py*m_w+px;
   if(v>m_mask[idx])
      m_mask[idx]=v;
  }

void CXauCanvas::MaskSeg(const double x1,const double y1,const double x2,const double y2,double &arc)
  {
   double dx=x2-x1;
   double dy=y2-y1;
   double len=MathSqrt(dx*dx+dy*dy);
   double reach=m_shw+m_sf*0.5+1.0;
   if(MathMax(x1,x2)+reach<0.0 || MathMin(x1,x2)-reach>m_w ||
      MathMax(y1,y2)+reach<0.0 || MathMin(y1,y2)-reach>m_h)
     {
      arc+=len;
      return;
     }
   m_sx=x1;
   m_sy=y1;
   m_sdx=dx;
   m_sdy=dy;
   m_slen=len;
   m_sinv=(len>1e-9 ? 1.0/(len*len) : 0.0);
   m_sarc=arc;
   double adx=MathAbs(dx);
   double ady=MathAbs(dy);
   if(adx>=ady)
     {
      // walk columns, cover a vertical window around the centre line
      double ext=(adx>1e-9 ? reach*len/adx : reach)+0.5;
      int c0=(int)MathFloor(MathMin(x1,x2)-reach);
      int c1=(int)MathCeil(MathMax(x1,x2)+reach);
      if(c0<0)
         c0=0;
      if(c1>m_w-1)
         c1=m_w-1;
      for(int px=c0; px<=c1; px++)
        {
         double t=(adx>1e-9 ? (px+0.5-x1)/dx : 0.0);
         t=XClamp(t,0.0,1.0);
         double yc=y1+dy*t;
         int r0=(int)MathFloor(yc-ext);
         int r1=(int)MathCeil(yc+ext);
         if(r0<0)
            r0=0;
         if(r1>m_h-1)
            r1=m_h-1;
         if(r0>r1)
            continue;
         for(int py=r0; py<=r1; py++)
           {
            MaskPx(px,py);
            if(px<m_rx0[py])
               m_rx0[py]=px;
            if(px>m_rx1[py])
               m_rx1[py]=px;
           }
         if(px<m_mx0)
            m_mx0=px;
         if(px>m_mx1)
            m_mx1=px;
         if(r0<m_my0)
            m_my0=r0;
         if(r1>m_my1)
            m_my1=r1;
        }
     }
   else
     {
      // walk rows, cover a horizontal window around the centre line
      double ext=reach*len/ady+0.5;
      int r0=(int)MathFloor(MathMin(y1,y2)-reach);
      int r1=(int)MathCeil(MathMax(y1,y2)+reach);
      if(r0<0)
         r0=0;
      if(r1>m_h-1)
         r1=m_h-1;
      for(int py=r0; py<=r1; py++)
        {
         double t=XClamp((py+0.5-y1)/dy,0.0,1.0);
         double xc=x1+dx*t;
         int c0=(int)MathFloor(xc-ext);
         int c1=(int)MathCeil(xc+ext);
         if(c0<0)
            c0=0;
         if(c1>m_w-1)
            c1=m_w-1;
         if(c0>c1)
            continue;
         for(int px=c0; px<=c1; px++)
            MaskPx(px,py);
         if(c0<m_rx0[py])
            m_rx0[py]=c0;
         if(c1>m_rx1[py])
            m_rx1[py]=c1;
         if(c0<m_mx0)
            m_mx0=c0;
         if(c1>m_mx1)
            m_mx1=c1;
         if(py<m_my0)
            m_my0=py;
         if(py>m_my1)
            m_my1=py;
        }
     }
   arc+=len;
  }

void CXauCanvas::MaskFlush(const uint c)
  {
   uint ca=c>>24;
   for(int y=m_my0; y<=m_my1; y++)
     {
      int row=y*m_w;
      int xa=m_rx0[y],xb=m_rx1[y];
      m_rx0[y]=m_w;
      m_rx1[y]=-1;
      for(int x=xa; x<=xb; x++)
        {
         int idx=row+x;
         uint v=m_mask[idx];
         if(v==0)
            continue;
         m_mask[idx]=0;
         BlendA(idx,c,(ca*v+127)/255);
        }
     }
   MaskReset();
  }

void CXauCanvas::MaskFlushLut(const uint &lut[],const double y0,const double y1,const double alpha)
  {
   int n=ArraySize(lut);
   if(n<1)
      return;
   double span=(MathAbs(y1-y0)>1e-9 ? y1-y0 : 1.0);
   double k=XClamp(alpha,0.0,1.0);
   for(int y=m_my0; y<=m_my1; y++)
     {
      int li=(int)MathRound(XClamp((y+0.5-y0)/span,0.0,1.0)*(n-1));
      uint c=lut[li];
      uint ca=(uint)((c>>24)*k+0.5);
      int row=y*m_w;
      int xa=m_rx0[y],xb=m_rx1[y];
      m_rx0[y]=m_w;
      m_rx1[y]=-1;
      for(int x=xa; x<=xb; x++)
        {
         int idx=row+x;
         uint v=m_mask[idx];
         if(v==0)
            continue;
         m_mask[idx]=0;
         BlendA(idx,c,(ca*v+127)/255);
        }
     }
   MaskReset();
  }

void CXauCanvas::MaskStroke(const double &xs[],const double &ys[],const int n,const double width,
                            const double dash,const double gap,const double feather)
  {
   m_shw=MathMax(width*m_k,0.6)*0.5;
   m_sf=MathMax(feather*(feather>1.0 ? m_k : 1.0),1.0);
   m_sdash=dash*m_k;
   m_speriod=(dash+gap)*m_k;
   m_sdashed=(dash>0.0 && gap>0.0);
   MaskReset();
   double arc=0.0;
   if(n==1)
     {
      MaskSeg(xs[0],ys[0],xs[0],ys[0],arc);
      return;
     }
   for(int i=0; i<n-1; i++)
      MaskSeg(xs[i],ys[i],xs[i+1],ys[i+1],arc);
  }

void CXauCanvas::Polyline(const double &xs[],const double &ys[],const int n,const uint c,const double width,
                          const double dash,const double gap,const double feather)
  {
   if(!Ready() || n<1 || (c>>24)==0)
      return;
   MaskStroke(xs,ys,n,width,dash,gap,feather);
   MaskFlush(c);
  }

void CXauCanvas::PolylineLut(const double &xs[],const double &ys[],const int n,const uint &lut[],
                             const double y_top,const double y_bottom,const double width,
                             const double alpha,const double feather)
  {
   if(!Ready() || n<1)
      return;
   MaskStroke(xs,ys,n,width,0.0,0.0,feather);
   MaskFlushLut(lut,y_top,y_bottom,alpha);
  }

void CXauCanvas::Line(const double x1,const double y1,const double x2,const double y2,const uint c,
                      const double width,const double dash,const double gap)
  {
   double xs[2];
   double ys[2];
   xs[0]=x1;
   ys[0]=y1;
   xs[1]=x2;
   ys[1]=y2;
   Polyline(xs,ys,2,c,width,dash,gap);
  }

//+------------------------------------------------------------------+
//| Fill between two straight edges over [xa, xb].                   |
//| Edge 1 runs ya1->yb1, edge 2 runs ya2->yb2. fade is the alpha     |
//| multiplier reached at edge 2 (1 = flat fill, 0 = fade out).        |
//| Pixel columns are owned by exactly one segment, so neighbouring   |
//| segments never overlap.                                           |
//+------------------------------------------------------------------+
void CXauCanvas::Band(const double xa,const double ya1,const double ya2,const double xb,const double yb1,
                      const double yb2,const uint c,const double fade)
  {
   if(!Ready() || (c>>24)==0 || xb<xa)
      return;
   int c0=(int)MathCeil(xa-0.5);
   int c1=(int)MathCeil(xb-0.5)-1;
   if(c0<0)
      c0=0;
   if(c1>m_w-1)
      c1=m_w-1;
   double dx=xb-xa;
   double ca=(double)(c>>24);
   bool flat=(fade>=0.999);
   for(int px=c0; px<=c1; px++)
     {
      double t=(dx>1e-9 ? XClamp((px+0.5-xa)/dx,0.0,1.0) : 0.0);
      double e1=ya1+(yb1-ya1)*t;
      double e2=ya2+(yb2-ya2)*t;
      double top=MathMin(e1,e2);
      double bot=MathMax(e1,e2);
      double span=bot-top;
      if(span<1e-6)
         continue;
      int r0=(int)MathFloor(top);
      int r1=(int)MathCeil(bot)-1;
      if(r0<0)
         r0=0;
      if(r1>m_h-1)
         r1=m_h-1;
      for(int py=r0; py<=r1; py++)
        {
         double cov=MathMin(py+1.0,bot)-MathMax((double)py,top);
         if(cov<=0.0)
            continue;
         double a=ca*(cov>1.0 ? 1.0 : cov);
         if(!flat)
           {
            double f=MathAbs(py+0.5-e1)/span;
            a*=1.0+(fade-1.0)*XClamp(f,0.0,1.0);
           }
         BlendA(py*m_w+px,c,(uint)(a+0.5));
        }
     }
  }

void CXauCanvas::FillRect(const double x1,const double y1,const double x2,const double y2,const uint c)
  {
   if(!Ready() || (c>>24)==0)
      return;
   double l=MathMin(x1,x2);
   double r=MathMax(x1,x2);
   double t=MathMin(y1,y2);
   double b=MathMax(y1,y2);
   int c0=(int)MathFloor(l);
   int c1=(int)MathCeil(r)-1;
   int r0=(int)MathFloor(t);
   int r1=(int)MathCeil(b)-1;
   if(c0<0)
      c0=0;
   if(r0<0)
      r0=0;
   if(c1>m_w-1)
      c1=m_w-1;
   if(r1>m_h-1)
      r1=m_h-1;
   for(int py=r0; py<=r1; py++)
     {
      double cy=MathMin(py+1.0,b)-MathMax((double)py,t);
      if(cy<=0.0)
         continue;
      int row=py*m_w;
      for(int px=c0; px<=c1; px++)
        {
         double cx=MathMin(px+1.0,r)-MathMax((double)px,l);
         if(cx<=0.0)
            continue;
         Cover(row+px,c,cx*cy);
        }
     }
  }

//--- signed-distance rounded rectangle; border is drawn inside the edge
void CXauCanvas::RoundRect(const double x1,const double y1,const double x2,const double y2,const double radius,
                           const uint fill,const uint border,const double border_width)
  {
   if(!Ready())
      return;
   double l=MathMin(x1,x2);
   double r=MathMax(x1,x2);
   double t=MathMin(y1,y2);
   double b=MathMax(y1,y2);
   double hx=(r-l)*0.5;
   double hy=(b-t)*0.5;
   if(hx<=0.0 || hy<=0.0)
      return;
   double cx=(l+r)*0.5;
   double cy=(t+b)*0.5;
   double rad=XClamp(radius,0.0,MathMin(hx,hy));
   bool do_fill=((fill>>24)!=0);
   bool do_border=((border>>24)!=0 && border_width>0.0);
   if(!do_fill && !do_border)
      return;
   int c0=(int)MathFloor(l)-1;
   int c1=(int)MathCeil(r)+1;
   int r0=(int)MathFloor(t)-1;
   int r1=(int)MathCeil(b)+1;
   if(c0<0)
      c0=0;
   if(r0<0)
      r0=0;
   if(c1>m_w-1)
      c1=m_w-1;
   if(r1>m_h-1)
      r1=m_h-1;
   double ix=hx-rad;
   double iy=hy-rad;
   for(int py=r0; py<=r1; py++)
     {
      double ay=MathAbs(py+0.5-cy)-iy;
      int row=py*m_w;
      for(int px=c0; px<=c1; px++)
        {
         double ax=MathAbs(px+0.5-cx)-ix;
         double ox=(ax>0.0 ? ax : 0.0);
         double oy=(ay>0.0 ? ay : 0.0);
         double d=MathSqrt(ox*ox+oy*oy)+MathMin(MathMax(ax,ay),0.0)-rad;
         double outer=XClamp(0.5-d,0.0,1.0);
         if(outer<=0.0)
            continue;
         int idx=row+px;
         if(do_fill)
            Cover(idx,fill,outer);
         if(do_border)
           {
            double inner=XClamp(0.5-(d+border_width),0.0,1.0);
            Cover(idx,border,outer-inner);
           }
        }
     }
  }

void CXauCanvas::Circle(const double cx,const double cy,const double r,const uint fill,const uint border,
                        const double border_width)
  {
   if(!Ready() || r<=0.0)
      return;
   int c0=(int)MathFloor(cx-r)-1;
   int c1=(int)MathCeil(cx+r)+1;
   int r0=(int)MathFloor(cy-r)-1;
   int r1=(int)MathCeil(cy+r)+1;
   if(c0<0)
      c0=0;
   if(r0<0)
      r0=0;
   if(c1>m_w-1)
      c1=m_w-1;
   if(r1>m_h-1)
      r1=m_h-1;
   bool do_border=((border>>24)!=0 && border_width>0.0);
   for(int py=r0; py<=r1; py++)
     {
      double dy=py+0.5-cy;
      for(int px=c0; px<=c1; px++)
        {
         double dx=px+0.5-cx;
         double d=MathSqrt(dx*dx+dy*dy)-r;
         double outer=XClamp(0.5-d,0.0,1.0);
         if(outer<=0.0)
            continue;
         int idx=py*m_w+px;
         Cover(idx,fill,outer);
         if(do_border)
            Cover(idx,border,outer-XClamp(0.5-(d+border_width),0.0,1.0));
        }
     }
  }

void CXauCanvas::Triangle(double x1,double y1,double x2,double y2,double x3,double y3,const uint c)
  {
   if(!Ready() || (c>>24)==0)
      return;
   double s=(x2-x1)*(y3-y1)-(y2-y1)*(x3-x1);
   if(MathAbs(s)<1e-9)
      return;
   if(s<0.0)
     {
      double tx=x2;
      double ty=y2;
      x2=x3;
      y2=y3;
      x3=tx;
      y3=ty;
     }
   double l1=MathSqrt((x2-x1)*(x2-x1)+(y2-y1)*(y2-y1));
   double l2=MathSqrt((x3-x2)*(x3-x2)+(y3-y2)*(y3-y2));
   double l3=MathSqrt((x1-x3)*(x1-x3)+(y1-y3)*(y1-y3));
   if(l1<1e-9 || l2<1e-9 || l3<1e-9)
      return;
   int c0=(int)MathFloor(MathMin(x1,MathMin(x2,x3)))-1;
   int c1=(int)MathCeil(MathMax(x1,MathMax(x2,x3)))+1;
   int r0=(int)MathFloor(MathMin(y1,MathMin(y2,y3)))-1;
   int r1=(int)MathCeil(MathMax(y1,MathMax(y2,y3)))+1;
   if(c0<0)
      c0=0;
   if(r0<0)
      r0=0;
   if(c1>m_w-1)
      c1=m_w-1;
   if(r1>m_h-1)
      r1=m_h-1;
   for(int py=r0; py<=r1; py++)
     {
      double cy=py+0.5;
      for(int px=c0; px<=c1; px++)
        {
         double cx=px+0.5;
         double d1=((x2-x1)*(cy-y1)-(y2-y1)*(cx-x1))/l1;
         double d2=((x3-x2)*(cy-y2)-(y3-y2)*(cx-x2))/l2;
         double d3=((x1-x3)*(cy-y3)-(y1-y3)*(cx-x3))/l3;
         double cov=XClamp(MathMin(d1,MathMin(d2,d3))+0.5,0.0,1.0);
         if(cov>0.0)
            Cover(py*m_w+px,c,cov);
        }
     }
  }

//+------------------------------------------------------------------+
//| Text                                                             |
//+------------------------------------------------------------------+
void CXauCanvas::SetFont(const string face,const double points,const uint weight)
  {
   m_face=face;
   m_size=-(int)MathRound(points*10.0); // negative = tenths of a point, follows OS DPI
   m_weight=weight;
  }

void CXauCanvas::Text(const double x,const double y,const string text,const uint c,const uint align)
  {
   if(!Ready() || text=="")
      return;
   TextSetFont(m_face,m_size,m_weight);
   TextOut(text,(int)MathRound(x),(int)MathRound(y),align,m_px,m_w,m_h,c,COLOR_FORMAT_ARGB_NORMALIZE);
  }

void CXauCanvas::TextSize(const string text,int &w,int &h)
  {
   uint tw=0;
   uint th=0;
   TextSetFont(m_face,m_size,m_weight);
   TextGetSize(text,tw,th);
   w=(int)tw;
   h=(int)th;
  }

//+------------------------------------------------------------------+
//| Widgets                                                          |
//+------------------------------------------------------------------+
void CXauCanvas::PillSize(const string text,const double points,double &w,double &h)
  {
   SetFont(XAU_FONT,points,FW_SEMIBOLD);
   int tw=0;
   int th=0;
   TextSize(text,tw,th);
   w=tw+12.0*m_k;
   h=th+4.0*m_k;
  }

//--- rounded label with an optional pointer towards (x,y), like TradingView's label style
void CXauCanvas::Pill(const double x,const double y,const string text,const uint bg,const uint fg,
                      const ENUM_XAU_ANCHOR anchor,const double points,const uint border,const bool pointer)
  {
   if(!Ready())
      return;
   double bw=0.0;
   double bh=0.0;
   PillSize(text,points,bw,bh);
   double p=(pointer && anchor!=XA_CENTER ? 4.0*m_k : 0.0);
   double gap=2.0*m_k;
   double l=x-bw*0.5;
   double t=y-bh*0.5;
   if(anchor==XA_ABOVE)
      t=y-gap-p-bh;
   else
      if(anchor==XA_BELOW)
         t=y+gap+p;
      else
         if(anchor==XA_RIGHT)
            l=x+gap+p;
         else
            if(anchor==XA_LEFT)
               l=x-gap-p-bw;
   if(p>0.0)
     {
      if(anchor==XA_ABOVE)
         Triangle(x-p,t+bh-0.6,x+p,t+bh-0.6,x,y-gap,bg);
      else
         if(anchor==XA_BELOW)
            Triangle(x-p,t+0.6,x+p,t+0.6,x,y+gap,bg);
         else
            if(anchor==XA_RIGHT)
               Triangle(l+0.6,y-p,l+0.6,y+p,x+gap,y,bg);
            else
               Triangle(l+bw-0.6,y-p,l+bw-0.6,y+p,x-gap,y,bg);
     }
   RoundRect(l,t,l+bw,t+bh,MathMin(bh*0.5,4.0*m_k),bg,border,1.0);
   SetFont(XAU_FONT,points,FW_SEMIBOLD);
   Text(l+bw*0.5,t+bh*0.5,text,fg,TA_CENTER|TA_VCENTER);
  }

void CXauCanvas::Card(const double x,const double y,const double w,const double h,const uint bg,
                      const uint border,const uint accent)
  {
   double r=8.0*m_k;
   // soft drop shadow
   RoundRect(x+1.0*m_k,y+3.0*m_k,x+w+1.0*m_k,y+h+3.0*m_k,r+2.0*m_k,XArgb(0,0,0,0.10));
   RoundRect(x,y+1.5*m_k,x+w,y+h+1.5*m_k,r+1.0*m_k,XArgb(0,0,0,0.10));
   RoundRect(x,y,x+w,y+h,r,bg,border,1.0);
   if((accent>>24)!=0)
      RoundRect(x+r,y,x+w-r,y+2.0*m_k,1.0*m_k,accent);
  }

//--- progress / gauge track with a filled portion (frac 0..1)
void CXauCanvas::Bar(const double x,const double y,const double w,const double h,const double frac,
                     const uint track,const uint fill)
  {
   double r=h*0.5;
   RoundRect(x,y,x+w,y+h,r,track);
   double f=XClamp(frac,0.0,1.0);
   if(f>0.0)
      RoundRect(x,y,x+MathMax(w*f,h),y+h,r,fill);
  }

#endif
//+------------------------------------------------------------------+
