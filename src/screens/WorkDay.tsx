import { useEffect, useRef } from 'react';
import { fmtTime, nowMinutes, todayIso } from '../lib/dates';
import { type Data, type Day, type Travel, PER_DIEM, dayHours, money, num, rateFor } from '../lib/pay';
import { NumField, Seg, Toggle } from '../ui';

const ITEM = 44;
const MINUTES = Array.from({ length: 1440 }, (_, i) => fmtTime(i));

// Clocking out "now" before the shift's start would wrap the day round to
// ~22 hours, so hold at the start until the clock passes it.
export const endNow = (start: number) => Math.max(nowMinutes(), start);

export function blankDay(data: Data): Day {
  const start = data.settings.defaultStartMin;
  return {
    id: '', date: todayIso(), mode: 'range', startMin: start, endMin: endNow(start), totalHours: null,
    lunch: data.settings.defaultLunch, ccTips: 0, cashTips: 0, travel: 'none', miles: 0,
  };
}

function Wheel({ value, onChange, label }: { value: number; onChange: (m: number) => void; label: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const userScroll = useRef(false);
  const settle = useRef<number>(0);
  const programmatic = useRef(false);

  useEffect(() => {
    const el = ref.current;
    if (!el || userScroll.current) return;
    if (Math.abs(el.scrollTop - value * ITEM) > 2) {
      programmatic.current = true;
      el.scrollTop = value * ITEM;
      window.setTimeout(() => { programmatic.current = false; }, 120);
    }
  }, [value]);

  const onScroll = () => {
    if (programmatic.current) return;
    userScroll.current = true;
    window.clearTimeout(settle.current);
    settle.current = window.setTimeout(() => {
      userScroll.current = false;
      const el = ref.current;
      if (!el) return;
      const v = Math.max(0, Math.min(1439, Math.round(el.scrollTop / ITEM)));
      if (v !== value) onChange(v);
    }, 140);
  };

  return (
    <div className="wheel-col">
      <div className="label">{label}</div>
      <div className="wheel-box">
        <div ref={ref} className="wheel" onScroll={onScroll} aria-label={label}>
          <div className="spacer" />
          {MINUTES.map((m, i) => <div key={i}>{m}</div>)}
          <div className="spacer" />
        </div>
        <div className="wheel-mark" />
      </div>
      <div className="wheel-value">{fmtTime(value)}</div>
    </div>
  );
}

export function WorkDay({ data, draft, setDraft, editing, onSave, onDelete }: {
  data: Data; draft: Day; setDraft: (patch: Partial<Day>) => void; editing: boolean;
  onSave: () => void; onDelete: () => void;
}) {
  const d = draft;
  const rate = rateFor(data.rates, d.date);
  const hours = dayHours(d);
  const mileRate = data.settings.mileRate;
  const subtotal = hours * rate + num(d.ccTips) + PER_DIEM[d.travel] + num(d.miles) * mileRate;
  const travelOpts: { value: Travel; label: string; sub?: string }[] = [
    { value: 'none', label: 'Local' },
    { value: 'partial', label: 'Travel day', sub: money(PER_DIEM.partial) },
    { value: 'full', label: 'Full away', sub: money(PER_DIEM.full) },
  ];

  return (
    <div className="screen">
      <div className="head">
        <h1>Work day</h1>
        <input type="date" aria-label="Date" value={d.date} onChange={e => e.target.value && setDraft({ date: e.target.value })} />
      </div>

      <div className="tabs">
        <button className={d.mode === 'range' ? 'on' : ''} onClick={() => setDraft({ mode: 'range' })}>Start / End</button>
        <button className={d.mode === 'total' ? 'on' : ''} onClick={() => setDraft({ mode: 'total' })}>Total hours</button>
      </div>

      {d.mode === 'range' ? (
        <div className="wheels">
          <Wheel label="Clock in" value={d.startMin} onChange={v => setDraft({ startMin: v })} />
          <Wheel label="Clock out" value={d.endMin} onChange={v => setDraft({ endMin: v })} />
        </div>
      ) : (
        <div className="pad" style={{ paddingTop: 24, display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div className="label">Hours worked</div>
          <NumField label="Hours worked" className="num" value={d.totalHours}
            onCommit={v => setDraft({ totalHours: v })} placeholder="0.00" />
        </div>
      )}

      {d.mode === 'range' && (
        <div className="section" style={{ marginTop: 18, borderTop: '1px solid var(--rule-2)' }}>
          <div className="row">
            <div style={{ fontSize: 15 }}>Lunch taken <span className="muted">(30 min unpaid)</span></div>
            <Toggle label="Lunch taken" on={d.lunch} onClick={() => setDraft({ lunch: !d.lunch })} />
          </div>
        </div>
      )}

      <div className="section">
        <div className="row">
          <div style={{ fontSize: 15 }}>Credit card tips</div>
          <NumField label="Credit card tips" value={d.ccTips} onCommit={v => setDraft({ ccTips: v ?? 0 })} placeholder="0.00" />
        </div>
        <div className="row">
          <div className="stack">
            <div style={{ fontSize: 15 }}>Cash tips</div>
            <div className="muted" style={{ fontSize: 11 }}>tracked only — not on your check</div>
          </div>
          <NumField label="Cash tips" className="num soft" value={d.cashTips} onCommit={v => setDraft({ cashTips: v ?? 0 })} placeholder="0.00" />
        </div>
      </div>

      <div className="section">
        <div className="label">Long distance</div>
        <Seg value={d.travel} options={travelOpts} onChange={v => setDraft({ travel: v })} />
        <div className="row">
          <div className="stack">
            <div className="muted" style={{ fontSize: 13 }}>POV miles driven</div>
            <div className="label">
              {num(d.miles) > 0 ? `${money(num(d.miles) * mileRate)} at $${mileRate.toFixed(2)}/mi` : 'Reimbursed, not taxed'}
            </div>
          </div>
          <NumField label="POV miles" className="num sm" value={d.miles} onCommit={v => setDraft({ miles: v ?? 0 })} placeholder="0" />
        </div>
      </div>

      <div className="row pad" style={{ paddingTop: 20, alignItems: 'baseline' }}>
        <div className="label" style={{ fontSize: 11 }}>{+hours.toFixed(2)} h worked{rate ? '' : ' · set your rate in settings'}</div>
        <div className="serif" style={{ fontSize: 28 }}>{money(subtotal)}</div>
      </div>

      <div className="row pad" style={{ paddingTop: 22 }}>
        {editing && <button className="btn danger" onClick={onDelete}>Delete</button>}
        <button className="btn" style={{ flex: 1 }} onClick={onSave}>{editing ? 'Update day' : 'Record day'}</button>
      </div>
    </div>
  );
}
