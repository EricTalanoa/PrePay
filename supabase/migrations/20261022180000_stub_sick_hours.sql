-- Sick hours cashed out on a check. Sick pay is part of gross, at straight time.
alter table public.stubs add column sick_hours numeric(8, 2) not null default 0;
