//+------------------------------------------------------------------+
//| PropGuard.mqh - reusable risk guard for prop-firm style rules    |
//| MIT License, Copyright (c) 2026 StanleyDaniels                   |
//+------------------------------------------------------------------+
#property strict
#ifndef PROPGUARD_MQH
#define PROPGUARD_MQH

#include <Trade/Trade.mqh>

enum ENUM_PG_DD_MODE
  {
   PG_DD_STATIC   = 0,  // Static: limit measured from initial balance
   PG_DD_TRAILING = 1   // Trailing: limit follows the highest equity seen
  };

struct PropGuardSettings
  {
   double            initialBalance;      // account size at challenge start (0 = current balance)
   double            dailyLossPct;        // max loss per day, % of reference
   bool              dailyFromEquity;     // daily reference = max(balance, equity) at day start
   double            maxDrawdownPct;      // max overall loss, % of initial balance
   ENUM_PG_DD_MODE   ddMode;
   double            maxOpenRiskPct;      // summed SL risk of open positions, % of balance
   int               maxTradesPerDay;     // 0 = unlimited
   double            safetyBufferPct;     // flatten this many % before the hard limit
   int               tradeStartHour;      // server time, inclusive
   int               tradeEndHour;        // server time, exclusive (start==end -> 24h)
   bool              blockFriday;         // no new trades after fridayCutoffHour
   int               fridayCutoffHour;
   string            newsTimes;           // "2026.10.16 12:30;2026.10.17 14:00" server time
   int               newsMinutesBefore;
   int               newsMinutesAfter;
   bool              flattenBeforeNews;
   double            consistencyPct;      // best day must be <= this % of total profit (0 = off)
   long              magicFilter;         // -1 = all positions on account
   bool              stopAfterTarget;     // stop trading once profitTargetPct reached
   double            profitTargetPct;
  };

class CPropGuard
  {
private:
   PropGuardSettings m_s;
   CTrade            m_trade;
   double            m_dayStartRef;
   double            m_peakEquity;
   datetime          m_dayStart;
   int               m_tradesToday;
   bool              m_lockedToday;
   bool              m_lockedForever;
   string            m_reason;
   datetime          m_news[];
   string            m_gvPrefix;

   datetime          DayStart(datetime t)
     {
      MqlDateTime d;
      TimeToStruct(t, d);
      d.hour = 0; d.min = 0; d.sec = 0;
      return StructToTime(d);
     }

   void              ParseNews()
     {
      ArrayResize(m_news, 0);
      string parts[];
      int n = StringSplit(m_s.newsTimes, ';', parts);
      for(int i = 0; i < n; i++)
        {
         string p = parts[i];
         StringTrimLeft(p);
         StringTrimRight(p);
         if(StringLen(p) == 0) continue;
         datetime t = StringToTime(p);
         if(t > 0)
           {
            int k = ArraySize(m_news);
            ArrayResize(m_news, k + 1);
            m_news[k] = t;
           }
        }
     }

   bool              OwnPosition()
     {
      return (m_s.magicFilter < 0 || PositionGetInteger(POSITION_MAGIC) == m_s.magicFilter);
     }

   void              SaveState()
     {
      GlobalVariableSet(m_gvPrefix + "peak", m_peakEquity);
      GlobalVariableSet(m_gvPrefix + "dayref", m_dayStartRef);
      GlobalVariableSet(m_gvPrefix + "day", (double)m_dayStart);
      GlobalVariableSet(m_gvPrefix + "init", m_s.initialBalance);
      GlobalVariableSet(m_gvPrefix + "lockall", m_lockedForever ? 1.0 : 0.0);
     }

   void              LoadState()
     {
      if(GlobalVariableCheck(m_gvPrefix + "peak"))   m_peakEquity  = GlobalVariableGet(m_gvPrefix + "peak");
      if(GlobalVariableCheck(m_gvPrefix + "init") && m_s.initialBalance <= 0)
         m_s.initialBalance = GlobalVariableGet(m_gvPrefix + "init");
      if(GlobalVariableCheck(m_gvPrefix + "day"))
        {
         datetime d = (datetime)GlobalVariableGet(m_gvPrefix + "day");
         if(d == DayStart(TimeCurrent()) && GlobalVariableCheck(m_gvPrefix + "dayref"))
           {
            m_dayStart = d;
            m_dayStartRef = GlobalVariableGet(m_gvPrefix + "dayref");
           }
        }
      if(GlobalVariableCheck(m_gvPrefix + "lockall"))
         m_lockedForever = (GlobalVariableGet(m_gvPrefix + "lockall") > 0.5);
     }

   void              NewDay()
     {
      m_dayStart = DayStart(TimeCurrent());
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartRef = m_s.dailyFromEquity ? MathMax(bal, eq) : bal;
      m_lockedToday = false;
      m_tradesToday = CountTradesToday();
      SaveState();
     }

   int               CountTradesToday()
     {
      int cnt = 0;
      if(!HistorySelect(m_dayStart, TimeCurrent() + 60)) return 0;
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0) continue;
         if(HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if(m_s.magicFilter >= 0 && HistoryDealGetInteger(tk, DEAL_MAGIC) != m_s.magicFilter) continue;
         cnt++;
        }
      return cnt;
     }

   void              Lock(const string why, bool forever)
     {
      if(forever) m_lockedForever = true;
      else        m_lockedToday = true;
      if(m_reason != why)
        {
         m_reason = why;
         Print("[PropGuard] LOCK: ", why);
        }
      SaveState();
     }

public:
                     CPropGuard() : m_dayStartRef(0), m_peakEquity(0), m_dayStart(0), m_tradesToday(0),
                     m_lockedToday(false), m_lockedForever(false), m_reason("") {}

   static void       Defaults(PropGuardSettings &s)
     {
      s.initialBalance = 0;   s.dailyLossPct = 5.0;   s.dailyFromEquity = true;
      s.maxDrawdownPct = 10.0; s.ddMode = PG_DD_STATIC; s.maxOpenRiskPct = 2.0;
      s.maxTradesPerDay = 0;  s.safetyBufferPct = 0.5;
      s.tradeStartHour = 0;   s.tradeEndHour = 0;
      s.blockFriday = false;  s.fridayCutoffHour = 20;
      s.newsTimes = "";       s.newsMinutesBefore = 5; s.newsMinutesAfter = 5;
      s.flattenBeforeNews = false;
      s.consistencyPct = 0;   s.magicFilter = -1;
      s.stopAfterTarget = false; s.profitTargetPct = 8.0;
     }

   bool              Init(const PropGuardSettings &s)
     {
      m_s = s;
      m_gvPrefix = "PG_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_";
      LoadState();
      if(m_s.initialBalance <= 0) m_s.initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(m_peakEquity < m_s.initialBalance) m_peakEquity = m_s.initialBalance;
      ParseNews();
      if(m_dayStart != DayStart(TimeCurrent())) NewDay();
      else m_tradesToday = CountTradesToday();
      m_trade.SetDeviationInPoints(50);
      SaveState();
      return true;
     }

   //--- levels
   double            DailyFloor()   { return m_dayStartRef * (1.0 - m_s.dailyLossPct / 100.0); }
   double            OverallFloor()
     {
      double base = (m_s.ddMode == PG_DD_TRAILING) ? m_peakEquity : m_s.initialBalance;
      double floor = base - m_s.initialBalance * m_s.maxDrawdownPct / 100.0;
      // trailing floors usually stop at the initial balance
      if(m_s.ddMode == PG_DD_TRAILING) floor = MathMin(floor, m_s.initialBalance);
      return floor;
     }
   double            Buffer()       { return m_s.initialBalance * m_s.safetyBufferPct / 100.0; }
   string            Reason()       { return m_reason; }
   int               TradesToday()  { return m_tradesToday; }
   bool              IsLocked()     { return m_lockedForever || m_lockedToday; }

   //--- open risk of all guarded positions in account currency (no SL = treat as unlimited)
   double            OpenRisk(bool &unprotected)
     {
      unprotected = false;
      double risk = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !OwnPosition()) continue;
         string sym = PositionGetString(POSITION_SYMBOL);
         double sl  = PositionGetDouble(POSITION_SL);
         double op  = PositionGetDouble(POSITION_PRICE_OPEN);
         double vol = PositionGetDouble(POSITION_VOLUME);
         if(sl <= 0) { unprotected = true; continue; }
         double tsz = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         double tvl = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         if(tsz <= 0) continue;
         long type = PositionGetInteger(POSITION_TYPE);
         double dist = (type == POSITION_TYPE_BUY) ? op - sl : sl - op;
         if(dist > 0) risk += dist / tsz * tvl * vol;   // SL beyond entry = locked profit, no risk
        }
      return risk;
     }

   bool              InNewsWindow(datetime now)
     {
      for(int i = 0; i < ArraySize(m_news); i++)
         if(now >= m_news[i] - m_s.newsMinutesBefore * 60 && now <= m_news[i] + m_s.newsMinutesAfter * 60)
            return true;
      return false;
     }

   bool              InSession(datetime now)
     {
      MqlDateTime d;
      TimeToStruct(now, d);
      if(d.day_of_week == 0 || d.day_of_week == 6) return false;
      if(m_s.blockFriday && d.day_of_week == 5 && d.hour >= m_s.fridayCutoffHour) return false;
      if(m_s.tradeStartHour == m_s.tradeEndHour) return true;
      if(m_s.tradeStartHour < m_s.tradeEndHour)
         return d.hour >= m_s.tradeStartHour && d.hour < m_s.tradeEndHour;
      return d.hour >= m_s.tradeStartHour || d.hour < m_s.tradeEndHour;   // overnight window
     }

   //--- consistency: share of total closed profit made on the best single day
   double            BestDayShare()
     {
      if(!HistorySelect(0, TimeCurrent() + 60)) return 0;
      datetime days[]; double pnl[];
      double total = 0;
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0) continue;
         long et = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if(et != DEAL_ENTRY_OUT && et != DEAL_ENTRY_INOUT && et != DEAL_ENTRY_OUT_BY) continue;
         if(m_s.magicFilter >= 0 && HistoryDealGetInteger(tk, DEAL_MAGIC) != m_s.magicFilter) continue;
         double p = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                    + HistoryDealGetDouble(tk, DEAL_COMMISSION);
         datetime d = DayStart((datetime)HistoryDealGetInteger(tk, DEAL_TIME));
         int k = -1;
         for(int j = 0; j < ArraySize(days); j++) if(days[j] == d) { k = j; break; }
         if(k < 0) { k = ArraySize(days); ArrayResize(days, k + 1); ArrayResize(pnl, k + 1); days[k] = d; pnl[k] = 0; }
         pnl[k] += p;
         total += p;
        }
      if(total <= 0) return 0;
      double best = 0;
      for(int j = 0; j < ArraySize(pnl); j++) best = MathMax(best, pnl[j]);
      return best / total * 100.0;
     }

   //--- close all guarded positions and delete guarded pending orders
   void              Flatten(const string why)
     {
      Print("[PropGuard] FLATTEN: ", why);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !OwnPosition()) continue;
         if(!m_trade.PositionClose(tk))
            Print("[PropGuard] close failed ", tk, " rc=", m_trade.ResultRetcode());
        }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0) continue;
         if(m_s.magicFilter >= 0 && OrderGetInteger(ORDER_MAGIC) != m_s.magicFilter) continue;
         m_trade.OrderDelete(tk);
        }
     }

   //--- call from OnTick (and OnTimer for quiet markets)
   void              Update()
     {
      datetime now = TimeCurrent();
      if(DayStart(now) != m_dayStart) NewDay();
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_peakEquity) { m_peakEquity = eq; SaveState(); }

      if(eq <= OverallFloor() + Buffer())
        { Flatten("overall drawdown"); Lock("max overall drawdown reached", true); return; }
      if(eq <= DailyFloor() + Buffer())
        { Flatten("daily loss"); Lock("daily loss limit reached", false); return; }
      if(m_s.stopAfterTarget && eq >= m_s.initialBalance * (1.0 + m_s.profitTargetPct / 100.0))
        { Flatten("profit target"); Lock("profit target reached", true); return; }
      if(m_s.flattenBeforeNews && InNewsWindow(now))
         Flatten("news window");
     }

   //--- ask before opening: riskMoney = loss at SL of the new order
   bool              CanOpen(double riskMoney = 0)
     {
      datetime now = TimeCurrent();
      if(m_lockedForever) return false;
      if(m_lockedToday)   return false;
      if(!InSession(now))  { m_reason = "outside trading window"; return false; }
      if(InNewsWindow(now)) { m_reason = "news window"; return false; }
      if(m_s.maxTradesPerDay > 0 && m_tradesToday >= m_s.maxTradesPerDay)
        { m_reason = "max trades per day"; return false; }
      bool unprot;
      double open = OpenRisk(unprot);
      if(unprot) { m_reason = "open position without SL"; return false; }
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(m_s.maxOpenRiskPct > 0 && open + riskMoney > bal * m_s.maxOpenRiskPct / 100.0)
        { m_reason = "max open risk"; return false; }
      // a full stop-out of everything must not breach daily / overall floors
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double worst = eq - open - riskMoney;
      if(worst <= DailyFloor() + Buffer())   { m_reason = "trade could breach daily limit"; return false; }
      if(worst <= OverallFloor() + Buffer()) { m_reason = "trade could breach max drawdown"; return false; }
      if(m_s.consistencyPct > 0 && BestDayShare() > m_s.consistencyPct)
        {
         // allowed to trade, but warn: more profit on other days is needed
         static datetime warned = 0;
         if(now - warned > 3600) { Print("[PropGuard] consistency: best day share above limit"); warned = now; }
        }
      m_reason = "";
      return true;
     }

   //--- call after a successful entry
   void              OnOpened() { m_tradesToday++; }

   //--- calculate money at risk for a planned order
   static double     RiskMoney(const string sym, ENUM_ORDER_TYPE type, double price, double sl, double lots)
     {
      if(sl <= 0) return DBL_MAX;
      double profit = 0;
      ENUM_ORDER_TYPE t = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
                          ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!OrderCalcProfit(t, sym, lots, price, sl, profit)) return DBL_MAX;
      return MathAbs(profit);
     }

   string            Status()
     {
      bool u;
      return StringFormat("PropGuard | eq %.2f | daily floor %.2f | overall floor %.2f | open risk %.2f | trades %d%s%s",
                          AccountInfoDouble(ACCOUNT_EQUITY), DailyFloor(), OverallFloor(), OpenRisk(u),
                          m_tradesToday, IsLocked() ? " | LOCKED: " : "", IsLocked() ? m_reason : "");
     }
  };

#endif // PROPGUARD_MQH
