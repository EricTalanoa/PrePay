import { useCallback, useEffect, useRef, useState } from 'react';
import { db, loadAll } from './db';
import { todayIso } from './lib/dates';
import { type Incoming, mergeData } from './lib/backup';
import { type Data, type Day, type Settings, type Stub, type TuitionEvent, currentRate, pendingRaise, sickLedger } from './lib/pay';

// Every change lands in local state first so the screen never waits on the
// network, then goes to Supabase. If a write fails the data is reloaded, so
// the screen shows what the database actually holds.
export function useStore(userId: string) {
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState<string | null>(null);
  const ref = useRef<Data | null>(null);
  ref.current = data;

  const reload = useCallback(async () => {
    try { setData(await loadAll()); setError(null); }
    catch (e) { setError((e as Error).message); }
  }, []);

  useEffect(() => { setData(null); reload(); }, [userId, reload]);

  const apply = useCallback((next: (d: Data) => Data, write: () => Promise<unknown>) => {
    if (!ref.current) return;
    setData(next(ref.current));
    write().catch(e => { setError((e as Error).message); reload(); });
  }, [reload]);

  const today = todayIso();

  const actions = {
    saveDay: (day: Day) => apply(
      d => ({ ...d, days: d.days.filter(x => x.id !== day.id).concat(day) }),
      () => db.saveDay(day)),
    deleteDay: (id: string) => apply(
      d => ({ ...d, days: d.days.filter(x => x.id !== id) }),
      () => db.deleteDay(id)),
    setSettings: (patch: Partial<Settings>) => {
      if (!ref.current) return;
      const s = { ...ref.current.settings, ...patch };
      apply(d => ({ ...d, settings: s }), () => db.saveSettings(s));
    },
    // Editing the base rate edits whichever rate is in force today.
    setBaseRate: (rate: number) => {
      if (!ref.current || !(rate > 0)) return;
      const from = currentRate(ref.current.rates, today)?.effectiveFrom ?? '2000-01-01';
      apply(d => ({ ...d, rates: d.rates.filter(r => r.effectiveFrom !== from).concat({ effectiveFrom: from, rate }) }),
        () => db.saveRate({ effectiveFrom: from, rate }));
    },
    scheduleRaise: (rate: number, from: string) => {
      if (!ref.current || !(rate > 0)) return;
      const old = pendingRaise(ref.current.rates, today);
      apply(d => ({ ...d, rates: d.rates.filter(r => r !== old && r.effectiveFrom !== from).concat({ effectiveFrom: from, rate }) }),
        async () => { if (old && old.effectiveFrom !== from) await db.deleteRate(old.effectiveFrom); await db.saveRate({ effectiveFrom: from, rate }); });
    },
    clearRaise: () => {
      const old = ref.current && pendingRaise(ref.current.rates, today);
      if (old) apply(d => ({ ...d, rates: d.rates.filter(r => r !== old) }), () => db.deleteRate(old.effectiveFrom));
    },
    saveStub: (s: Stub) => apply(
      d => ({ ...d, stubs: d.stubs.filter(x => x.periodStart !== s.periodStart).concat(s) }),
      () => db.saveStub(s)),
    deleteStub: (key: string) => apply(
      d => ({ ...d, stubs: d.stubs.filter(x => x.periodStart !== key) }),
      () => db.deleteStub(key)),
    setCashout: (periodStart: string, hours: number) => apply(
      d => ({ ...d, cashouts: d.cashouts.filter(c => c.periodStart !== periodStart).concat(hours > 0 ? [{ periodStart, hours }] : []) }),
      () => db.saveCashout({ periodStart, hours })),
    // The balance typed in is "available right now", after any cash-out that
    // is scheduled but not yet paid, so those are added back to the anchor.
    setSickAvailable: (hours: number) => {
      if (!ref.current) return;
      const at = { ...ref.current, settings: { ...ref.current.settings, sickBalance: 0, sickAsOf: today } };
      const pending = -sickLedger(at, today).available;
      actions.setSettings({ sickBalance: hours + pending, sickAsOf: today });
    },
    setTuition: (key: string, e: Omit<TuitionEvent, 'periodStart'> | null) => apply(
      d => ({ ...d, tuition: d.tuition.filter(x => x.periodStart !== key).concat(e ? [{ periodStart: key, ...e }] : []) }),
      () => db.saveTuition(key, e)),
    // Adds a backup or the old app's data to the account; nothing already
    // there is lost, and a day in both isn't doubled.
    mergeIn: async (incoming: Incoming) => {
      if (!ref.current) return;
      const next = mergeData(ref.current, incoming);
      const kept = new Set(next.days.map(d => d.id));
      const dropped = ref.current.days.filter(d => !kept.has(d.id)).map(d => d.id);
      setData(next);
      try { await db.writeMerged(next, dropped); } catch (e) { setError((e as Error).message); }
      await reload();
    },
  };

  return { data, error, clearError: () => setError(null), actions };
}

export type Actions = ReturnType<typeof useStore>['actions'];
