import { type ReactNode, useEffect, useState } from 'react';

export function Toggle({ on, onClick, label }: { on: boolean; onClick: () => void; label: string }) {
  return (
    <button className={'toggle' + (on ? ' on' : '')} onClick={onClick} role="switch" aria-checked={on} aria-label={label}>
      <i />
    </button>
  );
}

export function Seg<T extends string>({ value, options, onChange, mono }: {
  value: T; options: { value: T; label: ReactNode; sub?: ReactNode }[]; onChange: (v: T) => void; mono?: boolean;
}) {
  return (
    <div className={'seg' + (mono ? ' mono' : '')}>
      {options.map(o => (
        <button key={o.value} className={o.value === value ? 'on' : ''} onClick={() => onChange(o.value)}>
          {o.label}{o.sub != null && <small>{o.sub}</small>}
        </button>
      ))}
    </div>
  );
}

// A number box that keeps what's typed locally and commits on blur or Enter,
// so a write goes to the database once per edit, not once per keystroke.
export function NumField({ value, onCommit, placeholder, className = 'num', label }: {
  value: number | null | undefined; onCommit: (n: number | null) => void; placeholder?: string; className?: string; label: string;
}) {
  const shown = value == null || value === 0 ? '' : String(value);
  const [text, setText] = useState(shown);
  useEffect(() => setText(shown), [shown]);
  const commit = () => {
    const n = text.trim() === '' ? null : parseFloat(text);
    if (n !== null && !Number.isFinite(n)) { setText(shown); return; }
    if ((n ?? 0) !== (value ?? 0)) onCommit(n);
  };
  return (
    <input
      className={className} type="text" inputMode="decimal" aria-label={label} placeholder={placeholder}
      value={text} onChange={e => setText(e.target.value)} onBlur={commit}
      onKeyDown={e => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); }}
    />
  );
}

export function Line({ name, detail, amt, className = '' }: { name: ReactNode; detail?: ReactNode; amt: ReactNode; className?: string }) {
  return (
    <div className={'line ' + className}>
      <span>{name} {detail && <span className="detail">{detail}</span>}</span>
      <span className="amt">{amt}</span>
    </div>
  );
}

export function PanelLine({ name, amt, extra, tone }: { name: ReactNode; amt: ReactNode; extra?: ReactNode; tone?: 'strong' | 'dim' }) {
  return (
    <div className={'pl ' + (tone ?? '')}>
      <span>{name}</span>
      <span>{extra && <span style={{ fontSize: 11, color: 'var(--good)', marginRight: 8 }}>{extra}</span>}{amt}</span>
    </div>
  );
}
