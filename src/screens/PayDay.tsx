import { useState } from 'react';
import { type Period, daysBetween, fmtMD, fmtRange, nextPeriod, todayIso } from '../lib/dates';
import { type Data, type Day, OT_MULT, computeHours, estimate, money, tuitionOwed, tuitionQuestions } from '../lib/pay';
import type { Actions } from '../store';
import { Line, NumField } from '../ui';
import { DayRow, newestFirst } from './DayRow';

function TuitionAsk({ data, p, actions }: { data: Data; p: Period; actions: Actions }) {
  const owed = tuitionOwed(data, p);
  const [amt, setAmt] = useState<number | null>(owed.amount);
  return (
    <div className="card alert">
      <div className="label accent">Tuition check-in</div>
      <div style={{ fontSize: 15 }}>Did tuition reimbursement come through on the {fmtMD(p.payDate)} check?</div>
      <div className="row">
        <div className="muted small">Expected about {money(owed.amount)} for {owed.hours.toFixed(2)}h</div>
        <NumField label="Tuition amount received" className="num sm" value={amt} onCommit={setAmt} placeholder="0.00" />
      </div>
      <div className="row">
        <button className="btn ghost" onClick={() => actions.setTuition(p.key, { status: 'missed', amount: 0 })}>No — move it to the next check</button>
        <button className="btn" style={{ width: 'auto', padding: '15px 22px' }}
          onClick={() => actions.setTuition(p.key, { status: 'received', amount: amt ?? 0 })}>Yes</button>
      </div>
    </div>
  );
}

export function PayDay({ data, pay, actions, onEdit }: { data: Data; pay: Period; actions: Actions; onEdit: (d: Day) => void }) {
  const [showTax, setShowTax] = useState(false);
  const today = todayIso();
  const calc = computeHours(data.days);
  const E = estimate(data, pay, today, calc);
  const T = E.totals;
  const closed = today > pay.to;
  const daysOut = daysBetween(today, pay.payDate);
  const total = daysBetween(pay.from, pay.to) + 1;
  const elapsed = Math.max(0, Math.min(total, daysBetween(pay.from, today) + 1));
  const next = nextPeriod(pay);
  const N = estimate(data, next, today, calc);
  const questions = tuitionQuestions(data, today);
  const noRate = !data.rates.length;

  return (
    <div className="screen">
      <div className="head" style={{ display: 'block' }}>
        <div className="label" style={{ letterSpacing: '0.2em' }}>Estimated statement</div>
        <h1>Pay day — {fmtMD(pay.payDate)}</h1>
      </div>

      {noRate && <div className="pad" style={{ paddingTop: 20 }}><div className="empty">Set your hourly rate in Settings to see an estimate.</div></div>}

      <div className="pad" style={{ paddingTop: 28 }}>
        <div className="big">{money(T.net)}</div>
        <div className="muted" style={{ fontSize: 14, marginTop: 8 }}>
          {T.gross > 0 ? `net estimate · gross ${money(T.gross)}` : T.tuition > 0 ? 'reimbursement only · nothing logged yet' : 'nothing logged yet'}
        </div>
      </div>

      <div className="progress" style={{ margin: '22px 24px 0' }}><div style={{ width: `${Math.round((elapsed / total) * 100)}%` }} /></div>
      <div className="row mono" style={{ margin: '8px 24px 0', fontSize: 11, color: 'var(--muted)' }}>
        <div>{fmtRange(pay)}</div>
        <div style={{ color: closed ? 'var(--accent-ink)' : undefined }}>
          {daysOut <= 0 ? 'TODAY' : closed ? `CLOSED · PAYS IN ${daysOut} DAY${daysOut === 1 ? '' : 'S'}` : `${daysOut} DAY${daysOut === 1 ? '' : 'S'} OUT`}
        </div>
      </div>

      <div className="lines" style={{ margin: '24px 24px 0' }}>
        {T.reg > 0 && <Line name="Regular" detail={`${T.reg.toFixed(2)}h @ ${T.rate.toFixed(2)}`} amt={money(T.regPay)} />}
        {T.ot > 0 && <Line name="Overtime" detail={`${T.ot.toFixed(2)}h @ ${(T.rate * OT_MULT).toFixed(2)}`} amt={money(T.otPay)} />}
        {T.tips > 0 && <Line name="Credit card tips" amt={money(T.tips)} />}
        {T.perDiem > 0 && <Line name="Per-diem" detail={`${T.travelDays} day${T.travelDays === 1 ? '' : 's'} · as spot bonus`} amt={money(T.perDiem)} />}
        {T.sick > 0 && <Line name="Sick cash-out" detail={`${T.sick.toFixed(2)}h @ ${T.rate.toFixed(2)}`} amt={money(T.sickPay)} />}
        <Line className="total" name="Gross" amt={money(T.gross)} />
        <Line className="dim" name="Est. taxes & deductions" amt={'−' + money(T.tax)} />
        {T.milePay > 0 && <Line name="POV mileage" detail={`${T.miles} mi`} amt={money(T.milePay)} />}
        {T.tuition > 0 && <Line name="Tuition reimb." detail={`${E.tuitionOwed.hours.toFixed(2)}h · expected`} amt={money(T.tuition)} />}
      </div>

      {T.cash > 0 && (
        <div className="row" style={{ margin: '16px 24px 0', padding: '14px 16px', border: '1px dashed oklch(0.7 0.01 70)' }}>
          <div className="stack">
            <div style={{ fontSize: 14 }}>Cash tips pocketed</div>
            <div className="muted" style={{ fontSize: 11 }}>already yours — not part of the check</div>
          </div>
          <div className="mono" style={{ fontSize: 18 }}>{money(T.cash)}</div>
        </div>
      )}

      <div className="label pad" style={{ marginTop: 16 }}>
        Accruing {E.accrual.toFixed(2)} sick h this period
        {data.settings.tuitionOn && !E.tuitionExpected && ' · tuition not expected on this check'}
      </div>
      <button className="link pad" style={{ marginTop: 18, textAlign: 'left' }} onClick={() => setShowTax(!showTax)}>
        {showTax ? 'Hide breakdown' : 'Show tax breakdown'}
      </button>
      {showTax && (
        <div className="panel" style={{ margin: '12px 24px 0' }}>
          {Object.entries(T.taxLines).map(([k, v]) => <div key={k} className="pl"><span>{k}</span><span>{money(v)}</span></div>)}
        </div>
      )}

      {questions.length > 0 && (
        <div className="pad" style={{ marginTop: 24, display: 'flex', flexDirection: 'column', gap: 12 }}>
          {questions.map(p => <TuitionAsk key={p.key} data={data} p={p} actions={actions} />)}
        </div>
      )}

      {E.list.length > 0 ? (
        <div className="pad" style={{ marginTop: 28 }}>
          <div className="label" style={{ paddingBottom: 8, borderBottom: '1px solid var(--ink)' }}>Logged days · tap to edit</div>
          {E.list.slice().sort(newestFirst).map(x => <DayRow key={x.id} day={x} calc={calc} data={data} onEdit={onEdit} />)}
        </div>
      ) : (
        <div className="pad" style={{ marginTop: 28 }}><div className="empty">No days logged for this period yet.</div></div>
      )}

      {N.list.length > 0 && (
        <div className="card" style={{ margin: '28px 24px 0' }}>
          <div className="label">Next check</div>
          <div className="row" style={{ alignItems: 'baseline' }}>
            <div className="stack">
              <div style={{ fontSize: 16, fontWeight: 600 }}>Pay day {fmtMD(next.payDate)}</div>
              <div className="mono muted" style={{ fontSize: 11 }}>{fmtRange(next)} · {N.list.length} day{N.list.length === 1 ? '' : 's'}</div>
            </div>
            <div className="stack" style={{ alignItems: 'flex-end' }}>
              <div className="serif" style={{ fontSize: 26 }}>{money(N.totals.net)}</div>
              {N.totals.cash > 0 && <div className="mono" style={{ fontSize: 11, color: 'var(--good)' }}>+ {money(N.totals.cash)} cash</div>}
            </div>
          </div>
          <div>{N.list.slice().sort(newestFirst).map(x => <DayRow key={x.id} day={x} calc={calc} data={data} onEdit={onEdit} />)}</div>
        </div>
      )}
    </div>
  );
}
