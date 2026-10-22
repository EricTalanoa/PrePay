import {
  type ISODate, type Period, addDays, nextPeriod, periodOf, prevPeriod, shiftPeriod, weekStart,
} from './dates';

export type Travel = 'none' | 'partial' | 'full';

export interface Day {
  id: string;
  date: ISODate;
  mode: 'range' | 'total';
  startMin: number;
  endMin: number;
  totalHours: number | null;
  lunch: boolean;
  ccTips: number;
  cashTips: number;
  travel: Travel;
  miles: number;
}

export interface Stub {
  periodStart: ISODate;
  periodEnd: ISODate;
  payDate: ISODate;
  regHours: number;
  otHours: number;
  ccTips: number;
  bonus: number; // the per-diem, which payroll prints as "spot bonus"
  sickHours: number; // cashed out on this check, at straight time
  reimbursement: number;
  tax: number;
  taxIsEstimate: boolean;
  cashTips: number;
}

export interface Rate { effectiveFrom: ISODate; rate: number }
export interface Cashout { periodStart: ISODate; hours: number }
export interface TuitionEvent { periodStart: ISODate; status: 'received' | 'missed'; amount: number }

export interface Settings {
  defaultStartMin: number;
  defaultLunch: boolean;
  mileRate: number;
  tuitionOn: boolean;
  tuitionRate: number;
  sickBalance: number;
  sickAsOf: ISODate;
}

export interface Data {
  days: Day[];
  stubs: Stub[];
  rates: Rate[];
  settings: Settings;
  cashouts: Cashout[];
  tuition: TuitionEvent[];
}

export const DEFAULT_SETTINGS: Omit<Settings, 'sickAsOf'> = {
  defaultStartMin: 465,
  defaultLunch: true,
  mileRate: 0.7,
  tuitionOn: true,
  tuitionRate: 1,
  sickBalance: 0,
};

export const OT_MULT = 1.5;
export const LUNCH_MIN = 30;

// Fixed per-day amounts. Payroll pays them as a "spot bonus", taxed as wages.
export const PER_DIEM: Record<Travel, number> = { none: 0, partial: 51, full: 75 };

// Rates read off the ADP stubs. FLI/Cares/MLI are levied on wages + bonus and
// skip tips; Workers Comp is per hour actually worked, so cashed-out sick
// hours are outside it.
export const TAX = {
  ss: 0.062, med: 0.0145,
  fli: 0.005433, cares: 0.0058, mli: 0.002643, wc: 0.3519,
};

// Federal withholding: the 2026 IRS percentage method for a semi-monthly
// payroll, single, standard W-4 (Pub. 15-T). Each row is where a rate starts:
// the annual bracket plus the $16,100 standard deduction, over 24 checks.
// A flat 12% matched small checks but missed the 22% band entirely, which is
// $165 on a $4,400 check.
export const FED_BRACKETS: [from: number, rate: number][] = [
  [670.83, 0.10], [1187.50, 0.12], [2770.83, 0.22], [5075.00, 0.24],
  [9078.13, 0.32], [11346.88, 0.35], [27362.50, 0.37],
];

export function federalTax(wages: number): number {
  let t = 0;
  FED_BRACKETS.forEach(([from, rate], i) => {
    const to = FED_BRACKETS[i + 1]?.[0] ?? Infinity;
    if (wages > from) t += (Math.min(wages, to) - from) * rate;
  });
  return t;
}

export const num = (x: unknown): number => {
  const n = typeof x === 'number' ? x : parseFloat(String(x));
  return Number.isFinite(n) ? n : 0;
};

// Rounds half up to the cent the way payroll does. Going through toFixed(6)
// first stops float noise (214.245 stored as 214.24499…) rounding down.
export const cents = (x: number) => Math.round(+(x * 100).toFixed(6)) / 100;

export function money(n: number): string {
  return (n < 0 ? '−$' : '$') + Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function dayHours(d: Pick<Day, 'mode' | 'startMin' | 'endMin' | 'totalHours' | 'lunch'>): number {
  if (d.mode === 'total') return Math.max(0, num(d.totalHours));
  let m = d.endMin - d.startMin;
  if (m < 0) m += 1440;
  if (d.lunch) m -= LUNCH_MIN;
  return Math.max(0, m / 60);
}

export const perDiemFor = (d: Pick<Day, 'travel'>) => PER_DIEM[d.travel] ?? 0;

// ---------------------------------------------------------------- rates

const byFrom = (rates: Rate[]) => rates.slice().sort((a, b) => (a.effectiveFrom < b.effectiveFrom ? -1 : 1));

// A raise applies to whole periods, so a date resolves through the period it
// falls in rather than through the date itself.
export function rateFor(rates: Rate[], date: ISODate): number {
  const key = periodOf(date).key;
  let r = 0;
  for (const x of byFrom(rates)) if (x.effectiveFrom <= key) r = x.rate;
  // A day before the earliest recorded rate still needs a rate.
  return r || byFrom(rates)[0]?.rate || 0;
}

// The rate in force today, and the raise still waiting for its date. Once a
// raise's date arrives it is simply the current rate: nothing to promote.
export function currentRate(rates: Rate[], today: ISODate): Rate | null {
  let r: Rate | null = null;
  for (const x of byFrom(rates)) if (x.effectiveFrom <= today) r = x;
  return r ?? byFrom(rates)[0] ?? null;
}

export function pendingRaise(rates: Rate[], today: ISODate): Rate | null {
  const cur = currentRate(rates, today);
  return byFrom(rates).find(x => x.effectiveFrom > today && x !== cur) ?? null;
}

// ---------------------------------------------------------------- hours

export interface DayCalc { hours: number; reg: number; ot: number }

// OT accrues within a Sat–Fri week on the hours past 40, in date order.
export function computeHours(days: Day[]): Record<string, DayCalc> {
  const sorted = days.slice().sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  const run: Record<string, number> = {};
  const out: Record<string, DayCalc> = {};
  for (const d of sorted) {
    const k = weekStart(d.date);
    const h = dayHours(d);
    const before = run[k] ?? 0, after = before + h;
    const ot = Math.max(0, after - 40) - Math.max(0, before - 40);
    out[d.id] = { hours: h, ot, reg: h - ot };
    run[k] = after;
  }
  return out;
}

export const daysIn = (days: Day[], p: Period) => days.filter(d => d.date >= p.from && d.date <= p.to);

// Hours a period actually paid: the stub wins where there is one.
export function periodHours(data: Data, p: Period, calc: Record<string, DayCalc>): number {
  const stub = data.stubs.find(s => s.periodStart === p.key);
  if (stub) return num(stub.regHours) + num(stub.otHours);
  return daysIn(data.days, p).reduce((a, d) => a + (calc[d.id]?.hours ?? 0), 0);
}

// ---------------------------------------------------------------- totals

export interface Totals {
  reg: number; ot: number; hrs: number; tips: number; cash: number;
  perDiem: number; travelDays: number; miles: number; milePay: number;
  rate: number; sick: number; sickPay: number; tuition: number;
  regPay: number; otPay: number; waBase: number; gross: number;
  taxLines: Record<string, number>; tax: number; net: number;
}

export function totals(
  list: Day[], calc: Record<string, DayCalc>,
  o: { rate: number; mileRate: number; sick?: number; tuition?: number },
): Totals {
  let reg = 0, ot = 0, hrs = 0, tips = 0, cash = 0, perDiem = 0, travelDays = 0, miles = 0;
  for (const d of list) {
    const c = calc[d.id] ?? { reg: 0, ot: 0, hours: 0 };
    reg += c.reg; ot += c.ot; hrs += c.hours;
    tips += num(d.ccTips); cash += num(d.cashTips); miles += num(d.miles);
    perDiem += perDiemFor(d);
    if (d.travel !== 'none') travelDays++;
  }
  const rate = o.rate;
  const regPay = reg * rate, otPay = ot * rate * OT_MULT;
  const sick = num(o.sick), sickPay = sick * rate;
  const milePay = miles * num(o.mileRate);
  const tuition = num(o.tuition);
  // Tips are taxed federally but sit outside the three Washington premiums;
  // per-diem comes through as a bonus and is taxed like wages; tuition and
  // mileage are reimbursements, outside all of it.
  const waBase = regPay + otPay + sickPay + perDiem;
  const gross = waBase + tips;
  const taxLines: Record<string, number> = {
    'Federal income tax': federalTax(gross),
    'Social Security': TAX.ss * gross,
    'Medicare': TAX.med * gross,
    'Washington FLI': TAX.fli * waBase,
    'Washington Cares': TAX.cares * waBase,
    'Washington MLI': TAX.mli * waBase,
    'WA Workers Comp': TAX.wc * hrs,
  };
  const tax = Object.values(taxLines).reduce((a, b) => a + b, 0);
  return {
    reg, ot, hrs, tips, cash, perDiem, travelDays, miles, milePay, rate, sick, sickPay, tuition,
    regPay, otPay, waBase, gross, taxLines, tax, net: gross - tax + tuition + milePay,
  };
}

export function stubTotals(s: Stub, rate: number) {
  // Payroll rounds each earnings line to cents before summing, and prints
  // overtime as two lines: OT straight (1x) and OT premium (0.5x).
  const regPay = cents(num(s.regHours) * rate);
  const otPay = cents(num(s.otHours) * rate) + cents(num(s.otHours) * rate * (OT_MULT - 1));
  const sickPay = cents(num(s.sickHours) * rate);
  const gross = cents(regPay + otPay + sickPay + num(s.ccTips) + num(s.bonus));
  return {
    regPay, otPay, sickPay, gross,
    hours: num(s.regHours) + num(s.otHours),
    net: cents(gross - num(s.tax) + num(s.reimbursement)),
  };
}

// ---------------------------------------------------------------- sick hours

export const accrualFor = (hours: number) => Math.floor(hours) / 40;

// Balance = what the stub said on sickAsOf, plus accrual on every check paid
// since, minus every cash-out paid (or scheduled) since. A cash-out leaves the
// balance the moment it is scheduled, so it can't be spent twice.
export function sickLedger(data: Data, today: ISODate, calc = computeHours(data.days)) {
  const asOf = data.settings.sickAsOf;
  let accrued = 0;
  const credited: { period: Period; hours: number }[] = [];
  let p = periodOf(asOf);
  // walk back far enough that every check paid after asOf is seen
  p = prevPeriod(prevPeriod(p));
  while (p.payDate <= today) {
    if (p.payDate > asOf) {
      const a = accrualFor(periodHours(data, p, calc));
      if (a > 0) credited.push({ period: p, hours: a });
      accrued += a;
    }
    p = nextPeriod(p);
  }
  let cashed = 0;
  for (const c of data.cashouts) if (periodOf(c.periodStart).payDate > asOf) cashed += num(c.hours);
  return {
    available: num(data.settings.sickBalance) + accrued - cashed,
    accrued, cashed, credited,
  };
}

// ---------------------------------------------------------------- tuition

// HR keys tuition in by hand, roughly every other check. The app expects it
// two checks after the last one it landed on. If an expected check comes and
// goes without it (marked missed, or never answered), it is expected on the
// very next check instead.
export const TUITION_EVERY = 2;

export function lastTuitionReceived(data: Data, before: ISODate): TuitionEvent | null {
  let last: TuitionEvent | null = null;
  for (const e of data.tuition) {
    if (e.status === 'received' && e.periodStart < before && (!last || e.periodStart > last.periodStart)) last = e;
  }
  return last;
}

export function tuitionExpected(data: Data, p: Period, today: ISODate): boolean {
  if (!data.settings.tuitionOn) return false;
  const ev = data.tuition.find(e => e.periodStart === p.key);
  if (ev) return ev.status === 'received';
  const last = lastTuitionReceived(data, p.key);
  if (!last) return true;
  let e = shiftPeriod(periodOf(last.periodStart), TUITION_EVERY);
  while (e.key < p.key) {
    const ev2 = data.tuition.find(x => x.periodStart === e.key);
    const passed = ev2 ? ev2.status === 'missed' : e.payDate <= today;
    if (!passed) return false; // an earlier check is still the one expected
    e = nextPeriod(e);
  }
  return e.key === p.key;
}

// $rate per hour worked on every period since accounting last ran it. A
// payout on period P settles hours through P-1, so P itself is still owed:
// the window opens AT the last paid period, not after it.
export function tuitionOwed(data: Data, p: Period, calc = computeHours(data.days)) {
  const last = lastTuitionReceived(data, p.key);
  const first = last ? last.periodStart : earliestKey(data);
  let hours = 0;
  const periods: Period[] = [];
  if (first) {
    for (let q = periodOf(first); q.key < p.key; q = nextPeriod(q)) {
      hours += periodHours(data, q, calc);
      periods.push(q);
    }
  }
  return { amount: cents(hours * num(data.settings.tuitionRate)), hours, periods };
}

function earliestKey(data: Data): ISODate | null {
  const keys = [...data.days.map(d => periodOf(d.date).key), ...data.stubs.map(s => s.periodStart)];
  return keys.length ? keys.sort()[0] : null;
}

// Checks that have been paid where tuition was expected and nobody has said
// whether it came. Only recent ones: an old gap is better fixed in History.
export function tuitionQuestions(data: Data, today: ISODate): Period[] {
  if (!data.settings.tuitionOn) return [];
  const out: Period[] = [];
  let p = periodOf(addDays(today, -45));
  for (; p.payDate <= today; p = nextPeriod(p)) {
    if (data.tuition.some(e => e.periodStart === p.key)) continue;
    if (!hasActivityBefore(data, p)) continue;
    if (tuitionExpected(data, p, today)) out.push(p);
  }
  return out;
}

const hasActivityBefore = (data: Data, p: Period) =>
  data.days.some(d => d.date < p.from) || data.stubs.some(s => s.periodStart < p.key);

// ---------------------------------------------------------------- one period

export function estimate(data: Data, p: Period, today: ISODate, calc = computeHours(data.days)) {
  const list = daysIn(data.days, p);
  const sick = data.cashouts.find(c => c.periodStart === p.key)?.hours ?? 0;
  const expected = tuitionExpected(data, p, today);
  const ev = data.tuition.find(e => e.periodStart === p.key);
  const owed = tuitionOwed(data, p, calc);
  const tuition = !expected ? 0 : ev?.status === 'received' ? num(ev.amount) : owed.amount;
  const T = totals(list, calc, { rate: rateFor(data.rates, p.from), mileRate: data.settings.mileRate, sick, tuition });
  return { period: p, list, totals: T, tuitionExpected: expected, tuitionOwed: owed, accrual: accrualFor(T.hrs) };
}
