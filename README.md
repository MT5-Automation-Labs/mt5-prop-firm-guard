# MT5 Prop Firm Guard

A reusable MQL5 include (`PropGuard.mqh`) that keeps any Expert Advisor inside typical prop-firm challenge rules, plus a demo EA that shows how to use it.

## Features
- **Daily loss limit** from the day's starting balance or max(balance, equity), reset at server midnight.
- **Max overall drawdown**, static (from initial balance) or trailing (from highest equity, capped at initial balance).
- **Safety buffer**: flatten slightly before the hard limit is reached.
- **Max open risk**: summed SL risk of open positions; positions without SL block new entries.
- **Pre-trade check**: a new order is refused if a stop-out of everything could breach the daily or overall limit.
- **Max trades per day**.
- **Time filters**: trading hours (overnight windows supported), weekend block, Friday cutoff.
- **News windows**: list of server times with minutes before/after; optional flatten during news.
- **Consistency rule** monitor (best-day share of total profit).
- **Profit target**: optional flatten and stop when reached.
- **Auto-flatten and block** on breach; state survives terminal restarts (terminal global variables).
- On-chart status line.

## Install
1. Copy `Include/PropGuard/` to `MQL5/Include/PropGuard/`.
2. Copy `Experts/PropGuardDemoEA.mq5` to `MQL5/Experts/`.
3. Compile in MetaEditor (F7) and attach the EA to a chart.

## Using it in your own EA
```mql5
#include <PropGuard/PropGuard.mqh>
CPropGuard guard;

int OnInit()
  {
   PropGuardSettings s;
   CPropGuard::Defaults(s);
   s.dailyLossPct = 5; s.maxDrawdownPct = 10;
   guard.Init(s);
   EventSetTimer(5);
   return INIT_SUCCEEDED;
  }
void OnTimer() { guard.Update(); }
void OnTick()
  {
   guard.Update();                       // flattens on breach
   double risk = CPropGuard::RiskMoney(_Symbol, ORDER_TYPE_BUY, ask, sl, lots);
   if(guard.CanOpen(risk)) { /* send order */ guard.OnOpened(); }
   else Print(guard.Reason());
  }
```

## Settings (PropGuardSettings / demo EA inputs)
| Field | Default | Meaning |
|---|---|---|
| `initialBalance` | 0 | Account size at start (0 = current balance, remembered afterwards) |
| `dailyLossPct` | 5.0 | Max loss per day, % of daily reference |
| `dailyFromEquity` | true | Daily reference = max(balance, equity) at day start |
| `maxDrawdownPct` | 10.0 | Max overall loss, % of initial balance |
| `ddMode` | static | `PG_DD_STATIC` or `PG_DD_TRAILING` |
| `maxOpenRiskPct` | 2.0 | Max summed SL risk, % of balance |
| `maxTradesPerDay` | 0 | 0 = unlimited |
| `safetyBufferPct` | 0.5 | Act this many % of initial balance before a limit |
| `tradeStartHour` / `tradeEndHour` | 0 / 0 | Server hours; equal = 24h |
| `blockFriday` / `fridayCutoffHour` | false / 20 | Stop new trades late Friday |
| `newsTimes` | "" | `yyyy.mm.dd hh:mi` entries separated by `;` (server time) |
| `newsMinutesBefore` / `After` | 5 / 5 | Blocked window around each event |
| `flattenBeforeNews` | false | Close positions during news windows |
| `consistencyPct` | 0 | Warn when best day > this % of total profit (0 = off) |
| `magicFilter` | -1 | Guard only one magic number (-1 = whole account) |
| `stopAfterTarget` / `profitTargetPct` | false / 8 | Flatten and stop at target |

## Example presets (generic 2-step challenge)
These reflect common industry values only. Always check your own firm's current rules; they differ and change.

| Preset | Daily loss | Max DD | DD mode | Target | Other |
|---|---|---|---|---|---|
| Phase 1 | 5% | 10% | static | 8–10% | buffer 0.5–1%, max open risk 2% |
| Phase 2 | 5% | 10% | static | 5% | same as phase 1 |
| Funded | 5% | 10% | static | off | news filter on, Friday cutoff on |
| Conservative / trailing-DD style | 4% | 6% | trailing | 6% | buffer 1%, max 3 trades/day |

## Notes
- Limits are checked on every tick and on a 5 s timer. Fast markets and gaps can still move equity past a limit before positions close; the buffer exists for this reason.
- Daily reset uses broker server midnight. If your firm resets at a different time, adjust accordingly.

## Disclaimer

Trading forex, metals, indices and CFDs on margin carries a high level of risk and can result in losses greater than your deposit. This software is provided for educational purposes, without any warranty, and is not financial advice. Past or backtested performance does not guarantee future results. Always test on a demo account first and use it at your own risk.

## License
MIT © 2026 StanleyDaniels
