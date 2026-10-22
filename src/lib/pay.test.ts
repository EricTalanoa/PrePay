import { describe, expect, it } from 'vitest';
import { periodOf, upcomingPeriod } from './dates';
import {
  type Data, type Day, DEFAULT_SETTINGS, computeHours, currentRate, estimate, pendingRaise, rateFor,
  sickLedger, tuitionExpected, tuitionOwed, tuitionQuestions,
} from './pay';
import { computeStats } from './stats';

let n = 0;
const day = (date: string, p: Partial<Day> = {}): Day => ({
  id: 'd' + n++, date, mode: 'range', startMin: 480, endMin: 990, totalHours: null, lunch: true,
  ccTips: 0, cashTips: 0, travel: 'none', miles: 0, ...p,
});
const data = (p: Partial<Data> = {}): Data => ({
  days: [], stubs: [], rates: [{ effectiveFrom: '2000-01-01', rate: 20 }], cashouts: [], tuition: [],
  settings: { ...DEFAULT_SETTINGS, sickAsOf: '2026-01-01' }, ...p,
});

describe('periods', () => {
  it('splits the month at the 15th and moves weekend pay dates to Friday', () => {
    expect(periodOf('2026-08-15')).toEqual({ key: '2026-08-01', from: '2026-08-01', to: '2026-08-15', payDate: '2026-08-20' });
    // Sep 5 2026 is a Saturday
    expect(periodOf('2026-08-31').payDate).toBe('2026-09-04');
  });
  it('rolls to the next check at 7 AM on pay day', () => {
    expect(upcomingPeriod(new Date(2026, 7, 20, 6, 59)).key).toBe('2026-08-01');
    expect(upcomingPeriod(new Date(2026, 7, 20, 7, 0)).key).toBe('2026-08-16');
  });
});

describe('hours and pay', () => {
  it('counts overtime past 40 in a Saturday–Friday week', () => {
    // Sat Aug 1 .. Fri Aug 7: six 8h days = 48h
    const days = ['01', '02', '03', '04', '05', '06'].map(d => day(`2026-08-${d}`));
    const c = computeHours(days);
    const ot = Object.values(c).reduce((a, x) => a + x.ot, 0);
    expect(ot).toBeCloseTo(8);
  });
  it('pays per-diem at 51/75 and taxes it like wages', () => {
    const d = data({ days: [day('2026-08-03', { travel: 'partial' }), day('2026-08-04', { travel: 'full' })] });
    const e = estimate(d, periodOf('2026-08-03'), '2026-08-10');
    expect(e.totals.perDiem).toBe(126);
    expect(e.totals.waBase).toBeCloseTo(16 * 20 + 126);
    expect(e.totals.taxLines['Washington FLI']).toBeCloseTo((16 * 20 + 126) * 0.005433);
  });
});

describe('raises', () => {
  const rates = [{ effectiveFrom: '2000-01-01', rate: 20 }, { effectiveFrom: '2026-09-01', rate: 22 }];
  it('is pending until its date, then becomes the base rate', () => {
    expect(currentRate(rates, '2026-08-20')!.rate).toBe(20);
    expect(pendingRaise(rates, '2026-08-20')!.rate).toBe(22);
    expect(currentRate(rates, '2026-09-01')!.rate).toBe(22);
    expect(pendingRaise(rates, '2026-09-01')).toBeNull();
  });
  it('keeps the old rate for periods before the raise', () => {
    expect(rateFor(rates, '2026-08-31')).toBe(20);
    expect(rateFor(rates, '2026-09-02')).toBe(22);
  });
});

describe('sick hours', () => {
  it('adds accrual on each paid check and removes cash-outs', () => {
    const days = Array.from({ length: 10 }, (_, i) => day(`2026-08-${String(i + 3).padStart(2, '0')}`));
    const d = data({ days, settings: { ...DEFAULT_SETTINGS, sickBalance: 10, sickAsOf: '2026-08-01' } });
    // 80h in Aug 1–15 → 2h, credited when it pays on the 20th
    expect(sickLedger(d, '2026-08-19').available).toBe(10);
    expect(sickLedger(d, '2026-08-20').available).toBe(12);
    d.cashouts = [{ periodStart: '2026-08-16', hours: 5 }];
    expect(sickLedger(d, '2026-08-20').available).toBe(7);
  });
});

describe('tuition', () => {
  const base = () => data({
    days: [day('2026-06-20'), day('2026-07-02'), day('2026-07-20'), day('2026-08-03'), day('2026-08-20')],
    tuition: [{ periodStart: '2026-06-16', status: 'received', amount: 50 }],
  });
  it('expects it every other check', () => {
    const d = base();
    expect(tuitionExpected(d, periodOf('2026-07-01'), '2026-07-01')).toBe(false);
    expect(tuitionExpected(d, periodOf('2026-07-16'), '2026-07-01')).toBe(true);
  });
  it('moves a missed one to the next check', () => {
    const d = base();
    d.tuition.push({ periodStart: '2026-07-16', status: 'missed', amount: 0 });
    expect(tuitionExpected(d, periodOf('2026-08-01'), '2026-08-10')).toBe(true);
    expect(tuitionExpected(d, periodOf('2026-08-16'), '2026-08-10')).toBe(false);
  });
  it('treats an unanswered expected check as missed and asks about it', () => {
    const d = base();
    expect(tuitionQuestions(d, '2026-08-06').map(p => p.key)).toEqual(['2026-07-16']);
    expect(tuitionExpected(d, periodOf('2026-08-01'), '2026-08-06')).toBe(true);
  });
  it('restarts the cadence from a check it came on unexpectedly', () => {
    const d = base();
    d.tuition.push({ periodStart: '2026-07-01', status: 'received', amount: 10 });
    expect(tuitionExpected(d, periodOf('2026-07-16'), '2026-07-10')).toBe(false);
    expect(tuitionExpected(d, periodOf('2026-08-01'), '2026-07-10')).toBe(true);
  });
  it('owes hours from the last paid period up to the one before', () => {
    const d = base();
    const o = tuitionOwed(d, periodOf('2026-08-01'));
    expect(o.periods.map(p => p.key)).toEqual(['2026-06-16', '2026-07-01', '2026-07-16']);
    expect(o.amount).toBe(24);
  });
});

describe('stats', () => {
  it('finds extremes and streaks', () => {
    const days = [
      day('2026-08-01', { ccTips: 50 }), day('2026-08-02', { cashTips: 30 }), day('2026-08-03', { endMin: 1200 }),
      day('2026-08-10', { mode: 'total', totalHours: 2 }),
    ];
    const s = computeStats(days, [{ effectiveFrom: '2000-01-01', rate: 20 }], '2026-08-11');
    expect(s.longestStreak).toEqual({ from: '2026-08-01', to: '2026-08-03', days: 3 });
    expect(s.longestBreak).toEqual({ from: '2026-08-04', to: '2026-08-09', days: 6 });
    expect(s.longestDay!.date).toBe('2026-08-03');
    expect(s.shortestDay!.date).toBe('2026-08-10');
    expect(s.mostCcTips!.value).toBe(50);
    expect(s.mostCash!.date).toBe('2026-08-02');
    expect(s.highestDay!.date).toBe('2026-08-03');
    expect(s.currentStreak).toBe(1);
  });
});
