-- POV mileage, which payroll pays as "misc pay": taxed like wages and counted
-- in the regular rate the overtime premium is worked from. Tuition stays in
-- reimbursement.
alter table public.stubs add column misc_pay numeric(10, 2) not null default 0;
