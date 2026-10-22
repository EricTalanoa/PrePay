-- Prepay schema. Every row belongs to one auth user and RLS keeps it that way:
-- the publishable key in the client can read and write only the signed-in
-- user's own rows.

create table public.settings (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  default_start_min int not null default 465 check (default_start_min between 0 and 1439),
  default_lunch boolean not null default true,
  mile_rate numeric(6, 3) not null default 0.70,
  tuition_on boolean not null default true,
  tuition_rate numeric(6, 2) not null default 1.00,
  -- Sick hours as printed on a stub, and the date that balance was true.
  -- Accruals paid after that date are added and cash-outs subtracted.
  sick_balance numeric(8, 2) not null default 0,
  sick_as_of date not null default current_date,
  updated_at timestamptz not null default now()
);

-- Pay rate history. The rate for a period is the latest row whose
-- effective_from is on or before the period's first day, so a future row is a
-- scheduled raise and becomes the base rate once its date arrives.
create table public.rates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  effective_from date not null,
  rate numeric(8, 2) not null check (rate > 0),
  unique (user_id, effective_from)
);

create table public.days (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  mode text not null default 'range' check (mode in ('range', 'total')),
  start_min int check (start_min between 0 and 1439),
  end_min int check (end_min between 0 and 1439),
  total_hours numeric(6, 2),
  lunch boolean not null default true,
  cc_tips numeric(10, 2) not null default 0,
  cash_tips numeric(10, 2) not null default 0,
  travel text not null default 'none' check (travel in ('none', 'partial', 'full')),
  miles numeric(8, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index days_user_date on public.days (user_id, date);

-- A real pay stub, keyed by the first day of the period it pays.
create table public.stubs (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  reg_hours numeric(8, 2) not null default 0,
  ot_hours numeric(8, 2) not null default 0,
  cc_tips numeric(10, 2) not null default 0,
  bonus numeric(10, 2) not null default 0,
  reimbursement numeric(10, 2) not null default 0,
  tax numeric(10, 2) not null default 0,
  tax_is_estimate boolean not null default false,
  cash_tips numeric(10, 2) not null default 0,
  primary key (user_id, period_start)
);

create table public.sick_cashouts (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  period_start date not null,
  hours numeric(8, 2) not null check (hours > 0),
  primary key (user_id, period_start)
);

-- Whether tuition reimbursement landed on a given check. HR enters it by
-- hand, so the app expects it every other check and asks.
create table public.tuition_events (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  period_start date not null,
  status text not null check (status in ('received', 'missed')),
  amount numeric(10, 2) not null default 0,
  primary key (user_id, period_start)
);

do $$
declare t text;
begin
  foreach t in array array['settings', 'rates', 'days', 'stubs', 'sick_cashouts', 'tuition_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format(
      'create policy "own rows" on public.%I for all to authenticated
         using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end $$;
