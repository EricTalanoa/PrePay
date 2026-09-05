# Prepay

A pay-period tracker for an hourly, tipped job in Washington State. Log each day
you work — clock in, clock out, lunch, tips, per-diem — and it estimates what the
next check should come to. When the real stub arrives you enter it and the
history keeps both sides side by side.

Live at <https://lustrous-puffpuff-8d6741.netlify.app/>.

Single self-contained `index.html`. No build step, no server, no account.

## Screens

- **Work day** — record a day: start/end time on a scroll wheel, lunch taken,
  credit-card tips, cash tips pocketed, and a long-distance/travel flag with a
  per-diem amount. Days can be edited or deleted after the fact.
- **Pay day** — the estimate for the current period: total hours split into
  regular and overtime, gross, an expandable deduction breakdown, and net.
- **History** — past pay periods. Real stubs show as `ACTUAL`; periods you have
  logged but not yet reconciled show as `ESTIMATE`. When a check lands, **+ Add
  the … check** creates the period prefilled from your log so you can type the
  real figures off the stub.
- **Settings** — hourly rate and raises, the spot bonus, tuition reimbursement,
  and sick-hour cash-outs.

## How the estimate is worked out

Wages are `regular hours x rate` plus `overtime hours x rate x 1.5`, overtime
accruing past 40 hours in a Saturday–Friday week.

What counts toward what is not uniform, and getting it wrong is what threw the
estimate off before:

| Amount | In gross? | In the WA premiums? | Notes |
| --- | --- | --- | --- |
| Regular and overtime pay | yes | yes | |
| Credit-card tips | yes | **no** | taxed federally, outside FLI/Cares/MLI |
| Spot bonus | yes | yes | |
| Sick-hour cash-out | yes | yes | straight time, and no Workers Comp — the hours were not worked |
| Per-diem, tuition, expenses | **no** | **no** | reimbursements, added after tax |

Deduction rates, all read off the stubs:

| Line | Rate | Levied on |
| --- | --- | --- |
| Federal income tax | 12% over $757 | gross |
| Social Security | 6.2% | gross |
| Medicare | 1.45% | gross |
| Washington FLI | 0.5433% | wages + bonus |
| Washington Cares | 0.58% | wages + bonus |
| Washington MLI | 0.2643% | wages + bonus |
| WA Workers Comp | $0.3519 / hour | hours actually worked |

Sick leave accrues at `floor(hours worked) / 40` per period.

### The three irregular lines

- **Spot bonus** — $102, and on every stub since June it has landed on the
  16th-to-end-of-month period only, not on every check. Settings has a toggle
  for the amount and for which periods it applies to.
- **Tuition reimbursement** — $1.00 per hour worked, always a period behind, and
  catching up whatever accounting skipped. A payout on a period settles hours
  through the *previous* period, so the period it appears on is still owed. It
  does not come through reliably, hence the on/off switch.
- **Sick cash-out** — accrued hours at the base rate, no overtime multiplier.
  Enter the hours in Settings and they land on the current period's estimate.

Against the 08/16–08/31 stub this reproduces gross, the bonus and the tuition
line exactly, and lands $5.08 under on net — a one-off expense reimbursement the
app has no way to anticipate. Treat the number as an estimate and check it
against the stub.

The rate lives in Settings. A raise can be set to start on either the current
pay period or the next one, and applies to whole periods rather than to dates
inside one.

## Running it

Open `index.html` in a browser, or serve the directory:

```
python3 -m http.server 8000
```

Then visit http://localhost:8000.

## The passcode

The app opens on a four-digit lock screen with its own on-screen keypad, and
unlocks for the session. This is a privacy screen for a phone left on a table —
nothing more. The code is a plain constant in the page source, so anyone who can
load the page can read it. It is not access control: do not rely on it to keep
pay data from anyone who has the URL.

## Where the data lives

Everything is in your own browser:

- `localStorage` — `prepay.days.v4` (logged days), `prepay.stubs.v1` (entered
  stubs) and `prepay.settings.v1` (rate, raise, bonus, tuition, sick)
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

Netlify deploys the repository root to
<https://lustrous-puffpuff-8d6741.netlify.app/>. `index.html` at the root is the
whole site, so there is nothing to build — `netlify.toml` pins the publish
directory and asks search engines not to index the site, since a live URL is the
only thing between the internet and the pay data baked into the page.
