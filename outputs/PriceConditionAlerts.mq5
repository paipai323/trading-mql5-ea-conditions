#property strict
#property version "1.09"
#property description "On-chart condition editor. Alerts only; no order operations."
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
struct DraftCondition
{
   string rule,level,low,high;
   bool live;
   ENUM_TIMEFRAMES timeframe;
};
DraftCondition draft[];
bool paused=true;
string savedFile="";
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
   CComboBox m_rule,m_mode,m_timeframe,m_pick_target;
   CButton m_list_toggle;
   bool m_list_expanded;
   CEdit m_level,m_low,m_high;
   CButton m_add,m_remove,m_up,m_down,m_apply,m_pause,m_import,m_drawing,m_pick;
   CLabel m_select_label,m_rule_label,m_mode_label,m_tf_label;
   CLabel m_level_label,m_low_label,m_high_label,m_help,m_status,m_message;
   int m_selected;
   bool m_ready;
   bool m_picking;
   int m_pick_field;
   void ShiftEditor(int dy)
   {
      m_add.Shift(0,dy); m_remove.Shift(0,dy); m_up.Shift(0,dy); m_down.Shift(0,dy);
      m_import.Shift(0,dy); m_rule_label.Shift(0,dy); m_rule.Shift(0,dy);
      m_mode_label.Shift(0,dy); m_tf_label.Shift(0,dy); m_mode.Shift(0,dy); m_timeframe.Shift(0,dy);
      m_level_label.Shift(0,dy); m_low_label.Shift(0,dy); m_high_label.Shift(0,dy);
      m_level.Shift(0,dy); m_low.Shift(0,dy); m_high.Shift(0,dy); m_help.Shift(0,dy);
      m_drawing.Shift(0,dy); m_pick_target.Shift(0,dy); m_pick.Shift(0,dy);
      m_apply.Shift(0,dy); m_pause.Shift(0,dy); m_status.Shift(0,dy); m_message.Shift(0,dy);
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
   { m_picking=false; m_pick.Text("Pick price"); }
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
   void Fields()
   {
      bool available=m_selected>=0 && m_selected<ArraySize(draft);
      if(!available)
      {
         m_rule.Disable(); m_mode.Disable(); m_timeframe.Disable();
         m_level.Disable(); m_low.Disable(); m_high.Disable();
         m_remove.Disable(); m_up.Disable(); m_down.Disable(); m_drawing.Disable();
         m_pick_target.Disable(); m_pick.Disable(); CancelPick();
         m_level.Text(""); m_low.Text(""); m_high.Text("");
         m_help.Text("Click Add condition to begin."); return;
      }
      m_rule.Enable(); m_remove.Enable(); m_drawing.Enable(); m_pick.Enable(); m_pick_target.Enable();
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
      m_pick_target.ItemsClear();
      if(zone)
      {
         m_pick_target.AddItem("Zone low",1); m_pick_target.AddItem("Zone high",2);
         if(m_pick_field==0) m_pick_field=1;
      }
      else { m_pick_target.AddItem("Price level",0); m_pick_field=0; }
      m_pick_target.SelectByValue(m_pick_field);
      if(zone) { m_level.Disable(); m_low.Enable(); m_high.Enable(); }
      else { m_level.Enable(); m_low.Disable(); m_high.Disable(); }
      if(m_selected>0) m_up.Enable(); else m_up.Disable();
      if(m_selected<ArraySize(draft)-1) m_down.Enable(); else m_down.Disable();
      m_help.Text(draft[m_selected].live ? "Live Bid; no candle-close wait." : "Checks newly completed candles on the selected timeframe.");
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
      if(!ValidateDraft(candidate) || !SaveConditions(candidate)) { UpdateStatus(); return; }
      if(ArrayResize(conditions,ArraySize(candidate))!=ArraySize(candidate))
      { FormMessage="Not enough memory to start monitoring."; UpdateStatus(); return; }
      for(int i=0;i<ArraySize(candidate);i++) conditions[i]=candidate[i];
      StartMonitoring(); FormMessage="Applied and saved. Monitoring restarted at condition 1.";
      UpdateStatus();
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
   void OnDrawing()
   {
      if(m_selected<0) return;
      CancelPick();
      Capture(); bool zone=ZoneRule(draft[m_selected].rule);
      string chosen=""; int matches=0;
      int total=ObjectsTotal(m_chart_id,0,-1);
      for(int i=0;i<total;i++)
      {
         string name=ObjectName(m_chart_id,i,0,-1);
         if(StringFind(name,m_name+"_DraftZone_")==0) continue;
         ENUM_OBJECT type=(ENUM_OBJECT)ObjectGetInteger(m_chart_id,name,OBJPROP_TYPE);
         if((zone && type!=OBJ_RECTANGLE) || (!zone && type!=OBJ_HLINE)) continue;
         if(!ObjectGetInteger(m_chart_id,name,OBJPROP_SELECTED)) continue;
         chosen=name; matches++;
      }
      if(matches!=1)
      { FormMessage=zone ? "Select exactly one chart rectangle, then click Use selected drawing." :
                          "Select exactly one horizontal line, then click Use selected drawing.";
        UpdateStatus(); return; }
      double first=ObjectGetDouble(m_chart_id,chosen,OBJPROP_PRICE,0);
      if(zone)
      {
         double second=ObjectGetDouble(m_chart_id,chosen,OBJPROP_PRICE,1);
         draft[m_selected].low=DoubleToString(MathMin(first,second),_Digits);
         draft[m_selected].high=DoubleToString(MathMax(first,second),_Digits);
      }
      else draft[m_selected].level=DoubleToString(first,_Digits);
      Fields(); FormMessage="Copied drawing prices into draft. Apply to use them."; UpdateStatus();
   }
   void OnPickTarget()
   {
      int target=(int)m_pick_target.Value();
      if(target==m_pick_field || target<0 || target>2) return;
      CancelPick(); m_pick_field=target;
      FormMessage="Choose Pick price, then click the main chart."; UpdateStatus();
   }
   void OnPick()
   {
      if(m_selected<0) return;
      Capture();
      if(m_picking)
      { CancelPick(); FormMessage="Price picking cancelled."; UpdateStatus(); return; }
      m_pick_field=(int)m_pick_target.Value();
      m_picking=true; m_pick.Text("Cancel pick");
      string field=m_pick_field==0 ? "price level" : (m_pick_field==1 ? "zone low" : "zone high");
      FormMessage="Click the main chart to set "+field+". Esc cancels.";
      UpdateStatus();
   }
protected:
   virtual void OnClickButtonClose(void) { Minimize(); }
   virtual void OnClickButtonMinMax(void)
   { if(m_minimized) Maximize(); else Minimize(); SubwinOff(); }
public:
   CConditionPanel() { m_selected=-1; m_ready=false; m_picking=false; m_pick_field=0; }
   void ClearZonePreviews()
   {
      if(m_name!="") ObjectsDeleteAll(m_chart_id,m_name+"_DraftZone_",0,-1);
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
      if(!m_ready || !ShowZonePreviews) return;
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
      if(m_selected<0 || m_selected>=ArraySize(draft)) { CancelPick(); return true; }
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
      else draft[m_selected].high=value;
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
             ScrollDropdown(m_pick_target,x,y,(int)delta) || ScrollList(m_condition,x,y,(int)delta);
   }
   virtual bool Create(const long chart,const string name,const int subwin,
                       const int x1,const int y1,const int x2,const int y2)
   {
      if(!CAppDialog::Create(chart,name,subwin,x1,y1,x2,y2)) return false;
      if(!m_condition.TotalView(5) ||
         !m_condition.Create(chart,name+"ConditionList",subwin,12,42,562,144) || !Add(m_condition)) return false;
      if(!Button(m_list_toggle,"ListToggle","- Hide conditions",12,8,270) ||
         !Label(m_select_label,"SelectLabel","Click a condition to edit it",300,12,262) ||
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
         !Button(m_drawing,"Drawing","Use selected line / rectangle",12,302,270) ||
         !Combo(m_pick_target,"PickTarget",300,302,156) ||
         !Button(m_pick,"Pick","Pick price",464,302,98) ||
         !Button(m_apply,"Apply","Apply & Restart",12,342,270) ||
         !Button(m_pause,"Pause","Resume & Restart",300,342,262) ||
         !Label(m_status,"Status","",12,380,550) ||
         !Label(m_message,"Message","",12,405,550)) return false;
      m_list_expanded=true; Height(Height()+110); m_norm_rect.Height(Height()); ShiftEditor(110);
      m_rule.ListViewItems(6);
      for(int i=0;i<ArraySize(ruleCodes);i++) if(!m_rule.AddItem(ruleNames[i],i)) return false;
      if(!m_mode.AddItem("Live Bid",0) || !m_mode.AddItem("Completed candle",1)) return false;
      for(int i=0;i<ArraySize(tfValues);i++) if(!m_timeframe.AddItem(tfNames[i],i)) return false;
      m_ready=true; m_selected=0; RefreshList();
      return true;
   }
   void UpdateStatus()
   {
      if(!m_ready) return;
      string status="Paused";
      if(!paused && !finished && ArraySize(conditions)>0)
         status="Monitoring condition "+IntegerToString(active+1)+" / "+IntegerToString(ArraySize(conditions))+": "+conditions[active].rule;
      else if(finished) status="Complete - click Resume & Restart or Apply to rearm";
      m_status.Text(status);
      m_message.Text(FormMessage);
      m_pause.Text(paused || finished ? "Resume & Restart" : "Pause");
      DrawZonePreviews();
      ChartRedraw();
   }
   virtual bool OnEvent(const int id,const long &lparam,const double &dparam,const string &sparam);
};
EVENT_MAP_BEGIN(CConditionPanel)
   ON_EVENT(ON_CLICK,m_list_toggle,OnListToggle)
   ON_EVENT(ON_CHANGE,m_condition,OnSelect)
   ON_EVENT(ON_CHANGE,m_rule,OnRule)
   ON_EVENT(ON_CHANGE,m_mode,OnMode)
   ON_EVENT(ON_CHANGE,m_timeframe,OnTimeframe)
   ON_EVENT(ON_CHANGE,m_pick_target,OnPickTarget)
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
   ON_EVENT(ON_CLICK,m_drawing,OnDrawing)
   ON_EVENT(ON_CLICK,m_pick,OnPick)
EVENT_MAP_END(CAppDialog)
CConditionPanel panel;
int OnInit()
{
   if(SequenceTimeoutMinutes<0 || ResetAfterTickGapSeconds<0)
      return INIT_PARAMETERS_INCORRECT;
   active=0; finished=false; started=0; previousBid=0; lastTick=0; lastPush=0;
   paused=true; ArrayResize(conditions,0); ArrayResize(draft,0);
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
   if(!panel.Create(ChartID(),"My trading conditions",0,20,30,620,505) || !panel.Run())
   { panel.Destroy(REASON_INITFAILED); return INIT_FAILED; }
   ChartSetInteger(ChartID(),CHART_EVENT_MOUSE_WHEEL,true);
   Print("On-chart editor ready for ",_Symbol,". Monitoring paused; no orders will be sent.");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { panel.ClearZonePreviews(); panel.Destroy(reason); Comment(""); }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if((id==CHARTEVENT_OBJECT_DRAG || id==CHARTEVENT_OBJECT_CHANGE) && panel.HandleZoneDrag(sparam)) return;
   if(id==CHARTEVENT_CHART_CHANGE) panel.DrawZonePreviews();
   if(id==CHARTEVENT_MOUSE_WHEEL && panel.HandleWheel(lparam,dparam)) return;
   if(id==CHARTEVENT_CLICK && panel.HandlePriceClick((int)lparam,(int)dparam)) return;
   if(id==CHARTEVENT_KEYDOWN && lparam==27 && panel.HandleEscape()) return;
   panel.ChartEvent(id,lparam,dparam,sparam);
}
void OnTick()
{
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
      Notify(tick.bid);
      if(OneShot) { finished=true; panel.UpdateStatus(); return; }
      ResetSequence("Sequence completed");
   }
   else PrimeStep(); // Next condition starts after this update, with fresh sweep memory.
   panel.UpdateStatus();
}
