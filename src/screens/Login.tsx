import { useState } from 'react';
import { supabase } from '../supabase';

export function Login() {
  const [err, setErr] = useState<string | null>(null);
  const go = async (provider: 'google' | 'apple') => {
    setErr(null);
    const { error } = await supabase.auth.signInWithOAuth({
      provider, options: { redirectTo: window.location.origin + window.location.pathname },
    });
    if (error) setErr(error.message);
  };
  return (
    <div className="login">
      <div className="brand">Prepay</div>
      <div className="rule" />
      <div className="muted" style={{ fontSize: 14 }}>Know the check before it lands.</div>
      <div className="btns">
        <button className="btn" onClick={() => go('apple')}>
          <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.75-.78-2.88-.76-1.48.02-2.84.86-3.6 2.19-1.54 2.66-.39 6.6 1.1 8.76.73 1.06 1.6 2.24 2.74 2.2 1.1-.04 1.52-.71 2.85-.71 1.33 0 1.7.71 2.87.69 1.18-.02 1.93-1.08 2.65-2.14.84-1.22 1.18-2.41 1.2-2.47-.03-.01-2.3-.88-2.3-3.52ZM14.2 6.13c.6-.74 1.01-1.75.9-2.77-.87.04-1.93.58-2.55 1.31-.56.64-1.05 1.68-.92 2.67.97.08 1.96-.49 2.57-1.21Z"/></svg>
          Continue with Apple
        </button>
        <button className="btn ghost" onClick={() => go('google')}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285F4" d="M23.5 12.27c0-.85-.08-1.66-.22-2.45H12v4.63h6.46a5.52 5.52 0 0 1-2.4 3.62v3h3.88c2.27-2.09 3.56-5.17 3.56-8.8Z"/><path fill="#34A853" d="M12 24c3.24 0 5.96-1.07 7.94-2.9l-3.88-3.01c-1.07.72-2.45 1.15-4.06 1.15-3.12 0-5.77-2.11-6.71-4.95H1.28v3.1A12 12 0 0 0 12 24Z"/><path fill="#FBBC05" d="M5.29 14.29a7.2 7.2 0 0 1 0-4.58v-3.1H1.28a12 12 0 0 0 0 10.78l4.01-3.1Z"/><path fill="#EA4335" d="M12 4.77c1.76 0 3.34.6 4.59 1.8l3.44-3.44A11.5 11.5 0 0 0 12 0 12 12 0 0 0 1.28 6.61l4.01 3.1C6.23 6.88 8.88 4.77 12 4.77Z"/></svg>
          Continue with Google
        </button>
      </div>
      {err && <div className="label warn">{err}</div>}
    </div>
  );
}
