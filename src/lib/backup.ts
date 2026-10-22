import { todayIso } from './dates';
import { type Data, type Day, type Stub, type Travel, DEFAULT_SETTINGS, num } from './pay';

// A backup is the whole Data object, versioned. Version 1 was the old
// single-file app's export: a bare array of days.
export const BACKUP_VERSION = 2;

export const toBackup = (d: Data) => JSON.stringify({ version: BACKUP_VERSION, ...d });

const uuid = () => crypto.randomUUID();
const isDate = (x: unknown): x is string => typeof x === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(x);

type Legacy = Record<string, unknown>;

function legacyDay(x: Legacy): Day {
  const travel: Travel = x.ld === 'partial' || x.ld === 'full' ? x.ld : 'none';
  return {
    id: uuid(), date: x.date as string, mode: x.mode === 'total' ? 'total' : 'range',
    startMin: num(x.start), endMin: num(x.end),
    totalHours: x.total == null || x.total === '' ? null : num(x.total),
    lunch: !!x.lunch, ccTips: num(x.tips), cashTips: num(x.cash), travel, miles: num(x.miles),
  };
}

function legacyStub(x: Legacy): Stub {
  return {
    periodStart: x.from as string, periodEnd: x.to as string, payDate: x.pay as string,
    regHours: num(x.regH), otHours: num(x.otH), ccTips: num(x.tips), bonus: num(x.bonus),
    reimbursement: num(x.reimb), tax: num(x.tax), taxIsEstimate: !!x.taxEst, cashTips: num(x.cash),
  };
}

// The old app kept days, stubs and settings in three localStorage keys.
export function fromLegacy(days: unknown, stubs: unknown, cfg: unknown): Data | null {
  const ds = Array.isArray(days) ? days.filter((x): x is Legacy => x && isDate(x.date)) : [];
  const ss = Array.isArray(stubs) ? stubs.filter((x): x is Legacy => x && isDate(x.from)) : [];
  const c = (cfg && typeof cfg === 'object' ? cfg : {}) as Legacy;
  if (!ds.length && !ss.length && !Object.keys(c).length) return null;
  const rates = [];
  if (num(c.rate) > 0) rates.push({ effectiveFrom: '2000-01-01', rate: num(c.rate) });
  if (isDate(c.raiseStart) && num(c.raiseRate) > 0) rates.push({ effectiveFrom: c.raiseStart, rate: num(c.raiseRate) });
  const stubList = ss.map(legacyStub);
  return {
    days: ds.map(legacyDay),
    stubs: stubList,
    rates,
    settings: {
      ...DEFAULT_SETTINGS,
      mileRate: c.mileRate == null ? DEFAULT_SETTINGS.mileRate : num(c.mileRate),
      tuitionOn: c.tuitionOn == null ? true : !!c.tuitionOn,
      tuitionRate: c.tuitionRate == null ? DEFAULT_SETTINGS.tuitionRate : num(c.tuitionRate),
      sickBalance: num(c.sickAvail),
      sickAsOf: todayIso(),
    },
    cashouts: isDate(c.sickPeriod) && num(c.sickHours) > 0 ? [{ periodStart: c.sickPeriod, hours: num(c.sickHours) }] : [],
    // the old app read a reimbursement on a stub as tuition landing there
    tuition: stubList.filter(s => s.reimbursement > 0)
      .map(s => ({ periodStart: s.periodStart, status: 'received' as const, amount: s.reimbursement })),
  };
}

export function readLegacyStorage(): Data | null {
  try {
    const get = (k: string) => { const s = localStorage.getItem(k); return s ? JSON.parse(s) : null; };
    return fromLegacy(get('prepay.days.v4'), get('prepay.stubs.v1'), get('prepay.settings.v1'));
  } catch {
    return null;
  }
}

export function parseBackup(text: string): Data | null {
  let x: unknown;
  try { x = JSON.parse(text); } catch { return null; }
  if (Array.isArray(x)) return x.every(d => d && isDate(d.date)) ? fromLegacy(x, null, null) : null;
  if (!x || typeof x !== 'object') return null;
  const o = x as Partial<Data> & { version?: number };
  if (o.version !== BACKUP_VERSION || !Array.isArray(o.days) || !o.settings) return null;
  return {
    days: o.days.map(d => ({ ...d, id: d.id || uuid() })),
    stubs: o.stubs ?? [], rates: o.rates ?? [], cashouts: o.cashouts ?? [], tuition: o.tuition ?? [],
    settings: { ...DEFAULT_SETTINGS, ...o.settings, sickAsOf: o.settings.sickAsOf || todayIso() },
  };
}
