//+------------------------------------------------------------------+
//|                                                       XauUI.mqh  |
//|        XAU Suite for MetaTrader 5 - TradingView-style chart UI   |
//|                                                                  |
//| CXauUI       one legend row per indicator (top-left of its        |
//|              window): show / hide eye, settings gear and a quick  |
//|              settings popover with layer switches + theme cycle.  |
//| CXauMovable  drag (header), resize (corner grip), collapse        |
//|              (chevron) and double-click for dashboard cards.      |
//|                                                                  |
//| State is stored per chart in terminal global variables, so it     |
//| survives time frame changes. While the cursor is over a widget,   |
//| chart scrolling is paused so dragging moves the widget instead.   |
//+------------------------------------------------------------------+
#ifndef XAU_UI_MQH
#define XAU_UI_MQH

#include "XauTheme.mqh"
#include "XauCanvas.mqh"

#define XUI_NONE     0
#define XUI_PAINT    1   // only the widget changed
#define XUI_VISUAL   2   // the indicator's drawing must be redone
#define XUI_THEME    4   // the suite theme changed
#define XUI_MAX_OPTS 12

#define XMV_NONE     0
#define XMV_MOVED    1
#define XMV_RESIZED  2
#define XMV_TOGGLED  4
#define XMV_DBLCLICK 8
#define XMV_HOVER    16

//+------------------------------------------------------------------+
//| Shared helpers                                                   |
//+------------------------------------------------------------------+
//--- stable numeric id for a name (global variable keys, ownership)
double XUid(const string s)
  {
   double h=7.0;
   int n=StringLen(s);
   for(int i=0; i<n; i++)
      h=MathMod(h*131.0+StringGetCharacter(s,i),999999937.0);
   return(h+1.0);
  }

string XChartKey(void)
  {
   return("XAU."+IntegerToString(ChartID())+".");
  }

//--- y of a sub-window's top edge in chart (mouse) coordinates
int XWindowTop(const int sub)
  {
   if(sub<=0)
      return(0);
   return((int)ChartGetInteger(0,CHART_WINDOW_YDISTANCE,sub));
  }

bool XMouseLeft(const string sparam)
  {
   return((((int)StringToInteger(sparam))&1)!=0);
  }

//--- pause chart scrolling while the cursor is over a widget; the last widget entered owns it
void XHoverScroll(const double uid,const bool over)
  {
   string gv=XChartKey()+"scroll";
   if(over)
     {
      GlobalVariableTemp(gv);
      GlobalVariableSet(gv,uid);
      ChartSetInteger(0,CHART_MOUSE_SCROLL,false);
      return;
     }
   if(GlobalVariableCheck(gv) && GlobalVariableGet(gv)==uid)
     {
      GlobalVariableDel(gv);
      ChartSetInteger(0,CHART_MOUSE_SCROLL,true);
     }
  }

//--- small vector icons -------------------------------------------------
void XDrawChevron(CXauCanvas &cv,const double cx,const double cy,const bool up,const uint c)
  {
   double k=cv.K();
   double d=(up ? -1.0 : 1.0);
   cv.Line(cx-4.0*k,cy-2.0*k*d,cx,cy+2.0*k*d,c,1.6);
   cv.Line(cx,cy+2.0*k*d,cx+4.0*k,cy-2.0*k*d,c,1.6);
  }

void XDrawGrip(CXauCanvas &cv,const double x2,const double y2,const uint c)
  {
   double k=cv.K();
   cv.Line(x2-11.0*k,y2-3.0*k,x2-3.0*k,y2-11.0*k,c,1.2);
   cv.Line(x2-7.0*k,y2-3.0*k,x2-3.0*k,y2-7.0*k,c,1.2);
  }

void XDrawEye(CXauCanvas &cv,const double cx,const double cy,const bool closed,const uint c)
  {
   double k=cv.K();
   double xs[25],ys[25];
   for(int j=0; j<=12; j++)
     {
      double a=-1.0+2.0*j/12.0;
      xs[j]=cx+a*6.5*k;
      ys[j]=cy-(1.0-a*a)*4.2*k;
      xs[24-j]=xs[j];
      ys[24-j]=cy+(1.0-a*a)*4.2*k;
     }
   cv.Polyline(xs,ys,25,c,1.3);
   cv.Circle(cx,cy,2.2*k,c);
   if(closed)
      cv.Line(cx-6.0*k,cy+5.0*k,cx+6.0*k,cy-5.0*k,c,1.5);
  }

void XDrawGear(CXauCanvas &cv,const double cx,const double cy,const uint c,const uint hole)
  {
   double k=cv.K();
   for(int j=0; j<8; j++)
     {
      double a=j*M_PI/4.0;
      cv.Line(cx+MathCos(a)*3.5*k,cy+MathSin(a)*3.5*k,cx+MathCos(a)*6.3*k,cy+MathSin(a)*6.3*k,c,2.2);
     }
   cv.Circle(cx,cy,4.6*k,c);
   cv.Circle(cx,cy,1.9*k,hole);
  }

void XDrawSwitch(CXauCanvas &cv,const double x,const double cy,const bool on,const uint on_rgb,const XauTheme &t)
  {
   double k=cv.K();
   double w=26.0*k,h=14.0*k;
   cv.RoundRect(x,cy-h*0.5,x+w,cy+h*0.5,h*0.5,on ? XRgb(on_rgb,0.95) : XRgb(t.border,1.0));
   double kx=(on ? x+w-h*0.5 : x+h*0.5);
   cv.Circle(kx,cy,h*0.5-2.0*k,XRgb(on ? 0xFFFFFF : t.muted,1.0));
  }

//+------------------------------------------------------------------+
//| Legend row + quick settings                                      |
//+------------------------------------------------------------------+
class CXauUI
  {
private:
   string            m_name;
   string            m_key;
   double            m_uid;
   uint              m_accent;
   int               m_sub;
   CXauCanvas        m_cv;
   XauTheme          m_t;
   bool              m_hidden;
   bool              m_open;
   int               m_n;
   string            m_label[XUI_MAX_OPTS];
   bool              m_val[XUI_MAX_OPTS];
   bool              m_inp[XUI_MAX_OPTS];
   int               m_x;
   int               m_y;
   double            m_k;
   int               m_hover;
   bool              m_down;
   int               m_down_hit;
   bool              m_over;

   double            RowW(void) const   { return(232.0*m_k); }
   double            RowH(void) const   { return(20.0*m_k); }
   double            Gap(void) const    { return(6.0*m_k); }
   double            PopW(void) const   { return(250.0*m_k); }
   double            PopH(void) const   { return(30.0*m_k+(m_n+1)*22.0*m_k+28.0*m_k); }
   int               Index(void) const;
   int               Hit(const double lx,const double ly) const;
   int               Click(const int hit);
   void              PopState(void);
   void              Save(void);

public:
                     CXauUI(void);
                    ~CXauUI(void) { Destroy(); }
   void              Init(const string name,const uint accent_rgb);
   int               Add(const string label,const bool input_value);
   bool              Opt(const int i) const { return(i>=0 && i<m_n ? m_val[i] : true); }
   bool              Hidden(void) const     { return(m_hidden); }
   void              SetTheme(const XauTheme &t) { m_t=t; }
   void              Draw(const int sub);
   int               OnEvent(const int id,const long lparam,const double dparam,const string sparam);
   void              OpenSettings(void);
   bool              Blocked(void) const;
   void              Destroy(void);
  };

CXauUI::CXauUI(void) : m_uid(1.0),m_accent(0xF6C453),m_sub(0),m_hidden(false),m_open(false),m_n(0),
   m_x(0),m_y(0),m_k(1.0),m_hover(0),m_down(false),m_down_hit(0),m_over(false)
  {
  }

void CXauUI::Init(const string name,const uint accent_rgb)
  {
   m_name=name;
   m_accent=accent_rgb;
   m_uid=XUid(name);
   m_key=XChartKey()+DoubleToString(m_uid,0)+".";
   m_k=m_cv.K();
   m_hidden=(GlobalVariableCheck(m_key+"h") && GlobalVariableGet(m_key+"h")>0.5);
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
  }

//--- runtime switch seeded from an input; a stored override is dropped once that input changes
int CXauUI::Add(const string label,const bool input_value)
  {
   if(m_n>=XUI_MAX_OPTS)
      return(-1);
   int i=m_n++;
   m_label[i]=label;
   m_inp[i]=input_value;
   m_val[i]=input_value;
   string gv=m_key+"o"+IntegerToString(i);
   if(GlobalVariableCheck(gv))
     {
      int v=(int)GlobalVariableGet(gv);
      if(((v&1)!=0)==input_value)
         m_val[i]=((v&2)!=0);
     }
   return(i);
  }

void CXauUI::Save(void)
  {
   GlobalVariableSet(m_key+"h",m_hidden ? 1.0 : 0.0);
   for(int i=0; i<m_n; i++)
      GlobalVariableSet(m_key+"o"+IntegerToString(i),(double)((m_inp[i] ? 1 : 0)+(m_val[i] ? 2 : 0)));
  }

//--- position among the XAU indicators of this window decides the legend row
int CXauUI::Index(void) const
  {
   int n=ChartIndicatorsTotal(0,m_sub);
   int idx=0;
   for(int i=0; i<n; i++)
     {
      string nm=ChartIndicatorName(0,m_sub,i);
      if(nm==m_name)
         return(idx);
      if(StringFind(nm,"XAU ")==0)
         idx++;
     }
   return(idx);
  }

bool CXauUI::Blocked(void) const
  {
   string gv=XChartKey()+"pop";
   if(GlobalVariableCheck(gv) && GlobalVariableGet(gv)!=m_uid)
      return(true);
   string gt=XChartKey()+"popt";
   if(GlobalVariableCheck(gt))
     {
      double dt=(double)GetTickCount()-GlobalVariableGet(gt);
      if(dt>=0.0 && dt<250.0)
         return(true);
     }
   return(false);
  }

void CXauUI::PopState(void)
  {
   string gv=XChartKey()+"pop";
   if(m_open)
     {
      GlobalVariableTemp(gv);
      GlobalVariableSet(gv,m_uid);
      m_cv.Destroy(); // recreated on the next Draw, which puts it above the other widgets
      return;
     }
   if(GlobalVariableCheck(gv) && GlobalVariableGet(gv)==m_uid)
      GlobalVariableDel(gv);
   string gt=XChartKey()+"popt";
   GlobalVariableTemp(gt);
   GlobalVariableSet(gt,(double)GetTickCount());
  }

void CXauUI::OpenSettings(void)
  {
   if(m_open)
      return;
   m_open=true;
   PopState();
   Draw(m_sub);
   ChartRedraw();
  }

//--- 0 none, 1 eye, 2 gear, 3 row, 4 close, 5 popover body, 7 theme, 10+i switch
int CXauUI::Hit(const double lx,const double ly) const
  {
   if(lx<0.0 || ly<0.0)
      return(0);
   double rw=RowW(),rh=RowH();
   if(lx<=rw && ly<=rh)
     {
      if(MathAbs(lx-(rw-44.0*m_k))<=10.0*m_k)
         return(1);
      if(MathAbs(lx-(rw-18.0*m_k))<=10.0*m_k)
         return(2);
      return(3);
     }
   if(!m_open)
      return(0);
   double px=rw+Gap();
   if(lx<px || lx>px+PopW() || ly>PopH())
      return(0);
   if(ly<28.0*m_k)
      return(lx>=px+PopW()-28.0*m_k ? 4 : 5);
   double y0=30.0*m_k;
   int i=(int)MathFloor((ly-y0)/(22.0*m_k));
   if(ly>=y0 && i>=0 && i<m_n)
      return(10+i);
   if(ly>=y0 && i==m_n)
      return(7);
   return(5);
  }

int CXauUI::Click(const int hit)
  {
   if(hit==1)
     {
      m_hidden=!m_hidden;
      Save();
      return(XUI_VISUAL|XUI_PAINT);
     }
   if(hit==2 || hit==3)
     {
      m_open=!m_open;
      PopState();
      return(XUI_PAINT);
     }
   if(hit==4)
     {
      m_open=false;
      PopState();
      return(XUI_PAINT);
     }
   if(hit==7)
     {
      int next=((int)XauResolveTheme(XAU_THEME_AUTO)+1)%4;
      XauSetSuiteTheme((ENUM_XAU_THEME)next);
      return(XUI_THEME|XUI_PAINT);
     }
   if(hit>=10 && hit<10+m_n)
     {
      m_val[hit-10]=!m_val[hit-10];
      Save();
      return(XUI_VISUAL|XUI_PAINT);
     }
   return(XUI_NONE);
  }

void CXauUI::Draw(const int sub)
  {
   m_sub=sub;
   m_k=m_cv.K();
   double k=m_k;
   double rw=RowW(),rh=RowH();
   int top=(int)MathRound((sub==0 ? 22.0 : 18.0)*k);
   m_x=(int)MathRound(6.0*k);
   m_y=top+(int)MathRound(Index()*(rh+3.0*k));
   int w=(int)MathCeil(m_open ? rw+Gap()+PopW()+8.0*k : rw+1.0);
   int h=(int)MathCeil(m_open ? MathMax(rh,PopH())+8.0*k : rh+1.0);
   string obj="XAU.ui."+DoubleToString(m_uid,0)+"."+IntegerToString(sub);
   if(!m_cv.Attach(obj,sub,false) || !m_cv.Place(m_x,m_y,w,h))
      return;
   m_cv.Clear();

   //--- legend row
   bool active=(m_hover>0 && m_hover<4) || m_open;
   m_cv.RoundRect(0,0,rw,rh,5.0*k,XRgb(m_t.panel,active ? 0.95 : 0.66),active ? XRgb(m_t.border,1.0) : 0,1.0);
   m_cv.Circle(11.0*k,rh*0.5,3.5*k,XRgb(m_accent,m_hidden ? 0.35 : 1.0));
   m_cv.SetFont(XAU_FONT,8.0,FW_SEMIBOLD);
   m_cv.Text(21.0*k,rh*0.5,m_name,XRgb(m_t.text,m_hidden ? 0.40 : 0.95),TA_LEFT|TA_VCENTER);
   uint ic_eye=XRgb(m_hover==1 ? m_t.text : m_t.muted,1.0);
   uint ic_gear=XRgb(m_hover==2 || m_open ? m_t.gold : m_t.muted,1.0);
   XDrawEye(m_cv,rw-44.0*k,rh*0.5,m_hidden,ic_eye);
   XDrawGear(m_cv,rw-18.0*k,rh*0.5,ic_gear,XRgb(m_t.panel,1.0));

   //--- quick settings popover
   if(m_open)
     {
      double px=rw+Gap(),pw=PopW(),ph=PopH();
      m_cv.Card(px,0,pw,ph,XRgb(m_t.panel,0.97),XRgb(m_t.border,1.0),XRgb(m_accent,0.95));
      m_cv.SetFont(XAU_FONT,8.5,FW_BOLD);
      m_cv.Text(px+12.0*k,15.0*k,m_name,XRgb(m_t.text,1.0),TA_LEFT|TA_VCENTER);
      uint xc=XRgb(m_hover==4 ? m_t.bear : m_t.muted,1.0);
      double cx=px+pw-14.0*k,cy=15.0*k;
      m_cv.Line(cx-4.0*k,cy-4.0*k,cx+4.0*k,cy+4.0*k,xc,1.5);
      m_cv.Line(cx-4.0*k,cy+4.0*k,cx+4.0*k,cy-4.0*k,xc,1.5);
      double y0=30.0*k,row=22.0*k;
      for(int i=0; i<=m_n; i++)
        {
         double ry=y0+i*row;
         int id=(i<m_n ? 10+i : 7);
         if(m_hover==id)
            m_cv.RoundRect(px+4.0*k,ry+1.0*k,px+pw-4.0*k,ry+row-1.0*k,5.0*k,XRgb(m_t.border,0.55));
         m_cv.SetFont(XAU_FONT,8.0,FW_NORMAL);
         if(i<m_n)
           {
            m_cv.Text(px+12.0*k,ry+row*0.5,m_label[i],XRgb(m_t.text,m_val[i] ? 0.95 : 0.55),TA_LEFT|TA_VCENTER);
            XDrawSwitch(m_cv,px+pw-40.0*k,ry+row*0.5,m_val[i],m_accent,m_t);
           }
         else
           {
            m_cv.Text(px+12.0*k,ry+row*0.5,"Theme (all charts)",XRgb(m_t.text,0.95),TA_LEFT|TA_VCENTER);
            m_cv.SetFont(XAU_FONT,8.0,FW_SEMIBOLD);
            m_cv.Text(px+pw-26.0*k,ry+row*0.5,XauThemeName(XAU_THEME_AUTO),XRgb(m_t.gold,1.0),TA_RIGHT|TA_VCENTER);
            XDrawChevron(m_cv,px+pw-15.0*k,ry+row*0.5,false,XRgb(m_t.gold,1.0));
           }
        }
      m_cv.SetFont(XAU_FONT,7.0,FW_NORMAL);
      m_cv.Text(px+12.0*k,ph-15.0*k,"Lengths & levels: press Ctrl+I,",XRgb(m_t.muted,1.0),TA_LEFT|TA_VCENTER);
      m_cv.Text(px+12.0*k,ph-4.0*k,"pick this indicator and click Edit",XRgb(m_t.muted,1.0),TA_LEFT|TA_BOTTOM);
     }
   m_cv.Flush();
  }

int CXauUI::OnEvent(const int id,const long lparam,const double dparam,const string sparam)
  {
   if(id!=CHARTEVENT_MOUSE_MOVE || !m_cv.Ready())
      return(XUI_NONE);
   double lx=(double)lparam-m_x;
   double ly=dparam-XWindowTop(m_sub)-m_y;
   bool btn=XMouseLeft(sparam);
   int hit=Hit(lx,ly);
   int res=XUI_NONE;
   bool over=(hit!=0);
   if(over!=m_over)
     {
      m_over=over;
      XHoverScroll(m_uid,over);
     }
   if(hit!=m_hover)
     {
      m_hover=hit;
      res|=XUI_PAINT;
     }
   if(btn && !m_down)
     {
      m_down=true;
      m_down_hit=hit;
     }
   else
      if(!btn && m_down)
        {
         m_down=false;
         if(hit!=0 && hit==m_down_hit)
           {
            if(m_open || !Blocked())
               res|=Click(hit);
           }
         else
            if(hit==0 && m_open)
              {
               m_open=false;
               PopState();
               res|=XUI_PAINT;
              }
        }
   if((res&XUI_PAINT)!=0)
     {
      Draw(m_sub);
      ChartRedraw();
     }
   return(res);
  }

void CXauUI::Destroy(void)
  {
   if(m_over)
      XHoverScroll(m_uid,false);
   m_over=false;
   if(m_open)
     {
      m_open=false;
      PopState();
     }
   m_cv.Destroy();
  }

//+------------------------------------------------------------------+
//| Movable / resizable / collapsible card                           |
//+------------------------------------------------------------------+
class CXauMovable
  {
private:
   string            m_key;
   double            m_uid;
   int               m_sub;
   bool              m_down;
   bool              m_drag;
   bool              m_size;
   bool              m_over;
   bool              m_moved;
   int               m_gx;
   int               m_gy;
   int               m_dx;
   int               m_dy;
   double            m_s0;
   double            m_w0;
   uint              m_last_click;

   int               Region(const double mx,const double my) const;

public:
   int               x;          // card top-left in window pixels, -1 = default placement
   int               y;
   double            scale;      // user size multiplier
   bool              collapsed;
   int               hover;      // 0 none, 1 header, 2 collapse, 3 grip, 4 body
   //--- regions in window pixels, refreshed by XCardBegin
   double            bx1,by1,bx2,by2,hy2;
   double            cx1,cy1,cx2,cy2;
   double            gx1,gy1;

                     CXauMovable(void);
                    ~CXauMovable(void) { if(m_over) XHoverScroll(m_uid,false); }
   void              Init(const string tag,const int sub);
   void              Save(void);
   void              SetSub(const int sub) { m_sub=sub; }
   int               Sub(void) const { return(m_sub); }
   int               OnEvent(const int id,const long lparam,const double dparam,const string sparam);
  };

CXauMovable::CXauMovable(void) : m_uid(1.0),m_sub(0),m_down(false),m_drag(false),m_size(false),m_over(false),
   m_moved(false),m_gx(0),m_gy(0),m_dx(0),m_dy(0),m_s0(1.0),m_w0(1.0),m_last_click(0),x(-1),y(-1),scale(1.0),
   collapsed(false),hover(0),bx1(0),by1(0),bx2(0),by2(0),hy2(0),cx1(0),cy1(0),cx2(0),cy2(0),gx1(0),gy1(0)
  {
  }

void CXauMovable::Init(const string tag,const int sub)
  {
   m_sub=sub;
   m_uid=XUid(tag);
   m_key=XChartKey()+"mv."+DoubleToString(m_uid,0)+".";
   if(GlobalVariableCheck(m_key+"x"))
     {
      x=(int)GlobalVariableGet(m_key+"x");
      y=(int)GlobalVariableGet(m_key+"y");
     }
   if(GlobalVariableCheck(m_key+"s"))
      scale=XClamp(GlobalVariableGet(m_key+"s"),0.6,1.8);
   if(GlobalVariableCheck(m_key+"c"))
      collapsed=(GlobalVariableGet(m_key+"c")>0.5);
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
  }

void CXauMovable::Save(void)
  {
   GlobalVariableSet(m_key+"x",x);
   GlobalVariableSet(m_key+"y",y);
   GlobalVariableSet(m_key+"s",scale);
   GlobalVariableSet(m_key+"c",collapsed ? 1.0 : 0.0);
  }

int CXauMovable::Region(const double mx,const double my) const
  {
   if(mx<bx1 || mx>bx2 || my<by1 || my>by2)
      return(0);
   if(mx>=cx1 && mx<=cx2 && my>=cy1 && my<=cy2)
      return(2);
   if(!collapsed && mx>=gx1 && my>=gy1)
      return(3);
   if(my<=hy2)
      return(1);
   return(4);
  }

int CXauMovable::OnEvent(const int id,const long lparam,const double dparam,const string sparam)
  {
   if(id!=CHARTEVENT_MOUSE_MOVE || bx2<=bx1)
      return(XMV_NONE);
   int mx=(int)lparam;
   int my=(int)MathRound(dparam)-XWindowTop(m_sub);
   bool btn=XMouseLeft(sparam);
   int r=Region(mx,my);
   int res=XMV_NONE;
   bool over=(r!=0 || m_drag || m_size);
   if(over!=m_over)
     {
      m_over=over;
      XHoverScroll(m_uid,over);
     }
   if(r!=hover)
     {
      hover=r;
      res|=XMV_HOVER;
     }
   if(btn && !m_down)
     {
      m_down=true;
      m_moved=false;
      m_dx=mx;
      m_dy=my;
      if(r==3)
        {
         m_size=true;
         m_s0=scale;
         m_w0=MathMax(bx2-bx1,40.0);
        }
      else
         if(r==1 || r==4)
           {
            m_drag=true;
            m_gx=mx-(int)bx1;
            m_gy=my-(int)by1;
           }
     }
   else
      if(btn && m_down)
        {
         if(MathAbs(mx-m_dx)+MathAbs(my-m_dy)>3)
            m_moved=true;
         if(m_drag && m_moved)
           {
            x=mx-m_gx;
            y=my-m_gy;
            res|=XMV_MOVED;
           }
         if(m_size && m_moved)
           {
            scale=XClamp(m_s0*(m_w0+(mx-m_dx))/m_w0,0.6,1.8);
            res|=XMV_RESIZED;
           }
        }
      else
         if(!btn && m_down)
           {
            m_down=false;
            bool was_drag=m_drag,was_size=m_size;
            m_drag=false;
            m_size=false;
            if((was_drag || was_size) && m_moved)
               Save();
            else
               if(!m_moved && r==2)
                 {
                  collapsed=!collapsed;
                  Save();
                  res|=XMV_TOGGLED;
                 }
               else
                  if(!m_moved && (r==1 || r==4))
                    {
                     uint now=GetTickCount();
                     if(m_last_click>0 && now-m_last_click<450)
                       {
                        res|=XMV_DBLCLICK;
                        m_last_click=0;
                       }
                     else
                        m_last_click=now;
                    }
            if(r==0 && m_over)
              {
               m_over=false;
               XHoverScroll(m_uid,false);
              }
           }
   return(res);
  }

//+------------------------------------------------------------------+
//| Place a card canvas for a movable card of size w x h (px).        |
//| def_x / def_y: default top-left. ox / oy: card origin inside the  |
//| canvas (a margin is kept for the shadow).                         |
//+------------------------------------------------------------------+
bool XCardBegin(CXauCanvas &cv,const string name,CXauMovable &mv,const double w,const double h,
                const double header_h,const int def_x,const int def_y,double &ox,double &oy)
  {
   int sub=mv.Sub();
   double k=cv.K();
   double m=7.0*k;
   int win_w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int win_h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,sub);
   int px=(mv.x>=0 ? mv.x : def_x);
   int py=(mv.y>=0 ? mv.y : def_y);
   px=(int)XClamp(px,m,MathMax(m,win_w-w-m));
   py=(int)XClamp(py,m,MathMax(m,win_h-h-m));
   if(mv.x>=0)
     {
      mv.x=px;
      mv.y=py;
     }
   int cw=(int)MathCeil(w+2.0*m),ch=(int)MathCeil(h+2.0*m);
   if(!cv.Attach(name+"."+IntegerToString(sub),sub,false) || !cv.Place(px-(int)m,py-(int)m,cw,ch))
      return(false);
   cv.Clear();
   ox=m;
   oy=m;
   mv.bx1=px;
   mv.by1=py;
   mv.bx2=px+w;
   mv.by2=py+h;
   mv.hy2=py+header_h;
   mv.cx1=px+w-26.0*k;
   mv.cx2=px+w-4.0*k;
   mv.cy1=py+4.0*k;
   mv.cy2=py+MathMin(header_h,30.0*k)-2.0*k;
   mv.gx1=px+w-16.0*k;
   mv.gy1=py+h-16.0*k;
   return(true);
  }

//--- chevron + grip decorations for a card drawn at (ox,oy) with size w x h
void XCardChrome(CXauCanvas &cv,const CXauMovable &mv,const XauTheme &t,const double ox,const double oy,
                 const double w,const double h,const double header_h)
  {
   double k=cv.K();
   double cx=ox+w-15.0*k;
   double cy=oy+MathMin(header_h,30.0*k)*0.5+1.0*k;
   if(mv.hover==2)
      cv.Circle(cx,cy,9.0*k,XRgb(t.border,0.9));
   XDrawChevron(cv,cx,cy,!mv.collapsed,XRgb(mv.hover==2 ? t.text : t.muted,1.0));
   if(!mv.collapsed)
      XDrawGrip(cv,ox+w-3.0*k,oy+h-3.0*k,XRgb(mv.hover==3 ? t.gold : t.muted,mv.hover==3 ? 1.0 : 0.7));
  }

#endif
//+------------------------------------------------------------------+
