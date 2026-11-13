-- Hours worked on a holiday, paid at time and a half. Their own line on the
-- stub, apart from regular and overtime.
alter table public.stubs add column hol_hours numeric(8, 2) not null default 0;
