import { describe, expect, it } from 'vitest';
import { fromLegacy, latestDay, mergeData, parseBackup, toBackup } from './backup';
import { type Data, DEFAULT_SETTINGS } from './pay';

const account = (): Data => ({
  days: [
    { id: 'a1', date: '2026-08-16', mode: 'range', startMin: 465, endMin: 844, totalHours: null, lunch: false, ccTips: 33.33, cashTips: 0, travel: 'none', miles: 0 },
  ],
  stubs: [
    { periodStart: '2026-08-16', periodEnd: '2026-08-31', payDate: '2026-09-04', regHours: 77.76, otHours: 0, ccTips: 290.32, bonus: 102, sickHours: 0, reimbursement: 123.25, tax: 432.17, taxIsEstimate: false, cashTips: 0 },
  ],
  rates: [{ effectiveFrom: '2000-01-01', rate: 25.5 }],
  cashouts: [],
  tuition: [{ periodStart: '2026-08-16', status: 'received', amount: 123.25 }],
  settings: { ...DEFAULT_SETTINGS, sickBalance: 11.12, sickAsOf: '2026-09-04' },
});

// The old app's own records: the same Aug 16 shift with tips corrected, and
// a newer one; no stubs, no settings saved.
const oldDays = [
  { id: '2026-08-16-x', date: '2026-08-16', mode: 'range', start: 465, end: 844, lunch: false, tips: 40, cash: 0, ld: 'none', miles: 0 },
  { id: '2026-10-21-y', date: '2026-10-21', mode: 'range', start: 465, end: 990, lunch: true, tips: 61.5, cash: 10, ld: 'partial', miles: 12 },
];

describe('moving the old log in', () => {
  it('adds new days, keeps a repeated shift once with the old log winning, and keeps stubs', () => {
    const incoming = fromLegacy(oldDays, null, null)!;
    expect(incoming.hasSettings).toBe(false);
    const m = mergeData(account(), incoming);
    expect(m.days.map(d => d.date).sort()).toEqual(['2026-08-16', '2026-10-21']);
    expect(m.days.find(d => d.date === '2026-08-16')!.ccTips).toBe(40);
    expect(m.days.find(d => d.date === '2026-10-21')!.travel).toBe('partial');
    expect(m.stubs).toHaveLength(1);
    expect(m.tuition).toHaveLength(1);
    expect(m.settings.sickBalance).toBe(11.12); // no old settings, so the account's stay
    expect(latestDay(m)).toBe('2026-10-21');
  });

  it('takes the old settings when the old app saved some', () => {
    const incoming = fromLegacy(oldDays, null, { rate: 26, sickAvail: 14.5 })!;
    const m = mergeData(account(), incoming);
    expect(m.settings.sickBalance).toBe(14.5);
    expect(m.rates).toEqual([{ effectiveFrom: '2000-01-01', rate: 26 }]);
  });

  it('round-trips through the copy-and-paste text', () => {
    const incoming = fromLegacy(oldDays, null, null)!;
    const back = parseBackup(toBackup(incoming))!;
    expect(back.days.map(d => d.date).sort()).toEqual(['2026-08-16', '2026-10-21']);
    expect(back.hasSettings).toBe(false);
    const m = mergeData(account(), back);
    expect(m.days).toHaveLength(2);
    expect(m.settings.sickBalance).toBe(11.12);
  });
});
