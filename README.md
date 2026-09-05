# PrePay

A paycheck estimator for Washington State. Log the hours you worked each day,
and it works out what the check should come to before it arrives — then lets you
compare that against the stub once it does.

## What it covers

- **Hours** — regular, overtime, and reimbursements (added after tax rather than
  taxed as wages)
- **Deductions** — federal income tax, Social Security, WA Workers Comp,
  Washington Cares, and Washington FLI/MLI, with a per-line breakdown you can
  show or hide
- **Days** — a running log you can add to and edit
- **Backups** — export every logged day as text and import it back on another
  device or browser

## Running it

`index.html` is a single self-contained file. There is no build step and no
install: open it in a browser, or serve the directory.

```
python3 -m http.server 8000
```

Then visit http://localhost:8000.

## Where your data lives

Everything stays in your own browser's `localStorage` (under the `prepay.*`
keys). The page makes no network requests and sends nothing anywhere, which also
means clearing site data wipes your logged days — use **Export days** to keep a
backup.

Because it is browser-local, the same log will not follow you between devices or
browsers on its own. Export from one and import into the other.
