import { supabase } from './supabase';
import { todayIso } from './lib/dates';
import {
  type Cashout, type Data, type Day, type Rate, type Settings, type Stub, type TuitionEvent, DEFAULT_SETTINGS, num,
} from './lib/pay';

// Rows are snake_case in Postgres and camelCase in the app; these are the only
// two places that know both.

type Row = Record<string, unknown>;

const toDay = (r: Row): Day => ({
  id: r.id as string, date: r.date as string, mode: r.mode as Day['mode'],
  startMin: num(r.start_min), endMin: num(r.end_min),
  totalHours: r.total_hours == null ? null : num(r.total_hours),
  lunch: !!r.lunch, ccTips: num(r.cc_tips), cashTips: num(r.cash_tips),
  travel: r.travel as Day['travel'], miles: num(r.miles),
});
const fromDay = (d: Day) => ({
  id: d.id, date: d.date, mode: d.mode, start_min: d.startMin, end_min: d.endMin,
  total_hours: d.totalHours, lunch: d.lunch, cc_tips: d.ccTips, cash_tips: d.cashTips,
  travel: d.travel, miles: d.miles, updated_at: new Date().toISOString(),
});

const toStub = (r: Row): Stub => ({
  periodStart: r.period_start as string, periodEnd: r.period_end as string, payDate: r.pay_date as string,
  regHours: num(r.reg_hours), otHours: num(r.ot_hours), ccTips: num(r.cc_tips), bonus: num(r.bonus), sickHours: num(r.sick_hours),
  reimbursement: num(r.reimbursement), tax: num(r.tax), taxIsEstimate: !!r.tax_is_estimate, cashTips: num(r.cash_tips),
});
const fromStub = (s: Stub) => ({
  period_start: s.periodStart, period_end: s.periodEnd, pay_date: s.payDate,
  reg_hours: s.regHours, ot_hours: s.otHours, cc_tips: s.ccTips, bonus: s.bonus, sick_hours: s.sickHours,
  reimbursement: s.reimbursement, tax: s.tax, tax_is_estimate: s.taxIsEstimate, cash_tips: s.cashTips,
});

const toSettings = (r: Row | null): Settings => r ? {
  defaultStartMin: num(r.default_start_min), defaultLunch: !!r.default_lunch, mileRate: num(r.mile_rate),
  tuitionOn: !!r.tuition_on, tuitionRate: num(r.tuition_rate),
  sickBalance: num(r.sick_balance), sickAsOf: r.sick_as_of as string,
} : { ...DEFAULT_SETTINGS, sickAsOf: todayIso() };
const fromSettings = (s: Settings) => ({
  default_start_min: s.defaultStartMin, default_lunch: s.defaultLunch, mile_rate: s.mileRate,
  tuition_on: s.tuitionOn, tuition_rate: s.tuitionRate, sick_balance: s.sickBalance, sick_as_of: s.sickAsOf,
  updated_at: new Date().toISOString(),
});

async function must<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(error.message);
  return data;
}

export async function loadAll(): Promise<Data> {
  const [days, stubs, rates, settings, cashouts, tuition] = await Promise.all([
    must(supabase.from('days').select('*').order('date')),
    must(supabase.from('stubs').select('*').order('period_start', { ascending: false })),
    must(supabase.from('rates').select('effective_from, rate').order('effective_from')),
    must(supabase.from('settings').select('*').maybeSingle()),
    must(supabase.from('sick_cashouts').select('period_start, hours')),
    must(supabase.from('tuition_events').select('period_start, status, amount')),
  ]);
  return {
    days: (days as Row[]).map(toDay),
    stubs: (stubs as Row[]).map(toStub),
    rates: (rates as Row[]).map(r => ({ effectiveFrom: r.effective_from as string, rate: num(r.rate) })),
    settings: toSettings(settings as Row | null),
    cashouts: (cashouts as Row[]).map(r => ({ periodStart: r.period_start as string, hours: num(r.hours) })),
    tuition: (tuition as Row[]).map(r => ({
      periodStart: r.period_start as string, status: r.status as TuitionEvent['status'], amount: num(r.amount),
    })),
  };
}

export const db = {
  saveDay: (d: Day) => must(supabase.from('days').upsert(fromDay(d))),
  deleteDay: (id: string) => must(supabase.from('days').delete().eq('id', id)),
  saveSettings: (s: Settings) => must(supabase.from('settings').upsert(fromSettings(s))),
  saveRate: (r: Rate) => must(supabase.from('rates').upsert(
    { effective_from: r.effectiveFrom, rate: r.rate }, { onConflict: 'user_id,effective_from' })),
  deleteRate: (from: string) => must(supabase.from('rates').delete().eq('effective_from', from)),
  saveStub: (s: Stub) => must(supabase.from('stubs').upsert(fromStub(s))),
  deleteStub: (key: string) => must(supabase.from('stubs').delete().eq('period_start', key)),
  saveCashout: (c: Cashout) => c.hours > 0
    ? must(supabase.from('sick_cashouts').upsert({ period_start: c.periodStart, hours: c.hours }))
    : must(supabase.from('sick_cashouts').delete().eq('period_start', c.periodStart)),
  saveTuition: (key: string, e: Omit<TuitionEvent, 'periodStart'> | null) => e
    ? must(supabase.from('tuition_events').upsert({ period_start: key, status: e.status, amount: e.amount }))
    : must(supabase.from('tuition_events').delete().eq('period_start', key)),

  // Writes a merged import. Everything is upserted, so a dropped connection
  // part-way leaves the account with more rows, never fewer; only the days the
  // import replaced (dropDayIds) are deleted, and only after the rest is in.
  async writeMerged(d: Data, dropDayIds: string[]) {
    await db.saveSettings(d.settings);
    if (d.days.length) await must(supabase.from('days').upsert(d.days.map(fromDay)));
    if (d.stubs.length) await must(supabase.from('stubs').upsert(d.stubs.map(fromStub)));
    if (d.rates.length) await must(supabase.from('rates').upsert(
      d.rates.map(r => ({ effective_from: r.effectiveFrom, rate: r.rate })), { onConflict: 'user_id,effective_from' }));
    if (d.cashouts.length) await must(supabase.from('sick_cashouts').upsert(
      d.cashouts.map(c => ({ period_start: c.periodStart, hours: c.hours }))));
    if (d.tuition.length) await must(supabase.from('tuition_events').upsert(
      d.tuition.map(e => ({ period_start: e.periodStart, status: e.status, amount: e.amount }))));
    if (dropDayIds.length) await must(supabase.from('days').delete().in('id', dropDayIds));
  },
};
