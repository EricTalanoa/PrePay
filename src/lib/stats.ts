import { type ISODate, addDays, daysBetween, dparse, fmtTime, weekStart } from './dates';
import { type Day, type Rate, OT_MULT, computeHours, num, perDiemFor, rateFor } from './pay';

export interface DayStat { date: ISODate; value: number }
export interface Run { from: ISODate; to: ISODate; days: number }

export interface Stats {
  daysWorked: number;
  totalHours: number;
  totalEarned: number; // wages + CC tips + cash tips
  totalCcTips: number;
  totalCash: number;
  totalPerDiem: number;
  totalMiles: number;
  travelDays: number;
  avgHourly: number; // everything earned / hours worked
  highestDay: DayStat | null;
  lowestDay: DayStat | null;
  longestDay: DayStat | null;
  shortestDay: DayStat | null;
  mostCash: DayStat | null;
  mostCcTips: DayStat | null;
  mostMiles: DayStat | null;
  bestWeek: DayStat | null; // date = the Saturday it starts on
  longestStreak: Run | null;
  longestBreak: Run | null;
  currentStreak: number;
  earliestStart: { date: ISODate; label: string } | null;
  latestEnd: { date: ISODate; label: string } | null;
  busiestWeekday: { name: string; count: number } | null;
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function pick(xs: DayStat[], better: (a: number, b: number) => boolean): DayStat | null {
  let best: DayStat | null = null;
  for (const x of xs) if (!best || better(x.value, best.value)) best = x;
  return best;
}

// Several entries on one date (a split shift) count as one day.
export function computeStats(days: Day[], rates: Rate[], today: ISODate): Stats {
  const calc = computeHours(days);
  const byDate = new Map<ISODate, { hours: number; earned: number; cash: number; cc: number; miles: number }>();
  let totalPerDiem = 0, travelDays = 0;
  let earliestStart: Stats['earliestStart'] = null, latestEnd: Stats['latestEnd'] = null;
  let earliestMin = Infinity, latestMin = -Infinity;
  const weekday = new Array(7).fill(0);

  for (const d of days) {
    const c = calc[d.id];
    const rate = rateFor(rates, d.date);
    const wages = c.reg * rate + c.ot * rate * OT_MULT;
    const e = byDate.get(d.date) ?? { hours: 0, earned: 0, cash: 0, cc: 0, miles: 0 };
    e.hours += c.hours;
    e.earned += wages + num(d.ccTips) + num(d.cashTips);
    e.cash += num(d.cashTips);
    e.cc += num(d.ccTips);
    e.miles += num(d.miles);
    if (!byDate.has(d.date)) weekday[dparse(d.date).getDay()]++;
    byDate.set(d.date, e);
    totalPerDiem += perDiemFor(d);
    if (d.travel !== 'none') travelDays++;
    if (d.mode === 'range') {
      if (d.startMin < earliestMin) { earliestMin = d.startMin; earliestStart = { date: d.date, label: fmtTime(d.startMin) }; }
      // a shift past midnight ends "later" than any same-day clock-out
      const end = d.endMin < d.startMin ? d.endMin + 1440 : d.endMin;
      if (end > latestMin) { latestMin = end; latestEnd = { date: d.date, label: fmtTime(d.endMin) }; }
    }
  }

  const dates = [...byDate.keys()].sort();
  const worked = dates.filter(k => byDate.get(k)!.hours > 0);
  const stat = (f: (e: NonNullable<ReturnType<typeof byDate.get>>) => number, from = worked) =>
    from.map(k => ({ date: k, value: f(byDate.get(k)!) }));

  const earned = stat(e => e.earned);
  const hours = stat(e => e.hours);
  const nonzero = (xs: DayStat[]) => xs.filter(x => x.value > 0);

  const weeks = new Map<ISODate, number>();
  for (const k of dates) weeks.set(weekStart(k), (weeks.get(weekStart(k)) ?? 0) + byDate.get(k)!.earned);

  // runs of consecutive calendar days worked, and the gaps between them
  let longestStreak: Run | null = null, longestBreak: Run | null = null;
  let runStart: ISODate | null = null, prev: ISODate | null = null;
  const closeRun = (end: ISODate) => {
    const n = daysBetween(runStart!, end) + 1;
    if (!longestStreak || n > longestStreak.days) longestStreak = { from: runStart!, to: end, days: n };
  };
  for (const k of worked) {
    if (prev && daysBetween(prev, k) === 1) { prev = k; continue; }
    if (prev) {
      closeRun(prev);
      const gap = daysBetween(prev, k) - 1;
      if (!longestBreak || gap > longestBreak.days) longestBreak = { from: addDays(prev, 1), to: addDays(k, -1), days: gap };
    }
    runStart = k; prev = k;
  }
  if (prev) closeRun(prev);

  // the streak still going: counts today, or yesterday if today isn't logged yet
  let currentStreak = 0;
  const set = new Set(worked);
  let cur = set.has(today) ? today : addDays(today, -1);
  while (set.has(cur)) { currentStreak++; cur = addDays(cur, -1); }

  const totalHours = hours.reduce((a, x) => a + x.value, 0);
  const totalEarned = earned.reduce((a, x) => a + x.value, 0);
  const max = weekday.reduce((a, b) => Math.max(a, b), 0);

  return {
    daysWorked: worked.length,
    totalHours,
    totalEarned,
    totalCcTips: dates.reduce((a, k) => a + byDate.get(k)!.cc, 0),
    totalCash: dates.reduce((a, k) => a + byDate.get(k)!.cash, 0),
    totalPerDiem,
    totalMiles: dates.reduce((a, k) => a + byDate.get(k)!.miles, 0),
    travelDays,
    avgHourly: totalHours > 0 ? totalEarned / totalHours : 0,
    highestDay: pick(earned, (a, b) => a > b),
    lowestDay: pick(earned, (a, b) => a < b),
    longestDay: pick(hours, (a, b) => a > b),
    shortestDay: pick(hours, (a, b) => a < b),
    mostCash: pick(nonzero(stat(e => e.cash)), (a, b) => a > b),
    mostCcTips: pick(nonzero(stat(e => e.cc)), (a, b) => a > b),
    mostMiles: pick(nonzero(stat(e => e.miles)), (a, b) => a > b),
    bestWeek: pick([...weeks].map(([date, value]) => ({ date, value })), (a, b) => a > b),
    longestStreak, longestBreak, currentStreak,
    earliestStart, latestEnd,
    busiestWeekday: max > 0 ? { name: WEEKDAYS[weekday.indexOf(max)], count: max } : null,
  };
}
