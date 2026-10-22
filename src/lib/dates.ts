// Calendar helpers. Dates travel as local 'YYYY-MM-DD' strings so that string
// comparison is date comparison and nothing shifts across time zones.

export type ISODate = string;

export const pad = (n: number) => String(n).padStart(2, '0');

export function iso(d: Date): ISODate {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function dparse(s: ISODate): Date {
  const p = s.split('-');
  return new Date(+p[0], +p[1] - 1, +p[2]);
}

export function addDays(s: ISODate, n: number): ISODate {
  const d = dparse(s);
  d.setDate(d.getDate() + n);
  return iso(d);
}

export function daysBetween(a: ISODate, b: ISODate): number {
  return Math.round((dparse(b).getTime() - dparse(a).getTime()) / 86400000);
}

export function todayIso(now = new Date()): ISODate {
  return iso(now);
}

// Overtime is counted in Saturday–Friday weeks.
export function weekStart(s: ISODate): ISODate {
  const d = dparse(s);
  d.setDate(d.getDate() - ((d.getDay() + 1) % 7));
  return iso(d);
}

// A pay date that falls on a weekend moves back to the Friday before.
function adjust(d: Date): Date {
  const x = new Date(d);
  if (x.getDay() === 6) x.setDate(x.getDate() - 1);
  if (x.getDay() === 0) x.setDate(x.getDate() - 2);
  return x;
}

export interface Period {
  key: ISODate; // first day of the period; also its id
  from: ISODate;
  to: ISODate;
  payDate: ISODate;
}

// 1st–15th pays on the 20th; 16th–end of month pays on the 5th of the next.
export function periodOf(s: ISODate): Period {
  const d = dparse(s), y = d.getFullYear(), m = d.getMonth();
  if (d.getDate() <= 15) {
    const from = iso(new Date(y, m, 1));
    return { key: from, from, to: iso(new Date(y, m, 15)), payDate: iso(adjust(new Date(y, m, 20))) };
  }
  const from = iso(new Date(y, m, 16));
  return { key: from, from, to: iso(new Date(y, m + 1, 0)), payDate: iso(adjust(new Date(y, m + 1, 5))) };
}

export const nextPeriod = (p: Period): Period => periodOf(addDays(p.to, 1));
export const prevPeriod = (p: Period): Period => periodOf(addDays(p.from, -1));

export function shiftPeriod(p: Period, n: number): Period {
  let q = p;
  for (let i = 0; i < Math.abs(n); i++) q = n > 0 ? nextPeriod(q) : prevPeriod(q);
  return q;
}

// The check that is coming next. On the pay date itself the money lands at
// 7 AM, so after that the next check is the one after.
export function upcomingPeriod(now = new Date()): Period {
  const today = iso(now);
  const past7 = now.getHours() >= 7;
  let p = prevPeriod(prevPeriod(periodOf(today)));
  while (past7 ? p.payDate <= today : p.payDate < today) p = nextPeriod(p);
  return p;
}

export function nowMinutes(now = new Date()): number {
  return now.getHours() * 60 + now.getMinutes();
}

export function fmtTime(m: number): string {
  const h = Math.floor(m / 60), mi = m % 60;
  const hh = h % 12 === 0 ? 12 : h % 12;
  return `${hh}:${pad(mi)} ${h < 12 ? 'AM' : 'PM'}`;
}

export const fmtMD = (s: ISODate) => dparse(s).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
export const fmtFull = (s: ISODate) =>
  dparse(s).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
export const fmtRange = (p: Period) => `${fmtMD(p.from)} – ${fmtMD(p.to)}`.toUpperCase();
