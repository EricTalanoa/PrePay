-- Roth 401(k): percent of gross taken after tax, and the first period it
-- comes out of.
alter table public.settings
  add column roth_pct numeric(5, 2) not null default 0 check (roth_pct between 0 and 100),
  add column roth_from date;
