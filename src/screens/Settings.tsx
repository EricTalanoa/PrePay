import { useState } from 'react';
import { type Period, fmtMD, fmtTime, nextPeriod, pad, todayIso } from '../lib/dates';
import { toBackup, parseBackup, readLegacyStorage } from '../lib/backup';
import {
  type Data, OT_MULT, currentRate, estimate, money, pendingRaise, sickLedger, tuitionExpected, tuitionOwed,
} from '../lib/pay';
import type { Actions } from '../store';
import { NumField, Seg, Toggle } from '../ui';

const START_PRESETS = [465, 480];

function nextTuitionCheck(data: Data, from: Period, today: string): Period | null {
  for (let p = from, i = 0; i < 6; p = nextPeriod(p), i++) if (tuitionExpected(data, p, today)) return p;
  return null;
}

function Backup({ data, actions, onClose, mode }: { data: Data; actions: Actions; onClose: () => void; mode: 'export' | 'import' }) {
  const [text, setText] = useState(mode === 'export' ? toBackup(data) : '');
  const [note, setNote] = useState<{ msg: string; bad: boolean } | null>(null);
  const act = async () => {
    if (mode === 'export') {
      try { await navigator.clipboard.writeText(text); setNote({ msg: 'COPIED', bad: false }); }
      catch { setNote({ msg: 'SELECT THE TEXT AND COPY MANUALLY', bad: true }); }
      return;
    }
    const parsed = parseBackup(text);
    if (!parsed) { setNote({ msg: "THAT DOESN'T LOOK LIKE A BACKUP", bad: true }); return; }
    await actions.replaceAll(parsed);
    onClose();
  };
  return (
    <div className="sheet-bg" onClick={onClose}>
      <div className="sheet" onClick={e => e.stopPropagation()}>
        <div className="row" style={{ alignItems: 'baseline' }}>
          <div className="serif" style={{ fontSize: 26 }}>{mode === 'import' ? 'Import backup' : 'Export backup'}</div>
          <button className="link" onClick={onClose}>Close</button>
        </div>
        <div className="muted" style={{ fontSize: 13 }}>
          {mode === 'import'
            ? 'Paste a backup below. This replaces everything stored in your account. Old one-file Prepay exports work too.'
            : 'Everything in your account as text. Keep it somewhere safe; importing it restores it all.'}
        </div>
        <textarea value={text} onChange={e => { setText(e.target.value); setNote(null); }} spellCheck={false} readOnly={mode === 'export'} />
        <button className="btn" onClick={act}>{mode === 'import' ? 'Replace everything' : 'Copy to clipboard'}</button>
        {note && <div className={'label' + (note.bad ? ' warn' : '')}>{note.msg}</div>}
      </div>
    </div>
  );
}

export function Settings({ data, pay, actions, email, onSignOut }: {
  data: Data; pay: Period; actions: Actions; email: string; onSignOut: () => void;
}) {
  const today = todayIso();
  const s = data.settings;
  const cur = currentRate(data.rates, today);
  const pending = pendingRaise(data.rates, today);
  const [raiseRate, setRaiseRate] = useState<number | null>(null);
  const [raiseWhen, setRaiseWhen] = useState<'this' | 'next'>('next');
  const [customStart, setCustomStart] = useState(!START_PRESETS.includes(s.defaultStartMin));
  const [backup, setBackup] = useState<'export' | 'import' | null>(null);
  const legacy = readLegacyStorage();

  // A raise starts on a whole period: the one being paid next, or the one after.
  const thisFrom = pay.from, nextFrom = nextPeriod(pay).from;
  const raiseTarget = raiseWhen === 'this' ? thisFrom : nextFrom;

  const ledger = sickLedger(data, today);
  const cashout = data.cashouts.find(c => c.periodStart === pay.key)?.hours ?? 0;
  const canCash = ledger.available + cashout;
  const E = estimate(data, pay, today);

  const tuiNext = nextTuitionCheck(data, pay, today);
  const tuiOwed = tuiNext ? tuitionOwed(data, tuiNext) : null;
  const startVal = `${pad(Math.floor(s.defaultStartMin / 60))}:${pad(s.defaultStartMin % 60)}`;

  return (
    <div className="screen">
      <div className="head"><h1>Settings</h1></div>

      <div className="section">
        <div className="label">Hourly rate</div>
        <div className="row">
          <div style={{ fontSize: 15 }}>Base rate</div>
          <NumField label="Base rate" value={cur?.rate} placeholder="0.00" onCommit={v => v && actions.setBaseRate(v)} />
        </div>
        <div className="label">
          {cur ? `$${cur.rate.toFixed(2)} / hour · OT $${(cur.rate * OT_MULT).toFixed(2)}` : 'Enter what you make an hour'}
          {cur && cur.effectiveFrom > '2000-01-01' && ` · since ${fmtMD(cur.effectiveFrom)}`}
        </div>
      </div>

      <div className="section">
        <div className="label">Raise</div>
        {pending ? (
          <div className="row panel">
            <div className="label warn" style={{ letterSpacing: '0.12em' }}>
              ${pending.rate.toFixed(2)} from {fmtMD(pending.effectiveFrom)} onward
            </div>
            <button className="label" onClick={actions.clearRaise}>Clear</button>
          </div>
        ) : (
          <>
            <div className="row">
              <div style={{ fontSize: 15 }}>New rate</div>
              <NumField label="New rate" value={raiseRate} placeholder="0.00" onCommit={setRaiseRate} />
            </div>
            <Seg mono value={raiseWhen} onChange={setRaiseWhen} options={[
              { value: 'this', label: `THIS PERIOD · ${fmtMD(thisFrom).toUpperCase()}` },
              { value: 'next', label: `NEXT PERIOD · ${fmtMD(nextFrom).toUpperCase()}` },
            ]} />
            <button className="btn" disabled={!(raiseRate && raiseRate > 0)}
              onClick={() => { if (raiseRate) { actions.scheduleRaise(raiseRate, raiseTarget); setRaiseRate(null); } }}>
              Start the raise
            </button>
            <div className="label">Once its date arrives it becomes the base rate</div>
          </>
        )}
      </div>

      <div className="section">
        <div className="label">Work day defaults</div>
        <div style={{ fontSize: 15 }}>Start time</div>
        <Seg value={customStart ? 'custom' : String(s.defaultStartMin)} onChange={v => {
          if (v === 'custom') { setCustomStart(true); return; }
          setCustomStart(false);
          actions.setSettings({ defaultStartMin: +v });
        }} options={[
          ...START_PRESETS.map(m => ({ value: String(m), label: fmtTime(m) })),
          { value: 'custom', label: 'Custom' },
        ]} />
        {customStart && (
          <div className="row">
            <div className="muted" style={{ fontSize: 13 }}>Clock in at</div>
            <input type="time" aria-label="Custom start time" value={startVal} className="mono" style={{ fontSize: 18 }}
              onChange={e => {
                const [hh, mm] = e.target.value.split(':').map(Number);
                if (Number.isFinite(hh) && Number.isFinite(mm)) actions.setSettings({ defaultStartMin: hh * 60 + mm });
              }} />
          </div>
        )}
        <div className="row">
          <div style={{ fontSize: 15 }}>Lunch taken by default</div>
          <Toggle label="Lunch taken by default" on={s.defaultLunch} onClick={() => actions.setSettings({ defaultLunch: !s.defaultLunch })} />
        </div>
      </div>

      <div className="section">
        <div className="row">
          <div style={{ fontSize: 15 }}>Tuition reimbursement</div>
          <Toggle label="Tuition reimbursement" on={s.tuitionOn} onClick={() => actions.setSettings({ tuitionOn: !s.tuitionOn })} />
        </div>
        {s.tuitionOn && (
          <>
            <div className="row">
              <div className="muted" style={{ fontSize: 15 }}>Per hour worked</div>
              <NumField label="Tuition per hour" value={s.tuitionRate} placeholder="1.00" onCommit={v => actions.setSettings({ tuitionRate: v ?? 0 })} />
            </div>
            <div className="label">
              {tuiNext && tuiOwed
                ? `Expected on the ${fmtMD(tuiNext.payDate)} check · about ${money(tuiOwed.amount)} for ${tuiOwed.hours.toFixed(2)}h`
                : 'Not expected in the next few checks'}
            </div>
            <div className="muted small">
              Usually every other check. If an expected one doesn't come, it moves to the next check — Pay day asks you after each one.
            </div>
          </>
        )}
      </div>

      <div className="section">
        <div className="label">POV mileage</div>
        <div className="row">
          <div style={{ fontSize: 15 }}>Per mile</div>
          <NumField label="Mileage rate" value={s.mileRate} placeholder="0.70" onCommit={v => actions.setSettings({ mileRate: v ?? 0 })} />
        </div>
      </div>

      <div className="section">
        <div className="label">Sick hours</div>
        <div className="row">
          <div className="stack">
            <div style={{ fontSize: 15 }}>Available</div>
            <div className="label">Type the balance off your latest stub</div>
          </div>
          <NumField label="Sick hours available" value={+ledger.available.toFixed(2)} placeholder="0.00"
            onCommit={v => actions.setSickAvailable(v ?? 0)} />
        </div>
        <div className="row">
          <div className="stack">
            <div style={{ fontSize: 15 }}>Cash out on the {fmtMD(pay.payDate)} check</div>
            <div className="label">{canCash.toFixed(2)} h can be cashed</div>
          </div>
          <NumField label="Sick hours to cash out" value={cashout} placeholder="0.00"
            onCommit={v => actions.setCashout(pay.key, Math.max(0, v ?? 0))} />
        </div>
        <div className="label">
          {cashout > 0 ? `${money(E.totals.sickPay)} on the ${fmtMD(pay.payDate)} check · already off your balance` : 'Taxed as wages · no workers comp'}
        </div>
        {cashout > canCash + 1e-9 && <div className="label warn">More than you have accrued</div>}
        <div className="label">
          +{E.accrual.toFixed(2)} h accruing this period · lands {fmtMD(pay.payDate)}
          {ledger.accrued > 0 && ` · ${ledger.accrued.toFixed(2)} h added since ${fmtMD(s.sickAsOf)}`}
        </div>
      </div>

      <div className="section">
        <div className="label">Backup · {data.days.length} days stored</div>
        <div className="row">
          <button className="btn ghost" onClick={() => setBackup('export')}>Export</button>
          <button className="btn ghost" onClick={() => setBackup('import')}>Import</button>
        </div>
        {legacy && (
          <div className="card">
            <div style={{ fontSize: 14 }}>
              This browser still has data from the old Prepay: {legacy.days.length} days and {legacy.stubs.length} stubs.
            </div>
            <button className="btn" onClick={() => {
              if (confirm('Replace everything in your account with the data saved in this browser?')) actions.replaceAll(legacy);
            }}>Move it into my account</button>
          </div>
        )}
      </div>

      <div className="section">
        <div className="label">Account</div>
        <div className="row">
          <div className="mono small" style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{email}</div>
          <button className="link" onClick={onSignOut}>Sign out</button>
        </div>
      </div>
      {backup && <Backup data={data} actions={actions} mode={backup} onClose={() => setBackup(null)} />}
    </div>
  );
}
