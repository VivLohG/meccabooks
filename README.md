# Mecca Books

Accounting, point of sale and stock for **The Security Mecca** (Richards Bay & Vereeniging).
Original software owned by The Security Mecca: no licence fees, no per-user fees.

- Double-entry books per branch (separate charts, combined reports), VAT, debtors/creditors
- Point of sale with daily cash-up by SA note/coin, six price levels per product
- Quotes → invoices, supplier bills with invoice photos, payments & receipts, bank import with auto-allocation
- Projects, stock per branch with transfers, audit trail
- Own usernames & passwords with tick-box access per person, enforced by the database

**To install, follow [SETUP.md](SETUP.md).**

| Folder / file | What it is |
|---|---|
| `index.html` | the app |
| `config.js` | your Supabase connection (fill in during setup) |
| `supabase/schema.sql` | the database: run once in Supabase |
| `.github/workflows/` | publishes the website and builds the Android APK |
| `manifest.webmanifest`, `sw.js`, `icons/` | lets phones install it like an app |
| `vendor/supabase.js` | the Supabase client library |
