#property strict
#property version "1.01"
#property description "Manual price conditions, alerts only. No trading operations."

enum RuleType { CLOSE_BELOW, CLOSE_ABOVE, CROSS_BELOW, CROSS_ABOVE,
                SWEEP_BELOW_RECLAIM, SWEEP_ABOVE_REJECT, ZONE_TOUCH };
input RuleType Rule=CROSS_BELOW;
input ENUM_TIMEFRAMES RuleTimeframe=PERIOD_H4;
input double PriceLevel=0; // Required for individual level rules
input double ZoneLow=0;
input double ZoneHigh=0;
input bool PopupAlerts=true;
input bool PhoneNotifications=false;
input bool OneShot=true; // Rearm by removing and reattaching the EA

datetime lastRule=0;
bool fired=false;

void Signal(string reason,datetime bar_time,double close_price)
{
   string message=StringFormat("%s | %s | bar %s | close %s",
      _Symbol,reason,TimeToString(bar_time,TIME_DATE|TIME_MINUTES),
      DoubleToString(close_price,_Digits));
   Print(message);
   if(PopupAlerts) Alert(message);
   if(PhoneNotifications && !MQLInfoInteger(MQL_TESTER))
   {
      ResetLastError();
      if(!SendNotification(StringSubstr(message,0,255)))
         Print("Push failed; error ",GetLastError(),". Signal remains in Experts log.");
   }
   fired=true;
}

// CopyRates places the older candle at index 0 in this fixed array.
bool NewClosed(ENUM_TIMEFRAMES tf,datetime &last,MqlRates &previous,MqlRates &latest)
{
   MqlRates bars[2];
   if(CopyRates(_Symbol,tf,1,2,bars)!=2) return false;
   previous=bars[0]; latest=bars[1];
   if(last==0) { last=latest.time; return false; } // No historical alert on attach
   if(latest.time<=last) return false;
   last=latest.time;
   return true;
}

int OnInit()
{
   if(Rule==ZONE_TOUCH)
   {
      if(ZoneLow<=0 || ZoneHigh<=ZoneLow) return INIT_PARAMETERS_INCORRECT;
   }
   else if(PriceLevel<=0) return INIT_PARAMETERS_INCORRECT;
   Print("Alert-only monitor attached to ",_Symbol,". No orders will be sent.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(OneShot && fired) return;
   MqlRates previous,bar;
   if(!NewClosed(RuleTimeframe,lastRule,previous,bar)) return;
   bool hit=false;
   switch(Rule)
   {
      case CLOSE_BELOW: hit=bar.close<PriceLevel; break;
      case CLOSE_ABOVE: hit=bar.close>PriceLevel; break;
      case CROSS_BELOW: hit=previous.close>=PriceLevel && bar.close<PriceLevel; break;
      case CROSS_ABOVE: hit=previous.close<=PriceLevel && bar.close>PriceLevel; break;
      case SWEEP_BELOW_RECLAIM: hit=bar.low<PriceLevel && bar.close>PriceLevel; break;
      case SWEEP_ABOVE_REJECT: hit=bar.high>PriceLevel && bar.close<PriceLevel; break;
      case ZONE_TOUCH: hit=bar.low<=ZoneHigh && bar.high>=ZoneLow; break;
      default: break;
   }
   if(hit) Signal(EnumToString(Rule)+" "+EnumToString(RuleTimeframe),bar.time,bar.close);
}
