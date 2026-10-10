#property strict
#property version "1.02"
#property description "User-defined condition list. Alerts only; no order operations."
input string ConditionsFile="conditions.csv"; // In MQL5/Files
input bool PopupAlerts=true;
input bool PhoneNotifications=false;
input bool OneShot=true;
input int SequenceTimeoutMinutes=0; // 0 = no expiry
input int ResetAfterTickGapSeconds=300; // 0 = disabled
struct Condition
{
   string rule;
   bool live;
   ENUM_TIMEFRAMES timeframe;
   double level,low,high;
};
Condition conditions[];
int active=0;
bool finished=false,aboveSeen=false,belowSeen=false;
double previousBid=0;
datetime lastCandle=0,started=0,lastTick=0,lastPush=0;

string Clean(string value)
{
   StringTrimLeft(value); StringTrimRight(value);
   return value;
}
bool Number(string value,double &result)
{
   value=Clean(value);
   if(StringLen(value)==0) return false;
   bool digit=false,dot=false;
   for(int i=0;i<StringLen(value);i++)
   {
      ushort c=StringGetCharacter(value,i);
      if(c>='0' && c<='9') digit=true;
      else if(c=='.' && !dot) dot=true;
      else return false;
   }
   result=StringToDouble(value);
   return digit && MathIsValidNumber(result);
}
bool Timeframe(string value,ENUM_TIMEFRAMES &tf)
{
   if(value=="M1") tf=PERIOD_M1;
   else if(value=="M5") tf=PERIOD_M5;
   else if(value=="M15") tf=PERIOD_M15;
   else if(value=="M30") tf=PERIOD_M30;
   else if(value=="H1") tf=PERIOD_H1;
   else if(value=="H4") tf=PERIOD_H4;
   else if(value=="D1") tf=PERIOD_D1;
   else return false;
   return true;
}
bool ZoneRule(string rule)
{
   return rule=="ZONE_ENTER" || rule=="ZONE_TOUCH" || rule=="CLOSE_IN_ZONE";
}
bool KnownRule(string rule)
{
   return ZoneRule(rule) || rule=="TRADED_ABOVE" || rule=="TRADED_BELOW" ||
      rule=="SWEEP_ABOVE_REJECT" || rule=="SWEEP_BELOW_RECLAIM" ||
      rule=="CLOSE_ABOVE" || rule=="CLOSE_BELOW" ||
      rule=="CROSS_ABOVE" || rule=="CROSS_BELOW";
}
bool LoadConditions()
{
   ArrayResize(conditions,0);
   int handle=FileOpen(ConditionsFile,FILE_READ|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(handle==INVALID_HANDLE)
   { Print("Cannot open ",ConditionsFile," in MQL5/Files; error ",GetLastError()); return false; }
   int lineNumber=0;
   bool valid=true;
   while(!FileIsEnding(handle))
   {
      string line=Clean(FileReadString(handle)); lineNumber++;
      if(line=="" || StringFind(line,"#")==0) continue;
      if(line=="rule,mode,timeframe,level,zone_low,zone_high") continue;
      string cells[];
      if(StringSplit(line,',',cells)!=6) { valid=false; break; }
      for(int j=0;j<6;j++) cells[j]=Clean(cells[j]);
      Condition item;
      item.rule=cells[0]; item.live=cells[1]=="LIVE";
      if(!KnownRule(item.rule) || (cells[1]!="LIVE" && cells[1]!="CANDLE") ||
         !Timeframe(cells[2],item.timeframe) || !Number(cells[3],item.level) ||
         !Number(cells[4],item.low) || !Number(cells[5],item.high))
      { valid=false; break; }
      if(item.live && (item.rule=="CLOSE_IN_ZONE" || item.rule=="CLOSE_ABOVE" ||
         item.rule=="CLOSE_BELOW" || item.rule=="CROSS_ABOVE" || item.rule=="CROSS_BELOW"))
      { valid=false; break; }
      if(ZoneRule(item.rule) ? item.low<=0 || item.high<=item.low : item.level<=0)
      { valid=false; break; }
      int count=ArraySize(conditions);
      if(ArrayResize(conditions,count+1)!=count+1) { valid=false; break; }
      conditions[count]=item;
   }
   FileClose(handle);
   if(!valid) Print("Invalid condition file at line ",lineNumber,". Monitor will not start.");
   if(ArraySize(conditions)==0) { Print("At least one condition is required."); valid=false; }
   return valid;
}
void PrimeStep()
{
   aboveSeen=false; belowSeen=false;
   lastCandle=iTime(_Symbol,conditions[active].timeframe,1);
}
void ResetSequence(string reason)
{
   active=0; started=0; PrimeStep();
   Print(reason,"; waiting for condition 1.");
}
bool Matches(const Condition &item,const MqlRates &prior,const MqlRates &bar)
{
   if(item.live && item.rule=="SWEEP_ABOVE_REJECT")
   {
      if(bar.close>item.level) aboveSeen=true;
      return aboveSeen && bar.close<item.level;
   }
   if(item.live && item.rule=="SWEEP_BELOW_RECLAIM")
   {
      if(bar.close<item.level) belowSeen=true;
      return belowSeen && bar.close>item.level;
   }
   bool overlap=bar.low<=item.high && bar.high>=item.low;
   if(item.rule=="ZONE_TOUCH") return overlap;
   if(item.rule=="ZONE_ENTER")
      return overlap && !(prior.low<=item.high && prior.high>=item.low);
   if(item.rule=="CLOSE_IN_ZONE") return bar.close>=item.low && bar.close<=item.high;
   if(item.rule=="TRADED_ABOVE") return bar.high>item.level;
   if(item.rule=="TRADED_BELOW") return bar.low<item.level;
   if(item.rule=="SWEEP_ABOVE_REJECT") return bar.high>item.level && bar.close<item.level;
   if(item.rule=="SWEEP_BELOW_RECLAIM") return bar.low<item.level && bar.close>item.level;
   if(item.rule=="CLOSE_ABOVE") return bar.close>item.level;
   if(item.rule=="CLOSE_BELOW") return bar.close<item.level;
   if(item.rule=="CROSS_ABOVE") return prior.close<=item.level && bar.close>item.level;
   if(item.rule=="CROSS_BELOW") return prior.close>=item.level && bar.close<item.level;
   return false;
}
void Notify(double price)
{
   string message=StringFormat("%s: all %d conditions met at %s; Bid %s",
      _Symbol,ArraySize(conditions),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      DoubleToString(price,_Digits));
   Print(message);
   if(PopupAlerts) Alert(message);
   if(PhoneNotifications && !MQLInfoInteger(MQL_TESTER))
   {
      if(lastPush==0 || TimeCurrent()-lastPush>=6)
      {
         lastPush=TimeCurrent();
         if(!SendNotification(StringSubstr(message,0,255)))
            Print("Push failed: ",GetLastError());
      }
      else Print("Push rate limited; signal saved in Experts log.");
   }
}
int OnInit()
{
   if(SequenceTimeoutMinutes<0 || ResetAfterTickGapSeconds<0 || !LoadConditions())
      return INIT_PARAMETERS_INCORRECT;
   active=0; finished=false; started=0; previousBid=0; lastTick=0; lastPush=0;
   PrimeStep();
   Print("Loaded ",ArraySize(conditions)," custom conditions for ",_Symbol,". Alerts only.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { Comment(""); }
void OnTick()
{
   if(finished) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0) return;
   datetime now=TimeCurrent();
   if(lastTick!=0 && ResetAfterTickGapSeconds>0 && now-lastTick>ResetAfterTickGapSeconds)
   { ResetSequence("Tick gap detected"); previousBid=0; }
   lastTick=now;
   if(previousBid==0) { previousBid=tick.bid; return; }
   if(started!=0 && SequenceTimeoutMinutes>0 && now-started>SequenceTimeoutMinutes*60)
      ResetSequence("Sequence expired");
   Condition item=conditions[active];
   MqlRates prior,bar;
   if(item.live)
   {
      ZeroMemory(prior); ZeroMemory(bar);
      prior.open=prior.high=prior.low=prior.close=previousBid;
      bar.open=bar.high=bar.low=bar.close=tick.bid;
      bar.time=now;
   }
   else
   {
      MqlRates candles[2];
      if(CopyRates(_Symbol,item.timeframe,1,2,candles)!=2)
      { previousBid=tick.bid; return; }
      prior=candles[0]; bar=candles[1];
      if(lastCandle==0) { lastCandle=bar.time; previousBid=tick.bid; return; }
      if(bar.time<=lastCandle) { previousBid=tick.bid; return; }
      lastCandle=bar.time;
   }
   previousBid=tick.bid;
   Comment("Custom conditions: ",active+1," / ",ArraySize(conditions),
           "\nWaiting for ",item.rule," (",item.live ? "live Bid" : "candle close",
           ")\nAlerts only");
   if(!Matches(item,prior,bar)) return;
   if(active==0) started=now;
   Print("Condition ",active+1," passed: ",item.rule," at ",TimeToString(now,TIME_DATE|TIME_SECONDS));
   active++;
   if(active==ArraySize(conditions))
   {
      Notify(tick.bid);
      if(OneShot) { finished=true; Comment("All conditions met. Reattach to rearm."); return; }
      ResetSequence("Sequence completed");
   }
   else PrimeStep(); // Next condition starts after this update, with fresh sweep memory.
}
