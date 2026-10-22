import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './supabase';
import { upcomingPeriod } from './lib/dates';
import type { Data, Day } from './lib/pay';
import { useStore } from './store';
import { Login } from './screens/Login';
import { WorkDay, blankDay, endNow } from './screens/WorkDay';
import { PayDay } from './screens/PayDay';
import { History } from './screens/History';
import { Settings } from './screens/Settings';

type Tab = 'day' | 'pay' | 'history' | 'settings';

export function App() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);
  if (session === undefined) return <div className="login"><div className="brand">Prepay</div></div>;
  if (!session) return <Login />;
  return <Signed session={session} />;
}

function Signed({ session }: { session: Session }) {
  const { data, error, clearError, actions } = useStore(session.user.id);
  if (!data) {
    return (
      <div className="login">
        <div className="brand">Prepay</div>
        <div className={'label' + (error ? ' warn' : '')}>{error ?? 'Loading…'}</div>
      </div>
    );
  }
  return <Main data={data} actions={actions} error={error} clearError={clearError} email={session.user.email ?? ''} />;
}

function Main({ data, actions, error, clearError, email }: {
  data: Data; actions: ReturnType<typeof useStore>['actions']; error: string | null; clearError: () => void; email: string;
}) {
  const [tab, setTab] = useState<Tab>('day');
  const [draft, setDraftState] = useState<Day>(() => blankDay(data));
  const [editing, setEditing] = useState(false);
  const [, tick] = useState(0);

  // re-render every few minutes so the 7 AM pay-day rollover happens without a reload
  useEffect(() => {
    const t = window.setInterval(() => tick(x => x + 1), 5 * 60 * 1000);
    return () => window.clearInterval(t);
  }, []);

  const pay = upcomingPeriod();
  const setDraft = (patch: Partial<Day>) => setDraftState(d => ({ ...d, ...patch }));
  const edit = (d: Day) => { setDraftState({ ...d }); setEditing(true); setTab('day'); window.scrollTo(0, 0); };
  const reset = () => { setDraftState(blankDay(data)); setEditing(false); };

  const go = (t: Tab) => {
    // clock-out tracks "now" whenever a new day is opened, never mid-edit
    if (t === 'day' && !editing) setDraft({ endMin: endNow(draft.startMin) });
    setTab(t);
    window.scrollTo(0, 0);
  };

  return (
    <div className="app">
      {error && <div className="toast"><span>{error}</span><button onClick={clearError}>✕</button></div>}
      {tab === 'day' && (
        <WorkDay data={data} draft={draft} setDraft={setDraft} editing={editing}
          onSave={() => { actions.saveDay({ ...draft, id: draft.id || crypto.randomUUID() }); reset(); setTab('pay'); }}
          onDelete={() => { actions.deleteDay(draft.id); reset(); }} />
      )}
      {tab === 'pay' && <PayDay data={data} pay={pay} actions={actions} onEdit={edit} />}
      {tab === 'history' && <History data={data} pay={pay} actions={actions} onEdit={edit} />}
      {tab === 'settings' && <Settings data={data} pay={pay} actions={actions} email={email} onSignOut={() => supabase.auth.signOut()} />}
      <nav className="nav">
        {([['day', 'Work day'], ['pay', 'Pay day'], ['history', 'History'], ['settings', 'Settings']] as const).map(([k, l]) => (
          <button key={k} className={tab === k ? 'on' : ''} onClick={() => go(k)}>{l}</button>
        ))}
      </nav>
    </div>
  );
}
