# Prepay

A pay-period tracker for an hourly, tipped job in Washington State. Log each day
you work — clock in, clock out, lunch, tips, per-diem — and it estimates what the
next check should come to. When the real stub arrives you enter it and the
history keeps both sides side by side.

Single self-contained `index.html`. No build step, no server, no account.

## Screens

- **Work day** — record a day: start/end time on a scroll wheel, lunch taken,
  credit-card tips, cash tips pocketed, and a long-distance/travel flag with a
  per-diem amount. Days can be edited or deleted after the fact.
- **Pay day** — the estimate for the current period: total hours split into
  regular and overtime, gross, an expandable deduction breakdown, and net.
- **History** — past pay periods, with the actual stub figures you entered.

## How the estimate is worked out

Wages are `regular hours x rate` plus `overtime hours x rate x 1.5`. Tips are
added to gross and taxed; per-diem is added after tax as an untaxed
reimbursement.

Deductions applied to the estimate:

| Line | Basis |
| --- | --- |
| Federal income tax | 12% of gross over $757 |
| Social Security | 6.2% of gross |
| Medicare | 1.45% of gross |
| Washington FLI | 0.5433% of wages |
| Washington Cares | 0.58% of wages |
| Washington MLI | 0.2643% of wages |
| WA Workers Comp | $0.3519 per hour worked |

These are flat approximations, not a payroll engine — no W-4 allowances, no
year-to-date wage caps, no bracket changes. Treat the number as an estimate and
check it against the stub.

The hourly rate, the overtime multiplier and every rate above are constants near
the top of the app script inside `index.html`.

## Running it

Open `index.html` in a browser, or serve the directory:

```
python3 -m http.server 8000
```

Then visit http://localhost:8000.

## The passcode

The app opens on a four-digit lock screen and unlocks for the session. This is a
privacy screen for a phone left on a table — nothing more. The code is a plain
constant in the page source, so anyone who can load the page can read it. It is
not access control: do not rely on it to keep pay data from anyone who has the
URL.

## Where the data lives

Everything is in your own browser:

- `localStorage` — `prepay.days.v4` (logged days) and `prepay.stubs.v1` (entered
  stubs)
- `sessionStorage` — `prepay.ok`, the unlock flag, cleared on reload

The page makes no network requests; React and the fonts are inlined into the
file. Nothing is sent anywhere and nothing syncs, which cuts both ways: the log
does not follow you between devices or browsers, and clearing site data wipes
it. Use **Export** on the History screen to copy a backup out as text, and
**Import** to paste it back in elsewhere.

Until you log a day of your own, the app shows a set of built-in sample days and
stubs so the screens are not empty. These are hardcoded in `index.html` and are
overwritten as soon as real data exists in `localStorage`.

## Deploying

`index.html` at the repository root is the whole site — publish the root
directory. `netlify.toml` sets that, and asks search engines not to index the
site, since a live URL is the only thing between the internet and the pay data
baked into the page.
