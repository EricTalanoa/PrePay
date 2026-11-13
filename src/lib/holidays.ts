import { type ISODate, dparse, iso } from './dates';

// Paid holidays: hours worked on one are paid at time and a half (HOL_MULT in
// pay.ts). Nothing is paid for a holiday not worked; the Sep 2026 stub showed
// no hours for Labor Day off.
//
// A holiday on a Saturday is observed the Friday before, one on a Sunday the
// Monday after, and only the observed day earns the premium.

export const HOLIDAYS: { name: string; on: (y: number) => Date }[] = [
  { name: "New Year's Day", on: y => new Date(y, 0, 1) },
  { name: 'Memorial Day', on: y => lastWeekday(y, 4, 1) },
  { name: 'Independence Day', on: y => new Date(y, 6, 4) },
  { name: 'Labor Day', on: y => nthWeekday(y, 8, 1, 1) },
  { name: 'Veterans Day', on: y => new Date(y, 10, 11) },
  { name: 'Thanksgiving', on: y => nthWeekday(y, 10, 4, 4) },
  { name: 'Christmas', on: y => new Date(y, 11, 25) },
];

// month is 0-based, weekday 0 = Sunday
function nthWeekday(y: number, month: number, weekday: number, n: number): Date {
  const first = new Date(y, month, 1).getDay();
  return new Date(y, month, 1 + ((weekday - first + 7) % 7) + (n - 1) * 7);
}

function lastWeekday(y: number, month: number, weekday: number): Date {
  const last = new Date(y, month + 1, 0);
  return new Date(y, month, last.getDate() - ((last.getDay() - weekday + 7) % 7));
}

function observed(d: Date): Date {
  const x = new Date(d);
  if (x.getDay() === 6) x.setDate(x.getDate() - 1);
  if (x.getDay() === 0) x.setDate(x.getDate() + 1);
  return x;
}

// The holiday observed on this date, if any. Next year's list is checked too:
// a Saturday New Year's Day is observed on Dec 31.
export function holidayOn(date: ISODate): string | null {
  const y = dparse(date).getFullYear();
  for (const yr of [y, y + 1]) {
    for (const h of HOLIDAYS) if (iso(observed(h.on(yr))) === date) return h.name;
  }
  return null;
}
