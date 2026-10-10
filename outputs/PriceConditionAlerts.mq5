#property strict
#property version "1.00"
#property description "Manual price conditions, alerts only. No trading operations."

enum RuleType { CLOSE_BELOW, CLOSE_ABOVE, CROSS_BELOW, CROSS_ABOVE,
                SWEEP_BELOW_RECLAIM, SWEEP_ABOVE_REJECT, ZONE_TOUCH,
                ZONE_SWEEP_SHIFT };
input RuleType Rule=CROSS_BELOW;
input ENUM_TIMEFRAMES RuleTimeframe=PERIOD_H4;
input double PriceLevel=0; // Required for individual level rules
input double ZoneLow=0;
input double ZoneHigh=0;
input bool BullishSequence=true;
input double LiquidityLevel=0;
input double ShiftLevel=0;
input int SequenceExpiryBars=6; // H1 bars after zone touch
input bool PopupAlerts=true;
input bool PhoneNotifications=false;
input bool OneShot=true; // Rearm by removing and reattaching the EA

datetime lastRule=0,lastH1=0,lastH4=0;
bool fired=false;
int stage=0,age=0;

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
   if(Rule==ZONE_TOUCH || Rule==ZONE_SWEEP_SHIFT)
   {
      if(ZoneLow<=0 || ZoneHigh<=ZoneLow) return INIT_PARAMETERS_INCORRECT;
   }
   else if(PriceLevel<=0) return INIT_PARAMETERS_INCORRECT;
   if(Rule==ZONE_SWEEP_SHIFT &&
      (LiquidityLevel<=0 || ShiftLevel<=0 || SequenceExpiryBars<2 ||
       (BullishSequence && ShiftLevel<=LiquidityLevel) ||
       (!BullishSequence && ShiftLevel>=LiquidityLevel)))
      return INIT_PARAMETERS_INCORRECT;
   Print("Alert-only monitor attached to ",_Symbol,". No orders will be sent.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(OneShot && fired) return;
   MqlRates previous,bar;
   if(Rule!=ZONE_SWEEP_SHIFT)
   {
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
      return;
   }

   // Cancellation takes precedence when H4 and H1 close together.
   if(NewClosed(PERIOD_H4,lastH4,previous,bar))
   {
      bool invalid=BullishSequence ? bar.close<ZoneLow : bar.close>ZoneHigh;
      if(invalid) { stage=0; age=0; }
   }
   if(!NewClosed(PERIOD_H1,lastH1,previous,bar)) return;
   // Also prevent rearming while the most recently closed H4 invalidates the zone.
   MqlRates context[1];
   if(CopyRates(_Symbol,PERIOD_H4,1,1,context)!=1) return;
   if(BullishSequence ? context[0].close<ZoneLow : context[0].close>ZoneHigh)
   { stage=0; age=0; return; }
   if(stage>0 && ++age>SequenceExpiryBars)
   { stage=0; age=0; Print("Sequence expired."); }
   if(stage==0)
   {
      if(bar.low<=ZoneHigh && bar.high>=ZoneLow)
      { stage=1; age=0; Print("Zone touched; waiting for a later H1 sweep."); }
      return;
   }
   if(stage==1)
   {
      bool swept=BullishSequence ? bar.low<LiquidityLevel && bar.close>LiquidityLevel
                                : bar.high>LiquidityLevel && bar.close<LiquidityLevel;
      if(swept) { stage=2; Print("Sweep confirmed; waiting for a later H1 shift."); }
      return;
   }
   bool shifted=BullishSequence ? previous.close<=ShiftLevel && bar.close>ShiftLevel
                               : previous.close>=ShiftLevel && bar.close<ShiftLevel;
   if(shifted)
   {
      Signal(BullishSequence ? "Bullish zone-sweep-shift" : "Bearish zone-sweep-shift",
             bar.time,bar.close);
      stage=0; age=0;
   }
}
