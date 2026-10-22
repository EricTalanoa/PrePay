import type { ReactNode } from 'react';
import { addDays, fmtFull, fmtMD, todayIso } from '../lib/dates';
import { type Data, money } from '../lib/pay';
import { type DayStat, type Run, computeStats } from '../lib/stats';

function Stat({ label, value, sub, wide }: { label: string; value: ReactNode; sub?: ReactNode; wide?: boolean }) {
  return (
    <div className={'stat' + (wide ? ' wide' : '')}>
      <div className="label">{label}</div>
      <div className="v">{value}</div>
      {sub && <div className="s">{sub}</div>}
    </div>
  );
}

const h = (x: number) => `${+x.toFixed(2)}h`;
const on = (x: DayStat | null) => (x ? fmtFull(x.date) : '—');
const run = (r: Run | null) => (r ? (r.days === 1 ? fmtMD(r.from) : `${fmtMD(r.from)} – ${fmtMD(r.to)}`) : '—');
const days = (n: number) => `${n} day${n === 1 ? '' : 's'}`;

export function StatsView({ data }: { data: Data }) {
  const s = computeStats(data.days, data.rates, todayIso());
  if (!s.daysWorked) return <div className="pad" style={{ marginTop: 28 }}><div className="empty">Log a few days and the stats show up here.</div></div>;
  return (
    <div style={{ padding: '20px 24px 0', display: 'flex', flexDirection: 'column', gap: 18 }}>
      <div className="stats">
        <Stat label="Highest earning day" value={s.highestDay ? money(s.highestDay.value) : '—'} sub={on(s.highestDay)} />
        <Stat label="Lowest earning day" value={s.lowestDay ? money(s.lowestDay.value) : '—'} sub={on(s.lowestDay)} />
        <Stat label="Longest day" value={s.longestDay ? h(s.longestDay.value) : '—'} sub={on(s.longestDay)} />
        <Stat label="Shortest day" value={s.shortestDay ? h(s.shortestDay.value) : '—'} sub={on(s.shortestDay)} />
        <Stat label="Most cash in a day" value={s.mostCash ? money(s.mostCash.value) : '—'} sub={on(s.mostCash)} />
        <Stat label="Most CC tips in a day" value={s.mostCcTips ? money(s.mostCcTips.value) : '—'} sub={on(s.mostCcTips)} />
        <Stat label="Most days in a row" value={s.longestStreak ? days(s.longestStreak.days) : '—'} sub={run(s.longestStreak)} />
        <Stat label="Most days off in a row" value={s.longestBreak ? days(s.longestBreak.days) : '—'} sub={run(s.longestBreak)} />
        <Stat label="Current streak" value={days(s.currentStreak)} sub={s.currentStreak ? `since ${fmtMD(addDays(todayIso(), -(s.currentStreak - 1)))}` : 'not working today'} />
        <Stat label="Best week" value={s.bestWeek ? money(s.bestWeek.value) : '—'} sub={s.bestWeek ? `week of ${fmtMD(s.bestWeek.date)}` : undefined} />
        <Stat label="Earliest clock-in" value={s.earliestStart?.label ?? '—'} sub={s.earliestStart ? fmtFull(s.earliestStart.date) : undefined} />
        <Stat label="Latest clock-out" value={s.latestEnd?.label ?? '—'} sub={s.latestEnd ? fmtFull(s.latestEnd.date) : undefined} />
        <Stat label="Most miles in a day" value={s.mostMiles ? `${s.mostMiles.value} mi` : '—'} sub={on(s.mostMiles)} />
        <Stat label="Busiest weekday" value={s.busiestWeekday?.name ?? '—'} sub={s.busiestWeekday ? days(s.busiestWeekday.count) + ' worked' : undefined} />
      </div>

      <div className="label">All time</div>
      <div className="stats">
        <Stat label="Days worked" value={s.daysWorked} sub={`${h(s.totalHours)} total`} />
        <Stat label="Avg per hour" value={money(s.avgHourly)} sub="wages + all tips" />
        <Stat label="Earned" value={money(s.totalEarned)} sub="wages + all tips, before tax" wide />
        <Stat label="CC tips" value={money(s.totalCcTips)} />
        <Stat label="Cash tips" value={money(s.totalCash)} />
        <Stat label="Per-diem" value={money(s.totalPerDiem)} sub={`${days(s.travelDays)} on the road`} />
        <Stat label="POV miles" value={`${+s.totalMiles.toFixed(2)} mi`} />
      </div>
    </div>
  );
}
