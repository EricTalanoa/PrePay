import { fmtFull, fmtTime } from '../lib/dates';
import { type Data, type Day, type DayCalc, OT_MULT, PER_DIEM, money, num, rateFor } from '../lib/pay';

export function DayRow({ day: x, calc, data, onEdit }: { day: Day; calc: Record<string, DayCalc>; data: Data; onEdit: (d: Day) => void }) {
  const c = calc[x.id] ?? { hours: 0, reg: 0, ot: 0 };
  const rate = rateFor(data.rates, x.date);
  const parts = [
    x.mode === 'total' ? `${c.hours.toFixed(2)}h` : `${fmtTime(x.startMin)} – ${fmtTime(x.endMin)}${x.lunch ? ' · 30m' : ''} · ${c.hours.toFixed(2)}h`,
  ];
  if (x.travel !== 'none') parts.push(x.travel === 'full' ? 'away' : 'travel');
  if (num(x.miles) > 0) parts.push(`${num(x.miles)} mi`);
  if (num(x.cashTips) > 0) parts.push(`${money(num(x.cashTips))} cash`);
  const amount = c.reg * rate + c.ot * rate * OT_MULT + num(x.ccTips) + PER_DIEM[x.travel];
  return (
    <button className="dayrow" onClick={() => onEdit(x)}>
      <div className="stack">
        <div style={{ fontSize: 15, fontWeight: 500 }}>{fmtFull(x.date)}</div>
        <div className="detail">{parts.join(' · ')}</div>
      </div>
      <div className="amt">{money(amount)}</div>
    </button>
  );
}

export const newestFirst = (a: Day, b: Day) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0);
