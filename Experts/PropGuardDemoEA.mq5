//+------------------------------------------------------------------+
//| PropGuardDemoEA.mq5 - shows how to wire CPropGuard into an EA    |
//| Strategy is a simple Donchian breakout for demonstration only.   |
//| MIT License, Copyright (c) 2026 StanleyDaniels                   |
//+------------------------------------------------------------------+
#property copyright "Copyright (c) 2026 StanleyDaniels"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <PropGuard/PropGuard.mqh>

input group "=== Challenge rules ==="
input double          InpInitialBalance   = 0;      // Initial balance (0 = current)
input double          InpDailyLossPct     = 5.0;    // Max daily loss %
input bool            InpDailyFromEquity  = true;   // Daily reference uses max(balance,equity)
input double          InpMaxDrawdownPct   = 10.0;   // Max overall drawdown %
input ENUM_PG_DD_MODE InpDDMode           = PG_DD_STATIC; // Drawdown mode
input double          InpProfitTargetPct  = 8.0;    // Profit target %
input bool            InpStopAtTarget     = true;   // Flatten and stop at target
input double          InpConsistencyPct   = 0;      // Best-day share limit % (0 = off)
input group "=== Risk controls ==="
input double          InpMaxOpenRiskPct   = 2.0;    // Max open risk %
input int             InpMaxTradesPerDay  = 5;      // Max trades per day (0 = off)
input double          InpBufferPct        = 0.5;    // Safety buffer % before limits
input group "=== Time filters (server time) ==="
input int             InpStartHour        = 8;      // Trading start hour
input int             InpEndHour          = 20;     // Trading end hour
input bool            InpBlockFriday      = true;   // Stop Friday afternoon
input int             InpFridayCutoff     = 18;     // Friday cutoff hour
input string          InpNews             = "";     // News times "yyyy.mm.dd hh:mi;..."
input int             InpNewsBefore       = 10;     // Minutes before news
input int             InpNewsAfter        = 10;     // Minutes after news
input bool            InpFlattenNews      = false;  // Close positions in news window
input group "=== Demo strategy ==="
input ENUM_TIMEFRAMES InpTF               = PERIOD_H1;
input int             InpChannel          = 20;     // Donchian lookback bars
input double          InpRiskPct          = 0.5;    // Risk per trade %
input double          InpRR               = 2.0;    // Reward:risk
input long            InpMagic            = 7701;   // Magic number

CPropGuard g_guard;
CTrade     g_trade;
datetime   g_lastBar = 0;

int OnInit()
  {
   PropGuardSettings s;
   CPropGuard::Defaults(s);
   s.initialBalance    = InpInitialBalance;
   s.dailyLossPct      = InpDailyLossPct;
   s.dailyFromEquity   = InpDailyFromEquity;
   s.maxDrawdownPct    = InpMaxDrawdownPct;
   s.ddMode            = InpDDMode;
   s.maxOpenRiskPct    = InpMaxOpenRiskPct;
   s.maxTradesPerDay   = InpMaxTradesPerDay;
   s.safetyBufferPct   = InpBufferPct;
   s.tradeStartHour    = InpStartHour;
   s.tradeEndHour      = InpEndHour;
   s.blockFriday       = InpBlockFriday;
   s.fridayCutoffHour  = InpFridayCutoff;
   s.newsTimes         = InpNews;
   s.newsMinutesBefore = InpNewsBefore;
   s.newsMinutesAfter  = InpNewsAfter;
   s.flattenBeforeNews = InpFlattenNews;
   s.consistencyPct    = InpConsistencyPct;
   s.magicFilter       = -1;              // guard the whole account
   s.stopAfterTarget   = InpStopAtTarget;
   s.profitTargetPct   = InpProfitTargetPct;
   if(!g_guard.Init(s)) return INIT_FAILED;
   g_trade.SetExpertMagicNumber(InpMagic);
   EventSetTimer(5);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }

void OnTimer() { g_guard.Update(); Comment(g_guard.Status()); }

double LotsForRisk(double entry, double sl)
  {
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   double tsz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tvl = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double dist = MathAbs(entry - sl);
   if(tsz <= 0 || tvl <= 0 || dist <= 0 || step <= 0) return 0;
   double lots = MathFloor(riskMoney / (dist / tsz * tvl) / step) * step;
   if(lots < vmin) return 0;
   return MathMin(lots, vmax);
  }

bool HasPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
     }
   return false;
  }

void OnTick()
  {
   g_guard.Update();
   Comment(g_guard.Status());

   datetime bar = iTime(_Symbol, InpTF, 0);
   if(bar == g_lastBar) return;
   g_lastBar = bar;
   if(HasPosition()) return;

   int hi = iHighest(_Symbol, InpTF, MODE_HIGH, InpChannel, 2);
   int lo = iLowest(_Symbol, InpTF, MODE_LOW, InpChannel, 2);
   if(hi < 0 || lo < 0) return;
   double upper = iHigh(_Symbol, InpTF, hi);
   double lower = iLow(_Symbol, InpTF, lo);
   double close1 = iClose(_Symbol, InpTF, 1);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   ENUM_ORDER_TYPE type;
   double price, sl, tp;
   if(close1 > upper)      { type = ORDER_TYPE_BUY;  price = ask; sl = lower; tp = price + (price - sl) * InpRR; }
   else if(close1 < lower) { type = ORDER_TYPE_SELL; price = bid; sl = upper; tp = price - (sl - price) * InpRR; }
   else return;

   sl = NormalizeDouble(sl, dg);
   tp = NormalizeDouble(tp, dg);
   double lots = LotsForRisk(price, sl);
   if(lots <= 0) return;

   double risk = CPropGuard::RiskMoney(_Symbol, type, price, sl, lots);
   if(!g_guard.CanOpen(risk))
     {
      Print("Entry blocked by PropGuard: ", g_guard.Reason());
      return;
     }
   bool ok = (type == ORDER_TYPE_BUY) ? g_trade.Buy(lots, _Symbol, price, sl, tp, "pg-demo")
                                      : g_trade.Sell(lots, _Symbol, price, sl, tp, "pg-demo");
   if(ok && (g_trade.ResultRetcode() == TRADE_RETCODE_DONE || g_trade.ResultRetcode() == TRADE_RETCODE_PLACED))
      g_guard.OnOpened();
  }
