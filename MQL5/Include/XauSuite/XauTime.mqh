//+------------------------------------------------------------------+
//|                                                     XauTime.mqh  |
//|          XAU Suite for MetaTrader 5 - trading day and sessions   |
//|                                                                  |
//| Bar times in MT5 are broker server time. The clock converts them |
//| to UTC (DST-aware), then derives the New York 17:00 trading day  |
//| and the Tokyo / London / New York sessions in their local time.  |
//+------------------------------------------------------------------+
#ifndef XAU_TIME_MQH
#define XAU_TIME_MQH

enum ENUM_XAU_DAY_ROLL
  {
   XAU_ROLL_NY17=0,   // New York 17:00 (metals / FX trading day)
   XAU_ROLL_UTC=1,    // UTC 00:00
   XAU_ROLL_SERVER=2  // Broker server midnight
  };

enum ENUM_XAU_DST
  {
   XAU_DST_US=0,   // Server follows US DST (most metal brokers)
   XAU_DST_EU=1,   // Server follows EU DST
   XAU_DST_NONE=2  // Server has no DST
  };

enum ENUM_XAU_ZONE
  {
   XAU_ZONE_TOKYO=0,
   XAU_ZONE_LONDON=1,
   XAU_ZONE_NEWYORK=2
  };

datetime XDate(const int y,const int mon,const int day)
  {
   MqlDateTime d;
   ZeroMemory(d);
   d.year=y;
   d.mon=mon;
   d.day=day;
   return(StructToTime(d));
  }

//--- n-th Sunday (1-based) of a month, 00:00
datetime XNthSunday(const int y,const int mon,const int n)
  {
   datetime t=XDate(y,mon,1);
   MqlDateTime d;
   TimeToStruct(t,d);
   int first=(7-d.day_of_week)%7; // days until the first Sunday
   return(t+(datetime)((first+7*(n-1))*86400));
  }

//--- last Sunday of a month, 00:00
datetime XLastSunday(const int y,const int mon)
  {
   int ny=(mon==12 ? y+1 : y);
   int nm=(mon==12 ? 1 : mon+1);
   datetime last=XDate(ny,nm,1)-86400;
   MqlDateTime d;
   TimeToStruct(last,d);
   return(last-(datetime)(d.day_of_week*86400));
  }

class CXauClock
  {
private:
   int               m_base;     // server minus UTC in seconds outside DST
   ENUM_XAU_DST      m_dst;
   datetime          m_y0;       // cached year [m_y0, m_y1)
   datetime          m_y1;
   datetime          m_us0;
   datetime          m_us1;
   datetime          m_eu0;
   datetime          m_eu1;

   void              Ensure(const datetime utc)
     {
      if(utc>=m_y0 && utc<m_y1)
         return;
      MqlDateTime d;
      TimeToStruct(utc,d);
      int y=d.year;
      m_y0=XDate(y,1,1);
      m_y1=XDate(y+1,1,1);
      m_us0=XNthSunday(y,3,2)+7*3600;  // 02:00 EST
      m_us1=XNthSunday(y,11,1)+6*3600; // 02:00 EDT
      m_eu0=XLastSunday(y,3)+3600;     // 01:00 UTC
      m_eu1=XLastSunday(y,10)+3600;
     }

public:
                     CXauClock(void) : m_base(0),m_dst(XAU_DST_US),m_y0(0),m_y1(0),
                     m_us0(0),m_us1(0),m_eu0(0),m_eu1(0) {}

   //--- gmt_hours >= 99 means: detect from the live server clock
   void              Init(const double gmt_hours,const ENUM_XAU_DST dst)
     {
      m_dst=dst;
      if(gmt_hours<99.0)
        {
         m_base=(int)MathRound(gmt_hours*3600.0);
         return;
        }
      long off=(long)(TimeTradeServer()-TimeGMT());
      off=(long)MathRound((double)off/1800.0)*1800;
      datetime now=TimeGMT();
      bool in_dst=(dst==XAU_DST_US && UsDst(now)) || (dst==XAU_DST_EU && EuDst(now));
      m_base=(int)off-(in_dst ? 3600 : 0);
     }

   bool              UsDst(const datetime utc)
     {
      Ensure(utc);
      return(utc>=m_us0 && utc<m_us1);
     }

   bool              EuDst(const datetime utc)
     {
      Ensure(utc);
      return(utc>=m_eu0 && utc<m_eu1);
     }

   datetime          ToUtc(const datetime srv)
     {
      datetime utc=srv-(datetime)m_base;
      if(m_dst==XAU_DST_US && UsDst(utc))
         utc-=3600;
      else
         if(m_dst==XAU_DST_EU && EuDst(utc))
            utc-=3600;
      return(utc);
     }

   //--- local wall-clock time of a zone
   datetime          ZoneTime(const datetime utc,const ENUM_XAU_ZONE zone)
     {
      if(zone==XAU_ZONE_TOKYO)
         return(utc+9*3600);
      if(zone==XAU_ZONE_LONDON)
         return(utc+(EuDst(utc) ? 3600 : 0));
      return(utc-5*3600+(UsDst(utc) ? 3600 : 0));
     }

   //--- integer id of the trading day a bar belongs to (days since 1970 of that day's date)
   long              DayKey(const datetime srv,const ENUM_XAU_DAY_ROLL roll)
     {
      if(roll==XAU_ROLL_SERVER)
         return((long)srv/86400);
      datetime utc=ToUtc(srv);
      if(roll==XAU_ROLL_UTC)
         return((long)utc/86400);
      // 17:00 New York + 7h = midnight, so Sunday's reopen already counts as Monday
      datetime ny=ZoneTime(utc,XAU_ZONE_NEWYORK);
      return(((long)ny+7*3600)/86400);
     }

   //--- 0 = Monday ... 6 = Sunday
   int               DayOfWeek(const long key)
     {
      return((int)((key%7+7+3)%7));
     }

   int               MonthOfKey(const long key)
     {
      MqlDateTime d;
      TimeToStruct((datetime)(key*86400+43200),d);
      return(d.mon);
     }

   //--- is the bar opening at server time srv inside [start_hour, end_hour) local time, Mon-Fri?
   bool              InSession(const datetime srv,const ENUM_XAU_ZONE zone,const int start_hour,const int end_hour)
     {
      datetime local=ZoneTime(ToUtc(srv),zone);
      long days=(long)local/86400;
      int dow=(int)((days+3)%7);
      if(dow>4)
         return(false);
      if(start_hour==end_hour)
         return(true);
      int minute=(int)(((long)local%86400)/60);
      int s=start_hour*60;
      int e=end_hour*60;
      if(s<e)
         return(minute>=s && minute<e);
      return(minute>=s || minute<e);
     }
  };

#endif
//+------------------------------------------------------------------+
