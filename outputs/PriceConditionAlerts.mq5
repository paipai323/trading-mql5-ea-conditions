#property strict
#property version "1.26"
#property description "Ordered conditions with optional market/pending entry and 2% equity risk."
#include <Controls\Dialog.mqh>
#include <Controls\ComboBox.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\Label.mqh>
input string ConditionsFile="conditions.csv"; // Optional import, not required on startup
input bool PopupAlerts=true;
input bool PhoneNotifications=false;
input bool OneShot=true;
input bool ShowZonePreviews=true; // Draw draft zones; selected condition is orange
input bool ShowPriceLevelPreviews=true; // Draw horizontal lines for draft level rules
input int SequenceTimeoutMinutes=0; // 0 = no expiry
input int ResetAfterTickGapSeconds=300; // 0 = disabled
input ulong EntryMagic=20261010;
input uint EntryDeviationPoints=20; // Risk sizing includes this adverse price allowance
input int EntryMaxSpreadPoints=0; // 0 = no spread filter
bool autoEntry=false;
ENUM_ORDER_TYPE entrySide=ORDER_TYPE_BUY;
double entrySL=0,entryTP=0,entryPendingPrice=0;
string entryLock="";
bool entryManualLots=false;
double entryLots=0;
bool ValidManualLots(double lots)
{
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   return MathIsValidNumber(lots) && lots>=minimum && lots<=maximum && step>0 &&
          MathAbs(lots/step-MathRound(lots/step))<0.0000001;
}

double TradePrice(double price)
{
   double size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   return size>0 ? NormalizeDouble(MathRound(price/size)*size,_Digits) : 0;
}
bool BuyOrder(ENUM_ORDER_TYPE side) { return side==ORDER_TYPE_BUY || side==ORDER_TYPE_BUY_LIMIT || side==ORDER_TYPE_BUY_STOP; }
bool PendingOrder(ENUM_ORDER_TYPE side) { return side>=ORDER_TYPE_BUY_LIMIT && side<=ORDER_TYPE_SELL_STOP; }
bool ValidEntryPrices(ENUM_ORDER_TYPE side,double sl,double tp,MqlTick &quote,double pendingPrice=0)
{
   if(!MathIsValidNumber(sl) || !MathIsValidNumber(tp) || sl<=0 || tp<=0 || quote.bid<=0 || quote.ask<=0) return false;
   double distance=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(PendingOrder(side))
   {
      if(!MathIsValidNumber(pendingPrice) || pendingPrice<=0) return false;
      if(side==ORDER_TYPE_BUY_LIMIT && !(pendingPrice<quote.ask && quote.ask-pendingPrice>=distance)) return false;
      if(side==ORDER_TYPE_SELL_LIMIT && !(pendingPrice>quote.bid && pendingPrice-quote.bid>=distance)) return false;
      if(side==ORDER_TYPE_BUY_STOP && !(pendingPrice>quote.ask && pendingPrice-quote.ask>=distance)) return false;
      if(side==ORDER_TYPE_SELL_STOP && !(pendingPrice<quote.bid && quote.bid-pendingPrice>=distance)) return false;
      if(BuyOrder(side)) return sl<pendingPrice && tp>pendingPrice && pendingPrice-sl>=distance && tp-pendingPrice>=distance;
      return sl>pendingPrice && tp<pendingPrice && sl-pendingPrice>=distance && pendingPrice-tp>=distance;
   }
   if(side==ORDER_TYPE_BUY) return sl<quote.bid && quote.bid-sl>=distance && tp>quote.ask && tp-quote.bid>=distance;
   return sl>quote.ask && sl-quote.ask>=distance && tp<quote.bid && quote.ask-tp>=distance;
}
bool SymbolHasExposure()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) return true;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)!=0 && OrderGetString(ORDER_SYMBOL)==_Symbol) return true;
   return false;
}
double RiskVolume(double budget,double lossAtMin,double minimum,double step,double maximum)
{
   if(!MathIsValidNumber(budget) || !MathIsValidNumber(lossAtMin) || !MathIsValidNumber(minimum) ||
      !MathIsValidNumber(step) || !MathIsValidNumber(maximum)) return 0;
   if(budget<=0 || lossAtMin<=0 || minimum<=0 || step<=0 || maximum<minimum) return 0;
   double raw=MathMin(maximum,budget/lossAtMin*minimum);
   double volume=NormalizeDouble(MathFloor(raw/step)*step,8);
   // Never round a too-small order up to the broker minimum.
   if(volume<minimum || volume/minimum*lossAtMin>budget) return 0;
   return volume;
}
bool EstimateEntry(ENUM_ORDER_TYPE side,double sl,double tp,MqlTick &quote,
                   double &volume,double &loss,double &gain,double &budget,string &reason,double pendingPrice=0,
                   bool manual=false,double manualLots=0)
{
   volume=0; loss=0; gain=0; budget=AccountInfoDouble(ACCOUNT_EQUITY)*0.02;
   if(!ValidEntryPrices(side,sl,tp,quote,pendingPrice)) { reason="Check entry/SL/TP sides and broker stop distances."; return false; }
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   ENUM_ORDER_TYPE marketSide=BuyOrder(side) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entry=PendingOrder(side) ? pendingPrice : (BuyOrder(side) ? quote.ask : quote.bid);
   // Convert the unsigned input before applying a negative Sell direction.
   double allowance=(double)EntryDeviationPoints*_Point;
   double adverse=BuyOrder(side) ? entry+allowance : entry-allowance;
   double minLoss=0;
   if(!MathIsValidNumber(budget) || budget<=0)
   { reason="Cannot size trade: account equity is zero or unavailable."; return false; }
   if(!MathIsValidNumber(adverse) || adverse<=0 || !MathIsValidNumber(minimum) || minimum<=0)
   { reason="Cannot size trade: entry price or broker minimum lot unavailable."; return false; }
   ResetLastError();
   if(!OrderCalcProfit(marketSide,_Symbol,minimum,adverse,sl,minLoss))
   {
      int error=GetLastError();
      reason="MT5 stop-loss calculation failed: error "+IntegerToString(error)+" (see Experts).";
      static int priorError=-1; static datetime lastReport=0;
      if(error!=priorError || TimeLocal()-lastReport>=30)
      {
         Print(reason," symbol=",_Symbol," side=",EnumToString(marketSide)," min lots=",minimum,
               " entry=",adverse," SL=",sl," tick size=",SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),
               " contract size=",SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
               " account currency=",AccountInfoString(ACCOUNT_CURRENCY));
         priorError=error; lastReport=TimeLocal();
      }
      return false;
   }
   if(!MathIsValidNumber(minLoss) || minLoss>=0)
   { reason="MT5 returned no SL loss: "+DoubleToString(minLoss,8)+". Check symbol pricing/specifications."; return false; }
   if(manual && !ValidManualLots(manualLots)) { reason="Manual lots must meet broker min/max and lot step."; return false; }
   volume=manual ? manualLots : RiskVolume(budget,-minLoss,minimum,step,maximum);
   if(volume==0) { reason="Broker minimum lot cannot fit the 2% risk budget."; return false; }
   double pnl=0;
   if(!OrderCalcProfit(marketSide,_Symbol,volume,adverse,sl,pnl) || !MathIsValidNumber(pnl) || pnl>=0 || (!manual && -pnl>budget))
   { reason="Rounded volume exceeds risk budget or calculation unavailable."; return false; }
   loss=-pnl;
   if(!OrderCalcProfit(marketSide,_Symbol,volume,entry,tp,gain) || !MathIsValidNumber(gain) || gain<=0)
   { reason="Cannot calculate take-profit estimate."; return false; }
   return true;
}
void ExecuteEntry()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   { FormMessage="Entry skipped: connection or automated trading permission unavailable."; return; }
   double old=GlobalVariableGet(entryLock);
   if(old>TimeLocal() || !GlobalVariableSetOnCondition(entryLock,(double)TimeLocal()+60,old))
   { FormMessage="Entry skipped: another entry attempt on this symbol within 60 seconds."; return; }
   // Keep the lock for 60 seconds even if the broker response is uncertain; never retry automatically.
   if(SymbolHasExposure()) { FormMessage="Entry skipped: this symbol already has a position or pending order."; return; }
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol,quote) || !ValidEntryPrices(entrySide,entrySL,entryTP,quote,entryPendingPrice))
   { FormMessage="Entry skipped: entry/SL/TP invalid at current quote or too close."; return; }
   if(EntryMaxSpreadPoints>0 && (quote.ask-quote.bid)/_Point>EntryMaxSpreadPoints)
   { FormMessage="Entry skipped: spread exceeds the configured limit."; return; }
   bool pending=PendingOrder(entrySide);
   double entry=pending ? entryPendingPrice : (BuyOrder(entrySide) ? quote.ask : quote.bid);
   double volume=0,loss=0,gain=0,budget=0; string reason="";
   if(!EstimateEntry(entrySide,entrySL,entryTP,quote,volume,loss,gain,budget,reason,entryPendingPrice,entryManualLots,entryLots))
   { FormMessage="Entry skipped: "+reason; return; }
   if(loss>budget) Print("WARNING: manual lot risk exceeds 2%: modeled loss=",loss," budget=",budget);
   MqlTradeRequest request={}; MqlTradeCheckResult check={}; MqlTradeResult result={};
   request.action=pending ? TRADE_ACTION_PENDING : TRADE_ACTION_DEAL; request.symbol=_Symbol; request.magic=EntryMagic;
   request.type=entrySide; request.volume=volume; request.price=entry;
   request.sl=entrySL; request.tp=entryTP; request.deviation=EntryDeviationPoints;
   request.comment="PriceConditionAlerts";
   long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   ENUM_SYMBOL_TRADE_EXECUTION execution=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE);
   if(pending)
   {
      if((SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_GTC)==0)
      { FormMessage="Entry skipped: symbol does not support GTC pending orders."; return; }
      request.type_filling=ORDER_FILLING_RETURN; request.type_time=ORDER_TIME_GTC;
   }
   else if(execution==SYMBOL_TRADE_EXECUTION_INSTANT || execution==SYMBOL_TRADE_EXECUTION_REQUEST ||
      (filling & SYMBOL_FILLING_FOK)!=0) request.type_filling=ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
   else if(execution!=SYMBOL_TRADE_EXECUTION_MARKET) request.type_filling=ORDER_FILLING_RETURN;
   else { FormMessage="Entry skipped: no supported market-order filling policy."; return; }
   if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
   { FormMessage="Entry check failed: "+IntegerToString(check.retcode)+" "+check.comment; Print(FormMessage); return; }
   Print("Entry request: ",EnumToString(entrySide)," volume=",volume,
         " budget=",budget," modeled SL loss=",loss," TP gain=",gain," SL=",entrySL," TP=",entryTP);
   bool sent=OrderSend(request,result);
   if(sent && pending && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_PLACED))
      FormMessage="Pending order placed: "+EnumToString(entrySide)+" "+DoubleToString(volume,8)+" lots. Sequence stopped.";
   else if(sent && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL))
      FormMessage="Entry executed: "+EnumToString(entrySide)+" "+DoubleToString(result.volume,8)+" lots. Sequence stopped.";
   else if(sent && result.retcode==TRADE_RETCODE_PLACED)
      FormMessage="Entry accepted, awaiting broker execution. Check Trade tab; no retry.";
   else FormMessage="Entry response: "+IntegerToString(result.retcode)+" "+result.comment+". Check Trade tab; no retry.";
   Print(FormMessage," order=",result.order," deal=",result.deal," price=",result.price);
}
struct Condition
{
   string rule;
   bool live;
   ENUM_TIMEFRAMES timeframe;
   double level,low,high;
};
Condition conditions[];
struct DraftCondition
{
   string rule,level,low,high;
   bool live;
   ENUM_TIMEFRAMES timeframe;
};
DraftCondition draft[];
bool paused=true;
string savedFile="";
bool WriteDraftText(int handle,string value)
{
   int length=StringLen(value);
   return length<=4096 && FileWriteInteger(handle,length,INT_VALUE)==4 &&
          FileWriteString(handle,value,length)==(uint)(length*2);
}
bool ReadDraftText(int handle,string &value)
{
   if(FileTell(handle)+4>FileSize(handle)) return false;
   int length=FileReadInteger(handle,INT_VALUE);
   if(length<0 || length>4096 || FileTell(handle)+(ulong)length*2>FileSize(handle)) return false;
   value=length==0 ? "" : FileReadString(handle,length);
   return StringLen(value)==length;
}
string ruleCodes[]={"ZONE_ENTER","ZONE_TOUCH","TRADED_ABOVE","TRADED_BELOW",
   "SWEEP_ABOVE_REJECT","SWEEP_BELOW_RECLAIM","CLOSE_ABOVE","CLOSE_BELOW",
   "CROSS_ABOVE","CROSS_BELOW","CLOSE_IN_ZONE"};
string ruleNames[]={"Enters zone","Is in / touches zone","Trades above level","Trades below level",
   "Sweeps above, returns below","Sweeps below, returns above","Candle closes above",
   "Candle closes below","First candle close above","First candle close below","Candle closes in zone"};
ENUM_TIMEFRAMES tfValues[]={PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4,PERIOD_D1};
string tfNames[]={"M1","M5","M15","M30","H1","H4","D1"};
string FormMessage="Add your conditions, then Apply & Restart. Monitoring is paused.";
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
bool CandleOnly(string rule)
{
   return rule=="CLOSE_IN_ZONE" || rule=="CLOSE_ABOVE" || rule=="CLOSE_BELOW" ||
          rule=="CROSS_ABOVE" || rule=="CROSS_BELOW";
}
bool LoadConditions(string filename,Condition &target[])
{
   ArrayResize(target,0);
   int handle=FileOpen(filename,FILE_READ|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(handle==INVALID_HANDLE)
   { FormMessage="Cannot open "+filename+" in MQL5/Files."; Print(FormMessage," error ",GetLastError()); return false; }
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
      if(item.live && CandleOnly(item.rule))
      { valid=false; break; }
      if(ZoneRule(item.rule) ? item.low<=0 || item.high<=item.low : item.level<=0)
      { valid=false; break; }
      int count=ArraySize(target);
      if(ArrayResize(target,count+1)!=count+1) { valid=false; break; }
      target[count]=item;
   }
   FileClose(handle);
   if(!valid) { FormMessage="Invalid configuration at line "+IntegerToString(lineNumber)+"."; Print(FormMessage); }
   if(ArraySize(target)==0) { FormMessage="At least one condition is required."; valid=false; }
   return valid;
}
string TfCode(ENUM_TIMEFRAMES tf)
{
   for(int i=0;i<ArraySize(tfValues);i++) if(tfValues[i]==tf) return tfNames[i];
   return "H1";
}
void CopyToDraft(const Condition &source[])
{
   ArrayResize(draft,ArraySize(source));
   for(int i=0;i<ArraySize(source);i++)
   {
      draft[i].rule=source[i].rule; draft[i].live=source[i].live;
      draft[i].timeframe=source[i].timeframe;
      draft[i].level=DoubleToString(source[i].level,_Digits);
      draft[i].low=DoubleToString(source[i].low,_Digits);
      draft[i].high=DoubleToString(source[i].high,_Digits);
   }
}
bool ValidateDraft(Condition &result[])
{
   int count=ArraySize(draft);
   if(count==0) { FormMessage="Add at least one condition before applying."; return false; }
   if(ArrayResize(result,count)!=count) return false;
   for(int i=0;i<count;i++)
   {
      result[i].rule=draft[i].rule; result[i].live=draft[i].live;
      result[i].timeframe=draft[i].timeframe;
      result[i].level=0; result[i].low=0; result[i].high=0;
      string prefix="Condition "+IntegerToString(i+1)+": ";
      if(!KnownRule(result[i].rule) || (result[i].live && CandleOnly(result[i].rule)))
      { FormMessage=prefix+"choose a valid rule and evaluation mode."; return false; }
      if(ZoneRule(result[i].rule))
      {
         if(!Number(draft[i].low,result[i].low) || !Number(draft[i].high,result[i].high) ||
            result[i].low<=0 || result[i].high<=result[i].low)
         { FormMessage=prefix+"zone low must be positive; zone high must be larger."; return false; }
      }
      else if(!Number(draft[i].level,result[i].level) || result[i].level<=0)
      { FormMessage=prefix+"enter a positive price level."; return false; }
   }
   return true;
}
bool SaveConditions(const Condition &source[])
{
   string temporary=savedFile+".tmp";
   int handle=FileOpen(temporary,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(handle==INVALID_HANDLE) { FormMessage="Could not save settings. Monitoring was not changed."; return false; }
   string text="rule,mode,timeframe,level,zone_low,zone_high\r\n";
   for(int i=0;i<ArraySize(source);i++)
      text+=source[i].rule+","+(source[i].live ? "LIVE" : "CANDLE")+","+
         TfCode(source[i].timeframe)+","+DoubleToString(source[i].level,16)+","+
         DoubleToString(source[i].low,16)+","+DoubleToString(source[i].high,16)+"\r\n";
   uint written=FileWriteString(handle,text);
   FileFlush(handle); FileClose(handle);
   if(written!=(uint)StringLen(text) || !FileMove(temporary,0,savedFile,FILE_REWRITE))
   { FormMessage="Could not save settings. Monitoring was not changed."; return false; }
   return true;
}
void StartMonitoring()
{
   active=0; finished=false; started=0; previousBid=0; lastTick=0;
   PrimeStep(); paused=false;
   Print("Monitoring restarted with ",ArraySize(conditions)," conditions.");
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
   if(autoEntry) message=FormMessage+"\n"+message;
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
class CConditionPanel : public CAppDialog
{
private:
   CListView m_condition;
   CComboBox m_trade_side;
   CEdit m_trade_sl,m_trade_tp,m_trade_entry;
   CLabel m_trade_entry_label;
   CComboBox m_lot_mode;
   CEdit m_manual_lots;
   CLabel m_lot_mode_label,m_manual_lots_label;
   CLabel m_trade_side_label,m_trade_sl_label,m_trade_tp_label;
   CLabel m_trade_estimate,m_trade_budget;
   CButton m_trade_switch;
   bool m_trade_draft;
   CComboBox m_rule,m_mode,m_timeframe;
   CButton m_list_toggle;
   CButton m_zone_toggle,m_level_toggle,m_entry_toggle;
   bool m_show_zones,m_show_levels,m_show_entry;
   bool m_list_expanded;
   bool m_scroll_blocked,m_previous_scroll;
   bool OverDropdown(CComboBox &combo,int x,int y)
   {
      for(int i=0;i<combo.ControlsTotal();i++)
      {
         CListView *list=dynamic_cast<CListView *>(combo.Control(i));
         if(list!=NULL && list.IsVisible() && list.Contains(x,y)) return true;
      }
      return false;
   }
   CEdit m_level,m_low,m_high;
   CButton m_add,m_remove,m_up,m_down,m_apply,m_pause,m_import;
   CLabel m_select_label,m_rule_label,m_mode_label,m_tf_label;
   CLabel m_level_label,m_low_label,m_high_label,m_help,m_status,m_message;
   int m_selected;
   bool m_ready;
   bool m_picking;
   int m_pick_field;
   void UpdateVisibilityButtons()
   {
      m_zone_toggle.Text(m_show_zones ? "Hide zones" : "Show zones");
      m_level_toggle.Text(m_show_levels ? "Hide levels" : "Show levels");
      m_entry_toggle.Text(m_show_entry ? "Hide entry/SL/TP" : "Show entry/SL/TP");
   }
   void OnEntryToggle()
   {
      CancelPick(); m_show_entry=!m_show_entry;
      if(!m_show_entry) ObjectsDeleteAll(m_chart_id,m_name+"_DraftEntry_",0,-1);
      UpdateVisibilityButtons(); RefreshTradePreview(); ChartRedraw();
   }
   void OnZoneToggle()
   {
      CancelPick(); m_show_zones=!m_show_zones;
      if(!m_show_zones) ObjectsDeleteAll(m_chart_id,m_name+"_DraftZone_",0,-1);
      UpdateVisibilityButtons(); DrawZonePreviews(); ChartRedraw();
   }
   void OnLevelToggle()
   {
      CancelPick(); m_show_levels=!m_show_levels;
      if(!m_show_levels) ObjectsDeleteAll(m_chart_id,m_name+"_DraftLevel_",0,-1);
      UpdateVisibilityButtons(); DrawLevelPreviews(); ChartRedraw();
   }
   void ShiftEditor(int dy)
   {
      m_add.Shift(0,dy); m_remove.Shift(0,dy); m_up.Shift(0,dy); m_down.Shift(0,dy);
      m_import.Shift(0,dy); m_rule_label.Shift(0,dy); m_rule.Shift(0,dy);
      m_mode_label.Shift(0,dy); m_tf_label.Shift(0,dy); m_mode.Shift(0,dy); m_timeframe.Shift(0,dy);
      m_level_label.Shift(0,dy); m_low_label.Shift(0,dy); m_high_label.Shift(0,dy);
      m_level.Shift(0,dy); m_low.Shift(0,dy); m_high.Shift(0,dy); m_help.Shift(0,dy);
      m_apply.Shift(0,dy); m_pause.Shift(0,dy); m_status.Shift(0,dy); m_message.Shift(0,dy);
      m_trade_side.Shift(0,dy); m_trade_sl.Shift(0,dy); m_trade_tp.Shift(0,dy); m_trade_switch.Shift(0,dy);
      m_trade_side_label.Shift(0,dy); m_trade_sl_label.Shift(0,dy); m_trade_tp_label.Shift(0,dy);
      m_trade_estimate.Shift(0,dy); m_trade_budget.Shift(0,dy);
      m_trade_entry.Shift(0,dy); m_trade_entry_label.Shift(0,dy);
      m_lot_mode.Shift(0,dy); m_manual_lots.Shift(0,dy);
      m_lot_mode_label.Shift(0,dy); m_manual_lots_label.Shift(0,dy);
   }
   void OnListToggle()
   {
      CancelPick(); m_list_expanded=!m_list_expanded;
      int dy=m_list_expanded ? 110 : -110;
      // Resize the dialog and its normal rectangle, including after minimizing.
      if(m_list_expanded) Height(Height()+dy);
      ShiftEditor(dy);
      if(!m_list_expanded) Height(Height()+dy);
      m_norm_rect.Height(Height());
      if(m_list_expanded) m_condition.Show(); else m_condition.Hide();
      m_list_toggle.Text((m_list_expanded ? "- Hide conditions (" : "+ Show conditions (")+
                         IntegerToString(ArraySize(draft))+")");
      ChartRedraw();
   }
   bool ScrollList(CListView &list,int x,int y,int delta)
   {
      if(!list.IsVisible() || !list.Contains(x,y)) return false;
      for(int j=0;j<list.ControlsTotal();j++)
      {
         CScrollV *scroll=dynamic_cast<CScrollV *>(list.Control(j));
         if(scroll==NULL || !scroll.IsVisible()) continue;
         int steps=MathMax(1,MathAbs(delta)/120),direction=delta>0 ? -1 : 1;
         for(int k=0;k<steps;k++)
         {
            if(!scroll.CurrPos(scroll.CurrPos()+direction)) continue;
            long scrollId=scroll.Id(); double unused=0.0; string scrollName=scroll.Name();
            list.OnEvent(CHARTEVENT_CUSTOM+(direction>0 ? ON_SCROLL_INC : ON_SCROLL_DEC),
                         scrollId,unused,scrollName);
         }
         break;
      }
      ChartRedraw(); return true;
   }
   bool ScrollDropdown(CComboBox &combo,int x,int y,int delta)
   {
      for(int i=0;i<combo.ControlsTotal();i++)
      {
         CListView *list=dynamic_cast<CListView *>(combo.Control(i));
         if(list==NULL || !list.IsVisible() || !list.Contains(x,y)) continue;
         for(int j=0;j<list.ControlsTotal();j++)
         {
            CScrollV *scroll=dynamic_cast<CScrollV *>(list.Control(j));
            if(scroll==NULL || !scroll.IsVisible()) continue;
            int steps=MathMax(1,MathAbs(delta)/120);
            int direction=delta>0 ? -1 : 1;
            for(int k=0;k<steps;k++)
            {
               if(scroll.CurrPos(scroll.CurrPos()+direction))
               {
                  long scrollId=scroll.Id(); double unused=0.0; string scrollName=scroll.Name();
                  list.OnEvent(CHARTEVENT_CUSTOM+(direction>0 ? ON_SCROLL_INC : ON_SCROLL_DEC),
                               scrollId,unused,scrollName);
               }
            }
            break;
         }
         ChartRedraw(); return true;
      }
      return false;
   }
   void CancelPick()
   { m_picking=false; }
   bool Combo(CComboBox &control,string suffix,int x,int y,int width)
   { return control.Create(m_chart_id,m_name+suffix,m_subwin,x,y,x+width,y+24) && Add(control); }
   bool Edit(CEdit &control,string suffix,int x,int y,int width)
   { return control.Create(m_chart_id,m_name+suffix,m_subwin,x,y,x+width,y+24) && Add(control); }
   bool Button(CButton &control,string suffix,string text,int x,int y,int width)
   {
      return control.Create(m_chart_id,m_name+suffix,m_subwin,x,y,x+width,y+26) &&
             control.Text(text) && Add(control);
   }
   bool Label(CLabel &control,string suffix,string text,int x,int y,int width)
   {
      return control.Create(m_chart_id,m_name+suffix,m_subwin,x,y,x+width,y+20) &&
             control.Text(text) && Add(control);
   }
   void Dirty()
   { FormMessage="Draft edits only. Apply & Restart resets monitoring to condition 1."; UpdateStatus(); }
   void Capture()
   {
      if(m_selected<0 || m_selected>=ArraySize(draft)) return;
      int r=(int)m_rule.Value();
      if(r>=0 && r<ArraySize(ruleCodes)) draft[m_selected].rule=ruleCodes[r];
      draft[m_selected].live=m_mode.Value()==0;
      if(CandleOnly(draft[m_selected].rule)) draft[m_selected].live=false;
      int tf=(int)m_timeframe.Value();
      if(tf>=0 && tf<ArraySize(tfValues)) draft[m_selected].timeframe=tfValues[tf];
      draft[m_selected].level=Clean(m_level.Text());
      draft[m_selected].low=Clean(m_low.Text());
      draft[m_selected].high=Clean(m_high.Text());
   }
   void StyleInput(CEdit &control,bool used)
   {
      control.ColorBackground(used ? CONTROLS_EDIT_COLOR_BG : clrGainsboro);
      control.Color(used ? CONTROLS_EDIT_COLOR : clrGray);
      control.ColorBorder(used ? CONTROLS_EDIT_COLOR_BORDER : clrSilver);
   }
   void StyleCombo(CComboBox &control,bool used)
   {
      for(int i=0;i<control.ControlsTotal();i++)
      {
         CEdit *edit=dynamic_cast<CEdit *>(control.Control(i));
         if(edit!=NULL) StyleInput(edit,used);
      }
   }
   void StyleUnusedInputs()
   {
      bool available=m_selected>=0 && m_selected<ArraySize(draft);
      bool zone=false,live=false,candleOnly=false;
      if(available)
      { zone=ZoneRule(draft[m_selected].rule); live=draft[m_selected].live; candleOnly=CandleOnly(draft[m_selected].rule); }
      StyleInput(m_level,available && !zone); StyleInput(m_low,available && zone); StyleInput(m_high,available && zone);
      m_level_label.Color(available && !zone ? CONTROLS_EDIT_COLOR : clrGray);
      m_low_label.Color(available && zone ? CONTROLS_EDIT_COLOR : clrGray);
      m_high_label.Color(available && zone ? CONTROLS_EDIT_COLOR : clrGray);
      StyleCombo(m_rule,available); StyleCombo(m_mode,available && !candleOnly); StyleCombo(m_timeframe,available && !live);
      m_rule_label.Color(available ? CONTROLS_EDIT_COLOR : clrGray);
      m_mode_label.Color(available && !candleOnly ? CONTROLS_EDIT_COLOR : clrGray);
      m_tf_label.Color(available && !live ? CONTROLS_EDIT_COLOR : clrGray);
      bool pending=PendingOrder((ENUM_ORDER_TYPE)m_trade_side.Value()),manual=m_lot_mode.Value()==1;
      StyleInput(m_trade_entry,pending); StyleInput(m_manual_lots,manual);
      m_trade_entry_label.Color(pending ? CONTROLS_EDIT_COLOR : clrGray);
      m_manual_lots_label.Color(manual ? CONTROLS_EDIT_COLOR : clrGray);
   }
   void Fields()
   {
      bool available=m_selected>=0 && m_selected<ArraySize(draft);
      if(!available)
      {
         m_rule.Disable(); m_mode.Disable(); m_timeframe.Disable();
         m_level.Disable(); m_low.Disable(); m_high.Disable();
         m_remove.Disable(); m_up.Disable(); m_down.Disable(); CancelPick();
         m_level.Text(""); m_low.Text(""); m_high.Text("");
         m_help.Text("Click Add condition to begin."); StyleUnusedInputs(); return;
      }
      m_rule.Enable(); m_remove.Enable();
      for(int i=0;i<ArraySize(ruleCodes);i++)
         if(ruleCodes[i]==draft[m_selected].rule) { m_rule.SelectByValue(i); break; }
      if(CandleOnly(draft[m_selected].rule)) draft[m_selected].live=false;
      m_mode.SelectByValue(draft[m_selected].live ? 0 : 1);
      for(int i=0;i<ArraySize(tfValues);i++)
         if(tfValues[i]==draft[m_selected].timeframe) { m_timeframe.SelectByValue(i); break; }
      m_level.Text(draft[m_selected].level); m_low.Text(draft[m_selected].low);
      m_high.Text(draft[m_selected].high);
      if(CandleOnly(draft[m_selected].rule)) m_mode.Disable(); else m_mode.Enable();
      if(draft[m_selected].live) m_timeframe.Disable(); else m_timeframe.Enable();
      bool zone=ZoneRule(draft[m_selected].rule);
      if(zone)
      {
         if(m_pick_field==0) m_pick_field=1;
      }
      else if(m_pick_field<=2) m_pick_field=0;
      if(zone) { m_level.Disable(); m_low.Enable(); m_high.Enable(); }
      else { m_level.Enable(); m_low.Disable(); m_high.Disable(); }
      if(m_selected>0) m_up.Enable(); else m_up.Disable();
      if(m_selected<ArraySize(draft)-1) m_down.Enable(); else m_down.Disable();
      m_help.Text(draft[m_selected].live ? "Live Bid; no candle-close wait." : "Checks newly completed candles on the selected timeframe.");
      StyleUnusedInputs();
   }
   void RefreshList()
   {
      m_condition.ItemsClear();
      int count=ArraySize(draft);
      if(count==0)
      {
         m_selected=-1;
         m_condition.AddItem("No conditions - click Add",-1); m_condition.Select(0);
         m_condition.Disable();
      }
      else
      {
         m_condition.Enable();
         m_selected=MathMax(0,MathMin(m_selected,count-1));
         for(int i=0;i<count;i++)
         {
            string name=draft[i].rule;
            for(int r=0;r<ArraySize(ruleCodes);r++) if(ruleCodes[r]==name) { name=ruleNames[r]; break; }
            m_condition.AddItem(IntegerToString(i+1)+". "+name,i);
         }
         m_condition.SelectByValue(m_selected);
      }
      if(!m_list_expanded) m_condition.Hide();
      m_list_toggle.Text((m_list_expanded ? "- Hide conditions (" : "+ Show conditions (")+
                         IntegerToString(count)+")");
      Fields(); UpdateStatus(); ChartRedraw();
   }
   void OnSelect()
   {
      int selection=(int)m_condition.Value();
      if(selection==m_selected || selection<0 || selection>=ArraySize(draft)) return;
      CancelPick(); Capture(); m_selected=selection; Fields(); DrawZonePreviews(); ChartRedraw();
   }
   void OnRule()
   {
      if(m_selected<0) return;
      int r=(int)m_rule.Value();
      if(r<0 || r>=ArraySize(ruleCodes) || draft[m_selected].rule==ruleCodes[r]) return;
      CancelPick(); Capture(); Dirty(); RefreshList();
   }
   void OnMode()
   {
      if(m_selected<0 || draft[m_selected].live==(m_mode.Value()==0)) return;
      Capture(); Fields(); Dirty();
   }
   void OnTimeframe()
   {
      if(m_selected<0) return;
      int tf=(int)m_timeframe.Value();
      if(tf<0 || tf>=ArraySize(tfValues) || draft[m_selected].timeframe==tfValues[tf]) return;
      Capture(); Dirty();
   }
   void OnEdit()
   {
      if(m_selected<0) return;
      if(draft[m_selected].level==Clean(m_level.Text()) && draft[m_selected].low==Clean(m_low.Text()) &&
         draft[m_selected].high==Clean(m_high.Text())) return;
      Capture(); Dirty();
   }
   void OnAdd()
   {
      CancelPick(); Capture(); int count=ArraySize(draft);
      if(ArrayResize(draft,count+1)!=count+1) { FormMessage="Not enough memory to add a condition."; UpdateStatus(); return; }
      draft[count].rule="ZONE_ENTER"; draft[count].live=true; draft[count].timeframe=PERIOD_H1;
      draft[count].level=""; draft[count].low=""; draft[count].high="";
      m_selected=count; Dirty(); RefreshList();
   }
   void OnRemove()
   {
      if(m_selected<0) return;
      CancelPick();
      int count=ArraySize(draft);
      for(int i=m_selected;i<count-1;i++) draft[i]=draft[i+1];
      ArrayResize(draft,count-1);
      m_selected=MathMin(m_selected,count-2); Dirty(); RefreshList();
   }
   void Move(int direction)
   {
      int target=m_selected+direction;
      if(m_selected<0 || target<0 || target>=ArraySize(draft)) return;
      CancelPick(); Capture(); DraftCondition temp=draft[m_selected];
      draft[m_selected]=draft[target]; draft[target]=temp; m_selected=target;
      Dirty(); RefreshList();
   }
   void OnUp() { Move(-1); }
   void OnDown() { Move(1); }
   void OnApply()
   {
      CancelPick(); Capture(); Condition candidate[];
      double sl=0,tp=0,pendingPrice=0;
      bool manual=m_lot_mode.Value()==1; double lots=0;
      ENUM_ORDER_TYPE side=(ENUM_ORDER_TYPE)m_trade_side.Value();
      if(m_trade_draft)
      {
         if(manual && (!Number(m_manual_lots.Text(),lots) || !ValidManualLots(lots)))
         { FormMessage="Cannot apply: manual lots must meet broker min/max and step."; UpdateStatus(); return; }
         MqlTick quote;
         if(PendingOrder(side) && !Number(m_trade_entry.Text(),pendingPrice))
         { FormMessage="Enter a pending entry price before applying."; UpdateStatus(); return; }
         pendingPrice=TradePrice(pendingPrice);
         if(!Number(m_trade_sl.Text(),sl) || !Number(m_trade_tp.Text(),tp) ||
            !SymbolInfoTick(_Symbol,quote) || !ValidEntryPrices(side,TradePrice(sl),TradePrice(tp),quote,pendingPrice))
         { FormMessage="Cannot apply auto entry: enter valid SL/TP on the correct sides of market."; UpdateStatus(); return; }
         sl=TradePrice(sl); tp=TradePrice(tp);
      }
      if(!ValidateDraft(candidate) || !SaveConditions(candidate)) { UpdateStatus(); return; }
      if(ArrayResize(conditions,ArraySize(candidate))!=ArraySize(candidate))
      { FormMessage="Not enough memory to start monitoring."; UpdateStatus(); return; }
      for(int i=0;i<ArraySize(candidate);i++) conditions[i]=candidate[i];
      autoEntry=m_trade_draft; entrySide=side; entrySL=sl; entryTP=tp; entryPendingPrice=pendingPrice;
      entryManualLots=manual; entryLots=lots;
      if(autoEntry && PendingOrder(side)) m_trade_entry.Text(DoubleToString(pendingPrice,_Digits));
      if(autoEntry) { m_trade_sl.Text(DoubleToString(sl,_Digits)); m_trade_tp.Text(DoubleToString(tp,_Digits)); }
      StartMonitoring(); FormMessage="Applied and saved. Monitoring restarted at condition 1.";
      UpdateStatus();
   }
   void OnTradeSwitch()
   {
      CancelPick(); m_trade_draft=!m_trade_draft;
      if(!m_trade_draft) autoEntry=false; // OFF takes effect immediately, including during monitoring.
      m_trade_switch.Text(m_trade_draft ? "Auto entry ON (Apply to arm)" : "Auto entry OFF - alerts only");
      FormMessage=m_trade_draft ? "Order type and prices apply to the full sequence. Apply arms real/demo orders." :
                                 "Automatic entry disabled immediately. Alerts remain available.";
      UpdateStatus();
   }
   void OnTradeEdit()
   {
      CancelPick();
      if(PendingOrder((ENUM_ORDER_TYPE)m_trade_side.Value())) m_trade_entry.Enable(); else m_trade_entry.Disable();
      if(m_lot_mode.Value()==1) m_manual_lots.Enable(); else m_manual_lots.Disable();
      StyleUnusedInputs();
      Dirty();
   }
   void OnPause()
   {
      CancelPick();
      if(!paused && !finished)
      { paused=true; FormMessage="Paused. Resume restarts at condition 1; missed prices are not replayed."; }
      else if(ArraySize(conditions)>0)
      { StartMonitoring(); FormMessage="Monitoring restarted with the applied list. Draft edits are not applied."; }
      else FormMessage="Apply a valid condition list before starting.";
      UpdateStatus();
   }
   void OnImport()
   {
      CancelPick();
      Condition imported[];
      if(!LoadConditions(ConditionsFile,imported)) { UpdateStatus(); return; }
      CopyToDraft(imported); m_selected=0;
      FormMessage="Imported into draft. Review, then Apply & Restart."; RefreshList();
   }
   void BeginPick(int field)
   {
      if(field<0 || field>5) return;
      if(field==5 && !PendingOrder((ENUM_ORDER_TYPE)m_trade_side.Value())) return;
      if(field<=2 && (m_selected<0 || m_selected>=ArraySize(draft))) return;
      Capture();
      if(field<=2)
      {
         bool zone=ZoneRule(draft[m_selected].rule);
         if(zone ? field==0 : field!=0) return;
      }
      m_pick_field=field; m_picking=true;
      string targets[]={"price level","zone low","zone high","stop-loss price","take-profit price","pending entry price"};
      string target=targets[field];
      FormMessage="Click the main chart to set "+target+". Esc cancels.";
      UpdateStatus();
   }
protected:
   virtual void OnClickButtonClose(void) { Minimize(); }
   virtual void OnClickButtonMinMax(void)
   { if(m_minimized) Maximize(); else Minimize(); SubwinOff(); }
public:
   CConditionPanel() { m_selected=-1; m_ready=false; m_picking=false; m_pick_field=0; m_scroll_blocked=false; m_previous_scroll=true; m_trade_draft=false; }
   void SaveDraftState()
   {
      if(!m_ready || savedFile=="") return;
      Capture();
      string filename=savedFile+".draft",temporary=filename+".tmp";
      int handle=FileOpen(temporary,FILE_WRITE|FILE_BIN|FILE_UNICODE);
      if(handle==INVALID_HANDLE) { Print("Cannot save draft: ",GetLastError()); return; }
      bool ok=FileWriteInteger(handle,3)==4 && FileWriteInteger(handle,ArraySize(draft))==4 &&
              FileWriteInteger(handle,m_selected)==4 && FileWriteInteger(handle,(int)m_trade_side.Value())==4 &&
              FileWriteInteger(handle,(int)m_lot_mode.Value())==4 &&
              FileWriteInteger(handle,m_show_zones ? 1 : 0)==4 && FileWriteInteger(handle,m_show_levels ? 1 : 0)==4 &&
              FileWriteInteger(handle,m_show_entry ? 1 : 0)==4;
      ok=ok && WriteDraftText(handle,m_trade_sl.Text()) && WriteDraftText(handle,m_trade_tp.Text()) &&
               WriteDraftText(handle,m_trade_entry.Text()) && WriteDraftText(handle,m_manual_lots.Text());
      for(int i=0;ok && i<ArraySize(draft);i++)
         ok=WriteDraftText(handle,draft[i].rule) && FileWriteInteger(handle,draft[i].live ? 1 : 0)==4 &&
            FileWriteInteger(handle,(int)draft[i].timeframe)==4 && WriteDraftText(handle,draft[i].level) &&
            WriteDraftText(handle,draft[i].low) && WriteDraftText(handle,draft[i].high);
      FileFlush(handle); FileClose(handle);
      if(!ok || !FileMove(temporary,0,filename,FILE_REWRITE)) Print("Could not finish saving draft: ",GetLastError());
   }
   void RestoreDraftState()
   {
      string filename=savedFile+".draft";
      if(!FileIsExist(filename)) return;
      int handle=FileOpen(filename,FILE_READ|FILE_BIN|FILE_UNICODE);
      if(handle==INVALID_HANDLE) { Print("Cannot restore draft: ",GetLastError()); return; }
      bool ok=FileSize(handle)>=20 && FileSize(handle)<=16777216;
      int version=FileReadInteger(handle),count=FileReadInteger(handle),selected=FileReadInteger(handle);
      int side=FileReadInteger(handle),lotMode=FileReadInteger(handle);
      ok=ok && (version>=1 && version<=3) && count>=0 && count<=100000 && side>=0 && side<=5 && (lotMode==0 || lotMode==1);
      int showZones=ShowZonePreviews ? 1 : 0,showLevels=ShowPriceLevelPreviews ? 1 : 0;
      int showEntry=1;
      if(ok && version>=2)
      {
         ok=FileTell(handle)+8<=FileSize(handle);
         if(ok) { showZones=FileReadInteger(handle); showLevels=FileReadInteger(handle); }
         ok=ok && (showZones==0 || showZones==1) && (showLevels==0 || showLevels==1);
      }
      if(ok && version>=3)
      {
         ok=FileTell(handle)+4<=FileSize(handle);
         if(ok) showEntry=FileReadInteger(handle);
         ok=ok && (showEntry==0 || showEntry==1);
      }
      string sl="",tp="",entry="",lots="";
      ok=ok && ReadDraftText(handle,sl) && ReadDraftText(handle,tp) && ReadDraftText(handle,entry) && ReadDraftText(handle,lots);
      DraftCondition restored[];
      if(ok) ok=ArrayResize(restored,count)==count;
      for(int i=0;ok && i<count;i++)
      {
         ok=ReadDraftText(handle,restored[i].rule) && FileTell(handle)+8<=FileSize(handle);
         if(!ok) break;
         int live=FileReadInteger(handle),tf=FileReadInteger(handle);
         bool knownTF=false;
         for(int t=0;t<ArraySize(tfValues);t++) if((int)tfValues[t]==tf) knownTF=true;
         restored[i].live=live==1; restored[i].timeframe=(ENUM_TIMEFRAMES)tf;
         ok=KnownRule(restored[i].rule) && (live==0 || live==1) && knownTF &&
            ReadDraftText(handle,restored[i].level) && ReadDraftText(handle,restored[i].low) && ReadDraftText(handle,restored[i].high);
      }
      ok=ok && FileTell(handle)==FileSize(handle); FileClose(handle);
      if(!ok) { Print("Invalid draft snapshot; keeping applied settings."); return; }
      if(ArrayResize(draft,count)!=count) { Print("Not enough memory to restore draft."); return; }
      for(int i=0;i<count;i++) draft[i]=restored[i];
      m_show_zones=showZones==1; m_show_levels=showLevels==1;
      m_show_entry=showEntry==1;
      if(!m_show_entry) ObjectsDeleteAll(m_chart_id,m_name+"_DraftEntry_",0,-1);
      if(!m_show_zones) ObjectsDeleteAll(m_chart_id,m_name+"_DraftZone_",0,-1);
      if(!m_show_levels) ObjectsDeleteAll(m_chart_id,m_name+"_DraftLevel_",0,-1);
      UpdateVisibilityButtons();
      m_selected=selected; m_trade_side.SelectByValue(side); m_lot_mode.SelectByValue(lotMode);
      m_trade_sl.Text(sl); m_trade_tp.Text(tp); m_trade_entry.Text(entry); m_manual_lots.Text(lots);
      if(PendingOrder((ENUM_ORDER_TYPE)side)) m_trade_entry.Enable(); else m_trade_entry.Disable();
      if(lotMode==1) m_manual_lots.Enable(); else m_manual_lots.Disable();
      m_trade_draft=false; autoEntry=false;
      FormMessage="Draft restored. Review then Apply & Restart. Auto entry OFF.";
      RefreshList();
   }
   void HandleChartResize()
   {
      SubwinOff();
      if(!m_ready || m_minimized) return;
      int chartHeight=(int)ChartGetInteger(m_chart_id,CHART_HEIGHT_IN_PIXELS,0);
      int chartWidth=(int)ChartGetInteger(m_chart_id,CHART_WIDTH_IN_PIXELS);
      if(chartHeight<=0 || chartWidth<=0) return;
      int x=MathMax(0,MathMin(Left(),MathMax(0,chartWidth-Width())));
      int y=MathMax(0,MathMin(Top(),MathMax(0,chartHeight-Height())));
      if(x!=Left() || y!=Top()) CAppDialog::Move(x,y);
      m_norm_rect.SetBound(m_rect);
   }
   bool HandleFieldLabelClick(int x,int y)
   {
      if(!m_ready || m_minimized) return false;
      // An open dropdown can cover a label; its rows must keep their normal click behavior.
      if(OverDropdown(m_rule,x,y) || OverDropdown(m_mode,x,y) ||
         OverDropdown(m_timeframe,x,y) || OverDropdown(m_trade_side,x,y) || OverDropdown(m_lot_mode,x,y)) return false;
      int field=-1;
      if(m_level_label.IsVisible() && m_level_label.Contains(x,y)) field=0;
      else if(m_low_label.IsVisible() && m_low_label.Contains(x,y)) field=1;
      else if(m_high_label.IsVisible() && m_high_label.Contains(x,y)) field=2;
      else if(m_trade_sl_label.IsVisible() && m_trade_sl_label.Contains(x,y)) field=3;
      else if(m_trade_tp_label.IsVisible() && m_trade_tp_label.Contains(x,y)) field=4;
      else if(m_trade_entry_label.IsVisible() && m_trade_entry_label.Contains(x,y)) field=5;
      if(field<0) return false;
      BeginPick(field); return true;
   }
   void RestoreChartScroll()
   {
      if(!m_scroll_blocked) return;
      ChartSetInteger(m_chart_id,CHART_MOUSE_SCROLL,m_previous_scroll);
      m_scroll_blocked=false;
   }
   void HandlePointer(int x,int y)
   {
      bool over=Contains(x,y) || OverDropdown(m_rule,x,y) || OverDropdown(m_mode,x,y) ||
                OverDropdown(m_timeframe,x,y) || OverDropdown(m_trade_side,x,y) || OverDropdown(m_lot_mode,x,y);
      if(over)
      {
         if(!m_scroll_blocked)
         {
            m_previous_scroll=(bool)ChartGetInteger(m_chart_id,CHART_MOUSE_SCROLL);
            m_scroll_blocked=true;
         }
         // The native dialog can re-enable chart scrolling after a drag ends.
         if(ChartGetInteger(m_chart_id,CHART_MOUSE_SCROLL))
         { ChartSetInteger(m_chart_id,CHART_MOUSE_SCROLL,false); ChartRedraw(m_chart_id); }
      }
      else RestoreChartScroll();
   }
   void ClearZonePreviews()
   {
      if(m_name!="") ObjectsDeleteAll(m_chart_id,m_name+"_DraftZone_",0,-1);
      if(m_name!="") ObjectsDeleteAll(m_chart_id,m_name+"_DraftLevel_",0,-1);
      if(m_name!="") ObjectsDeleteAll(m_chart_id,m_name+"_DraftEntry_",0,-1);
   }
   bool HandleEntryDrag(string name)
   {
      string prefix=m_name+"_DraftEntry_";
      if(name!=prefix+"SL" && name!=prefix+"TP" && name!=prefix+"Entry") return false;
      if(name==prefix+"Entry" && !PendingOrder((ENUM_ORDER_TYPE)m_trade_side.Value())) return true;
      double price=TradePrice(ObjectGetDouble(m_chart_id,name,OBJPROP_PRICE));
      ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTED,false);
      CancelPick();
      if(!MathIsValidNumber(price) || price<=0)
      { FormMessage="SL/TP not changed: price must be positive."; UpdateStatus(); return true; }
      if(name==prefix+"SL") m_trade_sl.Text(DoubleToString(price,_Digits));
      else if(name==prefix+"TP") m_trade_tp.Text(DoubleToString(price,_Digits));
      else m_trade_entry.Text(DoubleToString(price,_Digits));
      Dirty(); return true;
   }
   void RefreshTradePreview()
   {
      if(!m_ready) return;
      double sl=0,tp=0,pendingPrice=0;
      ENUM_ORDER_TYPE side=(ENUM_ORDER_TYPE)m_trade_side.Value();
      bool pending=PendingOrder(side);
      bool validEntry=Number(m_trade_entry.Text(),pendingPrice) && pendingPrice>0;
      pendingPrice=TradePrice(pendingPrice);
      bool validSL=Number(m_trade_sl.Text(),sl) && sl>0;
      bool validTP=Number(m_trade_tp.Text(),tp) && tp>0;
      sl=TradePrice(sl); tp=TradePrice(tp);
      string prefix=m_name+"_DraftEntry_";
      for(int i=0;m_show_entry && i<3;i++)
      {
         string name=prefix+(i==0 ? "SL" : (i==1 ? "TP" : "Entry"));
         bool valid=i==0 ? validSL && sl>0 : (i==1 ? validTP && tp>0 : pending && validEntry && pendingPrice>0);
         double price=i==0 ? sl : (i==1 ? tp : pendingPrice);
         if(!valid) { ObjectDelete(m_chart_id,name); continue; }
         if(ObjectFind(m_chart_id,name)<0 && !ObjectCreate(m_chart_id,name,OBJ_HLINE,0,0,price))
         { Print("Cannot draw SL/TP preview: ",GetLastError()); continue; }
         if(!ObjectGetInteger(m_chart_id,name,OBJPROP_SELECTED)) ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,price);
         ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,i==0 ? clrTomato : (i==1 ? clrLimeGreen : clrDeepSkyBlue));
         ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,2);
         ObjectSetInteger(m_chart_id,name,OBJPROP_BACK,true);
         ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTABLE,true);
         ObjectSetInteger(m_chart_id,name,OBJPROP_HIDDEN,true);
         ObjectSetString(m_chart_id,name,OBJPROP_TOOLTIP,i==0 ? "Draft stop-loss - double-click, then drag" :
                         (i==1 ? "Draft take-profit - double-click, then drag" : "Draft pending entry - double-click, then drag"));
      }
      string currency=AccountInfoString(ACCOUNT_CURRENCY);
      double budget=AccountInfoDouble(ACCOUNT_EQUITY)*0.02;
      m_trade_budget.Text("Draft estimate | 2% budget: "+DoubleToString(budget,2)+" "+currency+" | excludes fees/gaps");
      m_trade_budget.Color(clrDimGray);
      string reason="Enter stop-loss and take-profit prices.";
      bool manual=m_lot_mode.Value()==1; double manualLots=0;
      bool validLots=!manual || (Number(m_manual_lots.Text(),manualLots) && ValidManualLots(manualLots));
      if(!validLots) reason="Enter manual lots matching broker min/max and step.";
      MqlTick quote; double volume=0,loss=0,gain=0;
      if(pending && !validEntry) reason="Enter a pending entry price.";
      if(validSL && validTP && validLots && (!pending || validEntry) && SymbolInfoTick(_Symbol,quote))
      {
         if(EstimateEntry(side,sl,tp,quote,volume,loss,gain,budget,reason,pendingPrice,manual,manualLots))
         {
            m_trade_estimate.Text("Lots: "+DoubleToString(volume,8)+" | SL loss: "+DoubleToString(loss,2)+
                                  " | TP gain: "+DoubleToString(gain,2)+" "+currency+" | R: "+DoubleToString(gain/loss,2));
            double risk=loss/(budget/0.02)*100;
            bool exceeds=loss>budget;
            m_trade_budget.Text((exceeds ? "WARNING: " : "Draft risk: ")+DoubleToString(risk,2)+
                                "%"+(exceeds ? " exceeds 2%" : "")+" | 2% budget: "+DoubleToString(budget,2)+" "+currency);
            m_trade_budget.Color(exceeds ? clrTomato : clrDimGray);
         }
         else m_trade_estimate.Text(reason);
      }
      else m_trade_estimate.Text(reason);
      ChartRedraw(m_chart_id);
   }
   bool HandleLevelDrag(string name)
   {
      string prefix=m_name+"_DraftLevel_";
      if(StringFind(name,prefix)!=0 || ObjectGetInteger(m_chart_id,name,OBJPROP_TYPE)!=OBJ_HLINE) return false;
      int row=(int)StringToInteger(StringSubstr(name,StringLen(prefix)));
      if(row!=m_selected || row<0 || row>=ArraySize(draft)) return true;
      CancelPick(); Capture();
      double price=ObjectGetDouble(m_chart_id,name,OBJPROP_PRICE);
      double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSize>0) price=MathRound(price/tickSize)*tickSize;
      price=NormalizeDouble(price,_Digits);
      ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTED,false);
      if(!KnownRule(draft[row].rule) || ZoneRule(draft[row].rule) || !MathIsValidNumber(price) || price<=0)
      { FormMessage="Level not changed: price must be positive."; UpdateStatus(); return true; }
      draft[row].level=DoubleToString(price,_Digits);
      Fields(); Dirty(); return true;
   }
   void DrawLevelPreviews()
   {
      if(!m_ready || !m_show_levels) return;
      string prefix=m_name+"_DraftLevel_";
      for(int o=ObjectsTotal(m_chart_id,0,OBJ_HLINE)-1;o>=0;o--)
      {
         string name=ObjectName(m_chart_id,o,0,OBJ_HLINE);
         if(StringFind(name,prefix)!=0) continue;
         int row=(int)StringToInteger(StringSubstr(name,StringLen(prefix)));
         double level=0;
         if(row<0 || row>=ArraySize(draft)) { ObjectDelete(m_chart_id,name); continue; }
         if(!KnownRule(draft[row].rule) || ZoneRule(draft[row].rule) ||
            !Number(draft[row].level,level) || level<=0) ObjectDelete(m_chart_id,name);
      }
      for(int i=0;i<ArraySize(draft);i++)
      {
         double level=0;
         if(!KnownRule(draft[i].rule) || ZoneRule(draft[i].rule) ||
            !Number(draft[i].level,level) || level<=0) continue;
         string name=prefix+IntegerToString(i);
         if(ObjectFind(m_chart_id,name)<0 && !ObjectCreate(m_chart_id,name,OBJ_HLINE,0,0,level))
         { Print("Cannot draw price-level preview: ",GetLastError()); continue; }
         bool selected=i==m_selected;
         if(!selected) ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTED,false);
         if(!ObjectGetInteger(m_chart_id,name,OBJPROP_SELECTED)) ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,level);
         ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,selected ? clrOrange : clrDodgerBlue);
         ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,selected ? 2 : 1);
         ObjectSetInteger(m_chart_id,name,OBJPROP_STYLE,STYLE_SOLID);
         ObjectSetInteger(m_chart_id,name,OBJPROP_BACK,true);
         ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTABLE,selected);
         ObjectSetInteger(m_chart_id,name,OBJPROP_HIDDEN,true);
         ObjectSetString(m_chart_id,name,OBJPROP_TOOLTIP,"Draft condition "+IntegerToString(i+1)+
                         " - "+draft[i].rule+"\nPrice level "+DoubleToString(level,_Digits)+
                         (selected ? " - double-click, then drag" : ""));
      }
      ChartRedraw(m_chart_id);
   }
   bool HandleZoneDrag(string name)
   {
      string prefix=m_name+"_DraftZone_";
      if(StringFind(name,prefix)!=0 || ObjectGetInteger(m_chart_id,name,OBJPROP_TYPE)!=OBJ_HLINE)
         return false;
      string suffix=StringSubstr(name,StringLen(prefix));
      int row=(int)StringToInteger(suffix);
      if(row!=m_selected || row<0 || row>=ArraySize(draft)) return true;
      bool isLow=suffix==IntegerToString(row)+"_Low";
      if(!isLow && suffix!=IntegerToString(row)+"_High") return true;
      CancelPick(); Capture();
      double price=ObjectGetDouble(m_chart_id,name,OBJPROP_PRICE);
      double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickSize>0) price=MathRound(price/tickSize)*tickSize;
      price=NormalizeDouble(price,_Digits);
      double low=0,high=0;
      bool valid=ZoneRule(draft[row].rule) && Number(draft[row].low,low) && Number(draft[row].high,high);
      if(isLow) low=price; else high=price;
      ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTED,false);
      if(!valid || !MathIsValidNumber(price) || low<=0 || high<=low)
      {
         FormMessage="Boundary not changed: zone low must be positive and below zone high.";
         UpdateStatus(); return true;
      }
      if(isLow) draft[row].low=DoubleToString(low,_Digits);
      else draft[row].high=DoubleToString(high,_Digits);
      Fields(); Dirty(); return true;
   }
   void DrawZonePreviews()
   {
      RefreshTradePreview();
      DrawLevelPreviews();
      if(!m_ready || !m_show_zones) return;
      string prefix=m_name+"_DraftZone_";
      int first=(int)ChartGetInteger(m_chart_id,CHART_FIRST_VISIBLE_BAR);
      datetime left=iTime(_Symbol,_Period,MathMax(0,first));
      datetime current=iTime(_Symbol,_Period,0);
      if(left==0 || current==0) return;
      datetime right=current+(datetime)(PeriodSeconds(_Period)*20);
      // Only the selected condition has draggable boundary lines.
      double selectedLow=0,selectedHigh=0;
      bool handles=m_selected>=0 && m_selected<ArraySize(draft);
      if(handles) handles=ZoneRule(draft[m_selected].rule) && Number(draft[m_selected].low,selectedLow) &&
                          Number(draft[m_selected].high,selectedHigh) && selectedLow>0 && selectedHigh>selectedLow;
      for(int o=ObjectsTotal(m_chart_id,0,OBJ_HLINE)-1;o>=0;o--)
      {
         string name=ObjectName(m_chart_id,o,0,OBJ_HLINE);
         if(StringFind(name,prefix)!=0) continue;
         string expected=prefix+IntegerToString(m_selected);
         if(!handles || (name!=expected+"_Low" && name!=expected+"_High")) ObjectDelete(m_chart_id,name);
      }
      // Remove only our previews whose draft row was deleted or is no longer a valid zone.
      for(int o=ObjectsTotal(m_chart_id,0,OBJ_RECTANGLE)-1;o>=0;o--)
      {
         string name=ObjectName(m_chart_id,o,0,OBJ_RECTANGLE);
         if(StringFind(name,prefix)!=0) continue;
         int row=(int)StringToInteger(StringSubstr(name,StringLen(prefix)));
         double low=0,high=0;
         if(row<0 || row>=ArraySize(draft)) { ObjectDelete(m_chart_id,name); continue; }
         if(!ZoneRule(draft[row].rule) || !Number(draft[row].low,low) ||
            !Number(draft[row].high,high) || low<=0 || high<=low)
            ObjectDelete(m_chart_id,name);
      }
      for(int i=0;i<ArraySize(draft);i++)
      {
         double low=0,high=0;
         if(!ZoneRule(draft[i].rule) || !Number(draft[i].low,low) ||
            !Number(draft[i].high,high) || low<=0 || high<=low) continue;
         string name=prefix+IntegerToString(i);
         if(ObjectFind(m_chart_id,name)<0 &&
            !ObjectCreate(m_chart_id,name,OBJ_RECTANGLE,0,left,high,right,low))
         { Print("Cannot draw zone preview: ",GetLastError()); continue; }
         ObjectMove(m_chart_id,name,0,left,high); ObjectMove(m_chart_id,name,1,right,low);
         ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,i==m_selected ? clrOrange : clrDodgerBlue);
         ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,i==m_selected ? 2 : 1);
         ObjectSetInteger(m_chart_id,name,OBJPROP_FILL,false);
         ObjectSetInteger(m_chart_id,name,OBJPROP_BACK,true);
         ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTED,false);
         ObjectSetInteger(m_chart_id,name,OBJPROP_HIDDEN,true);
         ObjectSetString(m_chart_id,name,OBJPROP_TOOLTIP,"Draft condition "+IntegerToString(i+1)+
                         " - "+draft[i].rule+"\n"+DoubleToString(low,_Digits)+" to "+DoubleToString(high,_Digits));
      }
      if(handles)
      {
         for(int boundary=0;boundary<2;boundary++)
         {
            string name=prefix+IntegerToString(m_selected)+(boundary==0 ? "_Low" : "_High");
            double price=boundary==0 ? selectedLow : selectedHigh;
            if(ObjectFind(m_chart_id,name)<0 && !ObjectCreate(m_chart_id,name,OBJ_HLINE,0,0,price))
            { Print("Cannot draw zone boundary: ",GetLastError()); continue; }
            // Leave a selected handle alone until MT5 sends its drag/change event.
            if(!ObjectGetInteger(m_chart_id,name,OBJPROP_SELECTED)) ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,price);
            ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,clrOrange);
            ObjectSetInteger(m_chart_id,name,OBJPROP_STYLE,STYLE_DASH);
            ObjectSetInteger(m_chart_id,name,OBJPROP_BACK,true);
            ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTABLE,true);
            ObjectSetInteger(m_chart_id,name,OBJPROP_HIDDEN,true);
            ObjectSetString(m_chart_id,name,OBJPROP_TOOLTIP,"Draft condition "+IntegerToString(m_selected+1)+
                            (boundary==0 ? " zone low - double-click, then drag" : " zone high - double-click, then drag"));
         }
      }
      ChartRedraw(m_chart_id);
   }
   bool HandlePriceClick(int x,int y)
   {
      if(!m_picking) return false;
      // Clicks on the panel must never be interpreted as chart prices.
      if(x>=Left() && x<=Right() && y>=Top() && y<=Bottom()) return false;
      if(m_pick_field<=2 && (m_selected<0 || m_selected>=ArraySize(draft))) { CancelPick(); return true; }
      int window=0; datetime time=0; double price=0;
      if(!ChartXYToTimePrice(m_chart_id,x,y,window,time,price) || window!=0 ||
         !MathIsValidNumber(price) || price<=0)
      {
         FormMessage="Click the main price chart, outside the panel. Esc cancels.";
         UpdateStatus(); return true;
      }
      double tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tick_size>0) price=MathRound(price/tick_size)*tick_size;
      price=NormalizeDouble(price,_Digits);
      if(price<=0) return true;
      string value=DoubleToString(price,_Digits);
      Capture();
      if(m_pick_field==0) draft[m_selected].level=value;
      else if(m_pick_field==1) draft[m_selected].low=value;
      else if(m_pick_field==2) draft[m_selected].high=value;
      else if(m_pick_field==3) m_trade_sl.Text(value);
      else if(m_pick_field==4) m_trade_tp.Text(value);
      else if(m_pick_field==5) m_trade_entry.Text(value);
      CancelPick(); Fields();
      FormMessage="Copied "+value+" into draft. Apply & Restart to use it.";
      UpdateStatus(); return true;
   }
   bool HandleEscape()
   {
      if(!m_picking) return false;
      CancelPick(); FormMessage="Price picking cancelled."; UpdateStatus(); return true;
   }
   bool HandleWheel(const long packed,const double delta)
   {
      if(delta==0) return false;
      int x=(int)(short)packed,y=(int)(short)(packed>>16);
      return ScrollDropdown(m_rule,x,y,(int)delta) ||
             ScrollDropdown(m_mode,x,y,(int)delta) ||
             ScrollDropdown(m_timeframe,x,y,(int)delta) ||
             ScrollDropdown(m_trade_side,x,y,(int)delta) || ScrollDropdown(m_lot_mode,x,y,(int)delta) || ScrollList(m_condition,x,y,(int)delta);
   }
   virtual bool Create(const long chart,const string name,const int subwin,
                       const int x1,const int y1,const int x2,const int y2)
   {
      if(!CAppDialog::Create(chart,name,subwin,x1,y1,x2,y2)) return false;
      m_show_zones=ShowZonePreviews; m_show_levels=ShowPriceLevelPreviews;
      m_show_entry=true;
      if(!m_condition.TotalView(5) ||
         !m_condition.Create(chart,name+"ConditionList",subwin,12,42,562,144) || !Add(m_condition)) return false;
      if(!Button(m_list_toggle,"ListToggle","- Hide conditions",12,8,210) ||
         !Button(m_zone_toggle,"ZoneToggle","Hide zones",232,8,90) ||
         !Button(m_level_toggle,"LevelToggle","Hide levels",332,8,90) ||
         !Button(m_entry_toggle,"EntryToggle","Hide entry/SL/TP",432,8,130) ||
         !Button(m_add,"Add","+ Add",12,66,94) ||
         !Button(m_remove,"Remove","Remove",114,66,94) ||
         !Button(m_up,"Up","Move up",216,66,94) ||
         !Button(m_down,"Down","Move down",318,66,104) ||
         !Button(m_import,"Import","Import CSV",430,66,132) ||
         !Label(m_rule_label,"RuleLabel","Rule",12,108,320) ||
         !Combo(m_rule,"Rule",12,130,550) ||
         !Label(m_mode_label,"ModeLabel","Evaluate",12,164,250) ||
         !Label(m_tf_label,"TfLabel","Candle timeframe",300,164,260) ||
         !Combo(m_mode,"Mode",12,186,270) ||
         !Combo(m_timeframe,"Timeframe",300,186,262) ||
         !Label(m_level_label,"LevelLabel","Price level",12,220,170) ||
         !Label(m_low_label,"LowLabel","Zone low",200,220,170) ||
         !Label(m_high_label,"HighLabel","Zone high",388,220,170) ||
         !Edit(m_level,"Level",12,242,174) ||
         !Edit(m_low,"Low",200,242,174) ||
         !Edit(m_high,"High",388,242,174) ||
         !Label(m_help,"Help","",12,276,550) ||
         !Label(m_trade_side_label,"TradeSideLabel","Order type",12,302,174) ||
         !Label(m_trade_sl_label,"TradeSLLabel","Stop-loss price",200,302,174) ||
         !Label(m_trade_tp_label,"TradeTPLabel","Take-profit price",388,302,174) ||
         !Combo(m_trade_side,"TradeSide",12,324,174) ||
         !Edit(m_trade_sl,"TradeSL",200,324,174) ||
         !Edit(m_trade_tp,"TradeTP",388,324,174) ||
         !Label(m_trade_entry_label,"TradeEntryLabel","Pending entry price",12,354,174) ||
         !Edit(m_trade_entry,"TradeEntry",200,350,174) ||
         !Label(m_lot_mode_label,"LotModeLabel","Lot sizing",12,384,100) ||
         !Combo(m_lot_mode,"LotMode",112,380,176) ||
         !Label(m_manual_lots_label,"ManualLotsLabel","Manual lots",300,384,85) ||
         !Edit(m_manual_lots,"ManualLots",388,380,174) ||
         !Label(m_trade_estimate,"TradeEstimate","",12,416,550) ||
         !Label(m_trade_budget,"TradeBudget","",12,439,550) ||
         !Button(m_trade_switch,"TradeSwitch","Auto entry OFF - alerts only",12,468,550) ||
         !Button(m_apply,"Apply","Apply & Restart",12,516,270) ||
         !Button(m_pause,"Pause","Resume & Restart",300,516,262) ||
         !Label(m_status,"Status","",12,554,550) ||
         !Label(m_message,"Message","",12,579,550)) return false;
      m_list_expanded=true; Height(Height()+110); m_norm_rect.Height(Height()); ShiftEditor(110);
      m_rule.ListViewItems(6);
      for(int i=0;i<ArraySize(ruleCodes);i++) if(!m_rule.AddItem(ruleNames[i],i)) return false;
      if(!m_mode.AddItem("Live Bid",0) || !m_mode.AddItem("Completed candle",1)) return false;
      if(!m_trade_side.AddItem("Buy market",ORDER_TYPE_BUY) || !m_trade_side.AddItem("Sell market",ORDER_TYPE_SELL) ||
         !m_trade_side.AddItem("Buy Limit",ORDER_TYPE_BUY_LIMIT) || !m_trade_side.AddItem("Sell Limit",ORDER_TYPE_SELL_LIMIT) ||
         !m_trade_side.AddItem("Buy Stop",ORDER_TYPE_BUY_STOP) || !m_trade_side.AddItem("Sell Stop",ORDER_TYPE_SELL_STOP)) return false;
      m_trade_side.Select(0);
      m_trade_entry.Disable();
      if(!m_lot_mode.AddItem("Auto (2% risk)",0) || !m_lot_mode.AddItem("Manual lots",1)) return false;
      m_lot_mode.Select(0); m_manual_lots.Text("0.01"); m_manual_lots.Disable();
      for(int i=0;i<ArraySize(tfValues);i++) if(!m_timeframe.AddItem(tfNames[i],i)) return false;
      m_ready=true; m_selected=0; RefreshList();
      UpdateVisibilityButtons();
      int chartHeight=(int)ChartGetInteger(m_chart_id,CHART_HEIGHT_IN_PIXELS,0);
      if(chartHeight>0 && Height()+CONTROLS_BORDER_WIDTH>chartHeight) OnListToggle();
      HandleChartResize();
      return true;
   }
   void UpdateStatus()
   {
      if(!m_ready) return;
      string status="Paused";
      if(!paused && !finished && ArraySize(conditions)>0)
         status="Monitoring condition "+IntegerToString(active+1)+" / "+IntegerToString(ArraySize(conditions))+": "+conditions[active].rule;
      else if(finished) status="Complete - click Resume & Restart or Apply to rearm";
      m_status.Text((autoEntry ? (entryManualLots ? "ENTRY manual lots | " : "ENTRY auto 2% | ") : "ALERTS | ")+status);
      m_message.Text(FormMessage);
      m_pause.Text(paused || finished ? "Resume & Restart" : "Pause");
      DrawZonePreviews();
      ChartRedraw();
   }
   virtual bool OnEvent(const int id,const long &lparam,const double &dparam,const string &sparam);
};
EVENT_MAP_BEGIN(CConditionPanel)
   ON_EVENT(ON_CLICK,m_entry_toggle,OnEntryToggle)
   ON_EVENT(ON_CLICK,m_zone_toggle,OnZoneToggle)
   ON_EVENT(ON_CLICK,m_level_toggle,OnLevelToggle)
   ON_EVENT(ON_CHANGE,m_lot_mode,OnTradeEdit)
   ON_EVENT(ON_END_EDIT,m_manual_lots,OnTradeEdit)
   ON_EVENT(ON_CLICK,m_trade_switch,OnTradeSwitch)
   ON_EVENT(ON_CHANGE,m_trade_side,OnTradeEdit)
   ON_EVENT(ON_END_EDIT,m_trade_sl,OnTradeEdit)
   ON_EVENT(ON_END_EDIT,m_trade_tp,OnTradeEdit)
   ON_EVENT(ON_END_EDIT,m_trade_entry,OnTradeEdit)
   ON_EVENT(ON_CLICK,m_list_toggle,OnListToggle)
   ON_EVENT(ON_CHANGE,m_condition,OnSelect)
   ON_EVENT(ON_CHANGE,m_rule,OnRule)
   ON_EVENT(ON_CHANGE,m_mode,OnMode)
   ON_EVENT(ON_CHANGE,m_timeframe,OnTimeframe)
   ON_EVENT(ON_END_EDIT,m_level,OnEdit)
   ON_EVENT(ON_END_EDIT,m_low,OnEdit)
   ON_EVENT(ON_END_EDIT,m_high,OnEdit)
   ON_EVENT(ON_CLICK,m_add,OnAdd)
   ON_EVENT(ON_CLICK,m_remove,OnRemove)
   ON_EVENT(ON_CLICK,m_up,OnUp)
   ON_EVENT(ON_CLICK,m_down,OnDown)
   ON_EVENT(ON_CLICK,m_apply,OnApply)
   ON_EVENT(ON_CLICK,m_pause,OnPause)
   ON_EVENT(ON_CLICK,m_import,OnImport)
EVENT_MAP_END(CAppDialog)
CConditionPanel panel;
int OnInit()
{
   if(SequenceTimeoutMinutes<0 || ResetAfterTickGapSeconds<0 || EntryMaxSpreadPoints<0)
      return INIT_PARAMETERS_INCORRECT;
   active=0; finished=false; started=0; previousBid=0; lastTick=0; lastPush=0;
   paused=true; ArrayResize(conditions,0); ArrayResize(draft,0);
   autoEntry=false; entrySL=0; entryTP=0; entryPendingPrice=0; entryManualLots=false; entryLots=0;
   entryLock="PCA."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"."+
             StringSubstr(AccountInfoString(ACCOUNT_SERVER),0,16)+"."+StringSubstr(_Symbol,0,16);
   // Reattaching must reuse the shared lock without resetting another instance's cooldown.
   if(!GlobalVariableCheck(entryLock))
   {
      ResetLastError();
      if(!GlobalVariableTemp(entryLock))
      {
         int error=GetLastError();
         // Another chart can create the lock between the existence check and creation.
         if(error!=ERR_GLOBALVARIABLE_EXISTS || !GlobalVariableCheck(entryLock))
         { Print("Cannot initialize entry lock: ",error); return INIT_FAILED; }
      }
   }
   string symbol=_Symbol;
   StringReplace(symbol,"/","_"); StringReplace(symbol,"\\","_"); StringReplace(symbol,":","_");
   string server=AccountInfoString(ACCOUNT_SERVER);
   StringReplace(server,"/","_"); StringReplace(server,"\\","_"); StringReplace(server,":","_");
   savedFile="PriceConditionAlerts\\"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+
             server+"_"+symbol+"_"+IntegerToString(ChartID())+".csv";
   if(FileIsExist(savedFile))
   {
      Condition saved[];
      if(LoadConditions(savedFile,saved))
      {
         ArrayResize(conditions,ArraySize(saved));
         for(int i=0;i<ArraySize(saved);i++) conditions[i]=saved[i];
         CopyToDraft(saved);
         FormMessage="Saved list restored. Click Resume & Restart when ready.";
      }
      else FormMessage="Saved settings could not be loaded. Edit or import a new list.";
   }
   if(!panel.Create(ChartID(),"My trading conditions",0,20,30,620,679) || !panel.Run())
   { panel.Destroy(REASON_INITFAILED); return INIT_FAILED; }
   panel.RestoreDraftState();
   ChartSetInteger(ChartID(),CHART_EVENT_MOUSE_WHEEL,true);
   ChartSetInteger(ChartID(),CHART_EVENT_MOUSE_MOVE,true);
   Print("On-chart editor ready for ",_Symbol,". Monitoring paused; automatic entry OFF.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { if(reason!=REASON_INITFAILED) panel.SaveDraftState(); panel.ClearZonePreviews(); panel.Destroy(reason); panel.RestoreChartScroll(); Comment(""); }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_MOUSE_MOVE) panel.HandlePointer((int)lparam,(int)dparam);
   if(id==CHARTEVENT_OBJECT_DRAG || id==CHARTEVENT_OBJECT_CHANGE)
      if(panel.HandleZoneDrag(sparam) || panel.HandleLevelDrag(sparam) || panel.HandleEntryDrag(sparam)) return;
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      // CAppDialog's default handler auto-minimizes panels taller than the chart.
      // This fixed main-chart editor keeps its state; only user controls minimize it.
      panel.HandleChartResize(); panel.DrawZonePreviews(); return;
   }
   if(id==CHARTEVENT_MOUSE_WHEEL)
   {
      panel.HandlePointer((int)(short)lparam,(int)(short)(lparam>>16));
      if(panel.HandleWheel(lparam,dparam)) return;
   }
   if(id==CHARTEVENT_CLICK)
   {
      if(panel.HandleFieldLabelClick((int)lparam,(int)dparam)) return;
      if(panel.HandlePriceClick((int)lparam,(int)dparam)) return;
   }
   if(id==CHARTEVENT_KEYDOWN && lparam==27 && panel.HandleEscape()) return;
   panel.ChartEvent(id,lparam,dparam,sparam);
   if(id==CHARTEVENT_MOUSE_MOVE) panel.HandlePointer((int)lparam,(int)dparam);
}
void OnTick()
{
   static datetime previewSecond=0;
   datetime nowPreview=TimeLocal();
   if(nowPreview!=previewSecond) { previewSecond=nowPreview; panel.RefreshTradePreview(); }
   static datetime previewBar=0;
   datetime chartBar=iTime(_Symbol,_Period,0);
   if(chartBar!=previewBar) { previewBar=chartBar; panel.DrawZonePreviews(); }
   if(paused || finished || ArraySize(conditions)==0) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0) return;
   datetime now=TimeCurrent();
   if(lastTick!=0 && ResetAfterTickGapSeconds>0 && now-lastTick>ResetAfterTickGapSeconds)
   { ResetSequence("Tick gap detected"); previousBid=0; panel.UpdateStatus(); }
   lastTick=now;
   if(previousBid==0) { previousBid=tick.bid; return; }
   if(started!=0 && SequenceTimeoutMinutes>0 && now-started>SequenceTimeoutMinutes*60)
   { ResetSequence("Sequence expired"); panel.UpdateStatus(); }
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
   if(!Matches(item,prior,bar)) return;
   if(active==0) started=now;
   Print("Condition ",active+1," passed: ",item.rule," at ",TimeToString(now,TIME_DATE|TIME_SECONDS));
   active++;
   if(active==ArraySize(conditions))
   {
      if(autoEntry)
      {
         finished=true; // One attempt per arm, even if skipped/rejected; no automatic retries.
         ExecuteEntry(); Notify(tick.bid); panel.UpdateStatus(); return;
      }
      Notify(tick.bid);
      if(OneShot) { finished=true; panel.UpdateStatus(); return; }
      ResetSequence("Sequence completed");
   }
   else PrimeStep(); // Next condition starts after this update, with fresh sweep memory.
   panel.UpdateStatus();
}
