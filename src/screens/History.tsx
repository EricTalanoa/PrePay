import { useState } from 'react';
import { type Period, fmtMD, fmtRange, periodOf, prevPeriod, todayIso } from '../lib/dates';
import {
  type Data, type Day, type Stub, OT_MULT, computeHours, daysIn, estimate, money, num, rateFor, stubTotals,
  tuitionExpected, tuitionOwed,
} from '../lib/pay';
import type { Actions } from '../store';
import { NumField, PanelLine, Seg } from '../ui';
import { DayRow, newestFirst } from './DayRow';
import { StatsView } from './Stats';

type TuitionChoice = 'received' | 'missed' | 'unset';

function TuitionStatus({ data, p, actions }: { data: Data; p: Period; actions: Actions }) {
  if (!data.settings.tuitionOn) return null;
  const today = todayIso();
  const ev = data.tuition.find(e => e.periodStart === p.key);
  const value: TuitionChoice = ev?.status ?? 'unset';
  const expected = tuitionExpected(data, p, today);
  const owed = tuitionOwed(data, p);
  const set = (v: TuitionChoice) =>
    actions.setTuition(p.key, v === 'unset' ? null : { status: v, amount: v === 'received' ? (ev?.amount || owed.amount) : 0 });
  return (
    <div className="panel" style={{ marginTop: 14, display: 'flex', flexDirection: 'column', gap: 10 }}>
      <div className="label">
        Tuition on this check · {ev ? (ev.status === 'received' ? 'came through' : 'did not come') : expected ? 'expected, not confirmed' : 'not expected'}
      </div>
      <Seg mono value={value} onChange={set} options={[
        { value: 'received', label: 'CAME THROUGH' }, { value: 'missed', label: "DIDN'T" }, { value: 'unset', label: 'NOT SURE' },
      ]} />
      {ev?.status === 'received' && (
        <div className="row">
          <div className="small muted">Amount · owed was about {money(owed.amount)}</div>
          <NumField label="Tuition amount" className="num sm" value={ev.amount}
            onCommit={v => actions.setTuition(p.key, { status: 'received', amount: v ?? 0 })} />
        </div>
      )}
    </div>
  );
}

function DaysList({ list, data, calc, onEdit }: { list: Day[]; data: Data; calc: ReturnType<typeof computeHours>; onEdit: (d: Day) => void }) {
  if (!list.length) return null;
  return (
    <div style={{ marginTop: 16 }}>
      <div className="label" style={{ paddingBottom: 4 }}>Logged days · tap to correct</div>
      {list.slice().sort(newestFirst).map(x => <DayRow key={x.id} day={x} calc={calc} data={data} onEdit={onEdit} />)}
    </div>
  );
}

function StubBody({ s, data, actions, onEdit }: { s: Stub; data: Data; actions: Actions; onEdit: (d: Day) => void }) {
  const calc = computeHours(data.days);
  const p = periodOf(s.periodStart);
  const rate = rateFor(data.rates, s.periodStart);
  const P = stubTotals(s, rate);
  const list = daysIn(data.days, p);
  const set = (patch: Partial<Stub>) => actions.saveStub({ ...s, ...patch });
  const field = (key: keyof Stub, label: string, note: string, prefix = '') => (
    <div key={key} className="row" style={{ padding: '9px 0', borderTop: '1px solid var(--rule)' }}>
      <div className="stack"><div style={{ fontSize: 14 }}>{label}</div><div className="muted" style={{ fontSize: 11 }}>{note}</div></div>
      <div className="row" style={{ gap: 4 }}>
        <span className="muted" style={{ fontSize: 13 }}>{prefix}</span>
        <NumField label={label} className="num sm" value={s[key] as number}
          onCommit={v => set({ [key]: v ?? 0, ...(key === 'tax' ? { taxIsEstimate: false } : {}) })} />
      </div>
    </div>
  );

  // What the log says against what payroll paid: this is what turns up a
  // shift whose tips never made it onto the check.
  const checks: { name: string; logged: string; paid: string; delta: string }[] = [];
  if (list.length) {
    const L = estimate(data, p, todayIso(), calc).totals;
    const dT = L.tips - s.ccTips, dH = L.hrs - (s.regHours + s.otHours), dP = L.perDiem - s.bonus;
    const word = (x: number) => (x > 0 ? 'SHORT ' : 'OVER ');
    if (Math.abs(dT) > 0.005) checks.push({ name: 'CC tips', logged: money(L.tips), paid: money(s.ccTips), delta: word(dT) + money(Math.abs(dT)) });
    if (Math.abs(dH) > 0.05) checks.push({ name: 'Hours', logged: L.hrs.toFixed(2) + 'h', paid: (s.regHours + s.otHours).toFixed(2) + 'h', delta: word(dH) + Math.abs(dH).toFixed(2) + 'h' });
    if (Math.abs(dP) > 0.005) checks.push({ name: 'Per-diem', logged: money(L.perDiem), paid: money(s.bonus), delta: word(dP) + money(Math.abs(dP)) });
  }

  return (
    <div style={{ paddingBottom: 22 }}>
      {field('regHours', 'Regular hours', `@ $${rate.toFixed(2)}`)}
      {field('otHours', 'Overtime hours', `@ $${(rate * OT_MULT).toFixed(2)}`)}
      {field('ccTips', 'CC tips', 'taxed as wages', '$')}
      {field('bonus', 'Per-diem', 'printed as spot bonus · taxed', '$')}
      {field('reimbursement', 'Reimbursement', 'tuition + mileage · after tax', '$')}
      {field('tax', 'Taxes & deductions', 'as printed on the stub', '$')}
      {field('cashTips', 'Cash tips', 'off the check', '$')}
      <div className="panel" style={{ marginTop: 14 }}>
        <PanelLine name={`Regular ${s.regHours.toFixed(2)}h`} amt={money(P.regPay)} />
        {s.otHours > 0 && <PanelLine name={`Overtime ${s.otHours.toFixed(2)}h`} amt={money(P.otPay)} />}
        {s.ccTips > 0 && <PanelLine name="CC tips" amt={money(s.ccTips)} />}
        {s.bonus > 0 && <PanelLine name="Per-diem" amt={money(s.bonus)} />}
        <PanelLine tone="strong" name="Gross" amt={money(P.gross)} extra={s.cashTips > 0 ? `+ ${money(s.cashTips)} cash` : undefined} />
        <PanelLine tone="dim" name="Taxes & deductions" amt={'−' + money(s.tax)} />
        {s.reimbursement > 0 && <PanelLine name="Reimbursement (untaxed)" amt={money(s.reimbursement)} />}
        <PanelLine tone="strong" name="Net pay" amt={money(P.net)} />
      </div>
      {s.taxIsEstimate && <div className="dashed label accent" style={{ marginTop: 14, textAlign: 'left' }}>Tax is still the estimate · type it off the stub</div>}
      {checks.length > 0 && (
        <div className="card alert" style={{ marginTop: 14, gap: 4 }}>
          <div className="label accent">Your log disagrees with this stub</div>
          {checks.map(c => (
            <div key={c.name} className="mono" style={{ padding: '5px 0' }}>
              <div className="row" style={{ fontSize: 12 }}><span>{c.name}</span><span style={{ color: 'var(--accent-ink)', fontWeight: 600 }}>{c.delta}</span></div>
              <div className="muted" style={{ fontSize: 11, paddingTop: 3 }}>{c.logged} logged · {c.paid} paid</div>
            </div>
          ))}
        </div>
      )}
      <TuitionStatus data={data} p={p} actions={actions} />
      <DaysList list={list} data={data} calc={calc} onEdit={onEdit} />
      <button className="link" style={{ marginTop: 18, color: 'var(--muted)' }}
        onClick={() => { if (confirm('Remove this stub? Logged days stay.')) actions.deleteStub(s.periodStart); }}>Remove stub</button>
    </div>
  );
}

function EstimateBody({ p, data, actions, onEdit }: { p: Period; data: Data; actions: Actions; onEdit: (d: Day) => void }) {
  const calc = computeHours(data.days);
  const E = estimate(data, p, todayIso(), calc);
  const T = E.totals;
  return (
    <div style={{ paddingBottom: 22 }}>
      <div className="panel">
        {T.reg > 0 && <PanelLine name={`Regular ${T.reg.toFixed(2)}h`} amt={money(T.regPay)} />}
        {T.ot > 0 && <PanelLine name={`Overtime ${T.ot.toFixed(2)}h`} amt={money(T.otPay)} />}
        {T.tips > 0 && <PanelLine name="CC tips" amt={money(T.tips)} />}
        {T.perDiem > 0 && <PanelLine name="Per-diem" amt={money(T.perDiem)} />}
        {T.sickPay > 0 && <PanelLine name={`Sick cash-out ${T.sick.toFixed(2)}h`} amt={money(T.sickPay)} />}
        <PanelLine tone="strong" name="Gross" amt={money(T.gross)} extra={T.cash > 0 ? `+ ${money(T.cash)} cash` : undefined} />
        <PanelLine tone="dim" name="Est. taxes" amt={'−' + money(T.tax)} />
        {T.tuition > 0 && <PanelLine name="Tuition reimb." amt={money(T.tuition)} />}
        {T.milePay > 0 && <PanelLine name={`POV mileage ${T.miles} mi`} amt={money(T.milePay)} />}
        <PanelLine tone="strong" name="Net" amt={money(T.net)} />
      </div>
      <TuitionStatus data={data} p={p} actions={actions} />
      <DaysList list={E.list} data={data} calc={calc} onEdit={onEdit} />
    </div>
  );
}

export function History({ data, pay, actions, onEdit }: { data: Data; pay: Period; actions: Actions; onEdit: (d: Day) => void }) {
  const [open, setOpen] = useState<string | null>(null);
  const [stats, setStats] = useState(false);
  const today = todayIso();
  const calc = computeHours(data.days);

  type Entry = { key: string; period: Period; stub?: Stub };
  const keys = new Map<string, Entry>();
  for (const s of data.stubs) keys.set(s.periodStart, { key: s.periodStart, period: periodOf(s.periodStart), stub: s });
  for (const d of data.days) {
    const p = periodOf(d.date);
    if (!keys.has(p.key) && p.to < pay.from) keys.set(p.key, { key: p.key, period: p });
  }
  const entries = [...keys.values()].sort((a, b) => (a.key < b.key ? 1 : -1));

  // Without this the newest check could never become an ACTUAL row.
  const prev = prevPeriod(pay);
  const havePrev = data.stubs.some(s => s.periodStart === prev.key);
  const addStub = () => {
    const E = estimate(data, prev, today, calc);
    const T = E.totals;
    actions.saveStub({
      periodStart: prev.key, periodEnd: prev.to, payDate: prev.payDate,
      regHours: +T.reg.toFixed(2), otHours: +T.ot.toFixed(2), ccTips: +T.tips.toFixed(2), bonus: T.perDiem,
      reimbursement: +(T.tuition + T.milePay).toFixed(2), tax: +T.tax.toFixed(2), taxIsEstimate: true, cashTips: +T.cash.toFixed(2),
    });
    setOpen(prev.key);
  };

  return (
    <div className="screen">
      <div className="head">
        <div>
          <div className="label" style={{ letterSpacing: '0.2em' }}>Record</div>
          <h1>{stats ? 'Stats' : 'Past pay periods'}</h1>
        </div>
        <button className="link" onClick={() => setStats(!stats)}>{stats ? '← Periods' : 'Stats →'}</button>
      </div>

      {stats ? <StatsView data={data} /> : (
        <>
          {!havePrev && (
            <div className="pad" style={{ marginTop: 20 }}>
              <button className="dashed link" style={{ width: '100%' }} onClick={addStub}>+ Add the {fmtMD(prev.payDate)} check</button>
              <div className="label" style={{ textAlign: 'center', padding: '6px 0', letterSpacing: '0.1em' }}>Prefilled from your log · type the real figures off the stub</div>
            </div>
          )}
          {entries.length === 0 && <div className="pad" style={{ marginTop: 28 }}><div className="empty">Nothing here yet. Past periods appear once a pay day passes.</div></div>}
          {entries.map(e => {
            const isOpen = open === e.key;
            const net = e.stub ? stubTotals(e.stub, rateFor(data.rates, e.key)).net : estimate(data, e.period, today, calc).totals.net;
            const cash = e.stub ? e.stub.cashTips : daysIn(data.days, e.period).reduce((a, d) => a + num(d.cashTips), 0);
            const sub = e.stub ? `${(e.stub.regHours + e.stub.otHours).toFixed(2)} h` : `${daysIn(data.days, e.period).length} days`;
            return (
              <div key={e.key} style={{ borderBottom: '1px solid var(--rule-2)', margin: '0 24px' }}>
                <button className="row" style={{ width: '100%', padding: '18px 0', alignItems: 'baseline', textAlign: 'left' }}
                  onClick={() => setOpen(isOpen ? null : e.key)}>
                  <div className="stack">
                    <div className="row" style={{ gap: 8, justifyContent: 'flex-start' }}>
                      <div style={{ fontSize: 17, fontWeight: 600 }}>Paid {fmtMD(e.period.payDate)}</div>
                      <div className="mono" style={{
                        fontSize: 9, letterSpacing: '0.12em', padding: '2px 6px',
                        border: `1px solid ${e.stub ? 'var(--accent)' : 'oklch(0.75 0.01 70)'}`, color: e.stub ? 'var(--accent-ink)' : 'var(--muted)',
                      }}>{e.stub ? 'ACTUAL' : 'ESTIMATE'}</div>
                    </div>
                    <div className="mono muted" style={{ fontSize: 11 }}>{fmtRange(e.period)} · {sub}</div>
                  </div>
                  <div className="row" style={{ gap: 10, alignItems: 'baseline' }}>
                    <div className="stack" style={{ alignItems: 'flex-end' }}>
                      <div className="serif" style={{ fontSize: 24 }}>{money(net)}</div>
                      {cash > 0 && <div className="mono" style={{ fontSize: 11, color: 'var(--good)' }}>+ {money(cash)} cash</div>}
                    </div>
                    <div style={{ fontSize: 13, color: 'var(--accent-ink)' }}>{isOpen ? '−' : '+'}</div>
                  </div>
                </button>
                {isOpen && (e.stub
                  ? <StubBody s={e.stub} data={data} actions={actions} onEdit={onEdit} />
                  : <EstimateBody p={e.period} data={data} actions={actions} onEdit={onEdit} />)}
              </div>
            );
          })}
        </>
      )}
    </div>
  );
}
