import { describe, expect, it } from 'vitest';
import { periodOf, upcomingPeriod } from './dates';
import { holidayOn } from './holidays';
import {
  type Data, type Day, DEFAULT_SETTINGS, computeHours, currentRate, estimate, pendingRaise, rateFor,
  federalTax, sickLedger, stubTotals, tuitionExpected, tuitionOwed, tuitionQuestions,
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

describe('federal withholding', () => {
  it('follows the 2026 semi-monthly brackets', () => {
    expect(federalTax(600)).toBe(0);
    expect(federalTax(1000)).toBeCloseTo(0.10 * (1000 - 670.83));
    // all of the 10% band, then 12%
    expect(federalTax(2000)).toBeCloseTo(51.667 + 0.12 * (2000 - 1187.5), 2);
    // into the 22% band: a flat 12% would say 0.12 * (4000 - 757) = 389.16
    expect(federalTax(4000)).toBeCloseTo(51.667 + 190.0 + 0.22 * (4000 - 2770.83), 2);
  });
});

describe('stubs', () => {
  it('rounds OT as straight + premium lines and includes sick pay in gross', () => {
    const s = { periodStart: '2026-08-01', periodEnd: '2026-08-15', payDate: '2026-08-20', regHours: 10, otHours: 1.01,
      holHours: 0, sickHours: 2, ccTips: 5, bonus: 51, reimbursement: 7, tax: 20, taxIsEstimate: false, cashTips: 0 };
    const P = stubTotals(s, 13.5);
    // 1.01 * 13.5 = 13.635 -> 13.64, premium 6.8175 -> 6.82; one line would give 20.45
    expect(P.otPay).toBe(20.46);
    expect(P.sickPay).toBe(27);
    expect(P.gross).toBe(135 + 20.46 + 27 + 5 + 51);
    expect(P.net).toBe(P.gross - 20 + 7);
  });
});

describe('holidays', () => {
  it('knows the six holidays and moves weekend ones to the nearest weekday', () => {
    expect(holidayOn('2026-01-01')).toBe("New Year's Day");
    expect(holidayOn('2026-05-25')).toBe('Memorial Day');
    expect(holidayOn('2026-09-07')).toBe('Labor Day');
    expect(holidayOn('2026-11-26')).toBe('Thanksgiving');
    expect(holidayOn('2026-12-25')).toBe('Christmas');
    // Sat Jul 4 2026 is observed Fri Jul 3
    expect(holidayOn('2026-07-03')).toBe('Independence Day');
    expect(holidayOn('2026-07-04')).toBeNull();
    // Sun Dec 25 2022 is observed Mon Dec 26
    expect(holidayOn('2022-12-26')).toBe('Christmas');
    expect(holidayOn('2022-12-25')).toBeNull();
    // Sat Jan 1 2028 is observed Fri Dec 31 2027
    expect(holidayOn('2027-12-31')).toBe("New Year's Day");
    expect(holidayOn('2026-11-11')).toBeNull();
    expect(holidayOn('2026-11-27')).toBeNull();
  });

  const sum = (c: ReturnType<typeof computeHours>, k: 'reg' | 'ot' | 'hol') => Object.values(c).reduce((a, x) => a + x[k], 0);
  const total = (date: string, h: number) => day(date, { mode: 'total', totalHours: h });

  it('pays holiday hours at 1.5x, counting them toward 40 without stacking', () => {
    // Sat Nov 21 .. Fri Nov 27 2026. 36h Mon-Wed, 8h on Thanksgiving, 8h Friday.
    const days = [total('2026-11-23', 12), total('2026-11-24', 12), total('2026-11-25', 12),
      total('2026-11-26', 8), total('2026-11-27', 8)];
    const c = computeHours(days);
    expect(sum(c, 'reg')).toBeCloseTo(36);
    // the 4 holiday hours past 40 stay holiday, not 2.25x
    expect(sum(c, 'hol')).toBeCloseTo(8);
    expect(sum(c, 'ot')).toBeCloseTo(8);
  });
  it('lets a holiday early in the week push later days into overtime', () => {
    // Labor Day Mon Sep 7 2026, then 9h Tue-Fri: 44h, 4 of them OT on Friday
    const days = [total('2026-09-07', 8), ...['08', '09', '10', '11'].map(d => total(`2026-09-${d}`, 9))];
    const c = computeHours(days);
    expect(sum(c, 'hol')).toBeCloseTo(8);
    expect(sum(c, 'ot')).toBeCloseTo(4);
    expect(sum(c, 'reg')).toBeCloseTo(32);
  });
  it('puts holiday pay in the estimate and taxes it like wages', () => {
    const d = data({ days: [total('2026-11-26', 8), total('2026-11-25', 8)] });
    const T = estimate(d, periodOf('2026-11-26'), '2026-11-27').totals;
    expect(T.hol).toBeCloseTo(8);
    expect(T.holPay).toBeCloseTo(8 * 20 * 1.5);
    expect(T.waBase).toBeCloseTo(8 * 20 + 240);
    expect(T.hrs).toBeCloseTo(16);
  });
  it('adds holiday hours from a stub to its gross and hours', () => {
    const s = { periodStart: '2026-11-16', periodEnd: '2026-11-30', payDate: '2026-12-04', regHours: 60, otHours: 0,
      holHours: 8, sickHours: 0, ccTips: 0, bonus: 0, reimbursement: 0, tax: 0, taxIsEstimate: false, cashTips: 0 };
    const P = stubTotals(s, 13.5);
    expect(P.holPay).toBe(162);
    expect(P.gross).toBe(810 + 162);
    expect(P.hours).toBe(68);
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
