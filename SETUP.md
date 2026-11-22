# Mecca Books — setup guide

Mecca Books runs on **your own server account** (Supabase) and **your own website** (GitHub Pages).
Staff sign in with a **username and password you give them**, with no claude.ai or other account needed.

Allow about 30–45 minutes. Steps 1–5 are best done on a PC.

---

## 1. Create the Supabase project (the server)

1. Go to **supabase.com** → *Start your project* → sign up (use the business email).
2. *New project*:
   - **Name:** `meccabooks`
   - **Database password:** make a strong one and **keep it safe** (you'll rarely need it).
   - **Region:** South Africa isn't offered at the moment, so choose a **Europe** region (e.g. Frankfurt or London).
3. Plan: you can start on **Free** while setting up. **Upgrade to Pro (about $25/month) before you start using it for real.** Pro gives daily backups, and free projects pause after a week without use.

## 2. Create the database

1. In your project, open **SQL Editor** → **New query**.
2. Open the file **`supabase/schema.sql`**, copy **everything**, and paste it in.
3. At the very bottom, check the owner login: `'vivian', 'Vivian Lohrmann'`. Change it if you want a different username.
4. Press **Run**. You should see *Success. No rows returned*.

## 3. Two settings + your connection details

1. **Authentication → Sign In / Providers → Email**:
   - turn **OFF** "Confirm email" (logins are usernames, so no emails are sent)
   - leave **"Allow new users to sign up" ON** (the database only lets in people *you* add)
2. **Project Settings → API** (on newer dashboards: *API Keys*). Copy:
   - the **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - the **anon public** key (newer projects call it the **publishable** key)
3. Put both into **`config.js`**:
   ```js
   url: "https://abcdefgh.supabase.co",
   anonKey: "the-long-key-you-copied",
   ```
   The anon/publishable key is meant to be public. Security is enforced by the database rules, not by hiding this key.
   **Never** put the *service_role* / *secret* key in the app.

## 4. Put the app on GitHub

1. Create a new repository called **`meccabooks`** (Public is fine: no business data is stored in it, only the program).
2. Upload **all** the files and folders from this package, including the `.github` folder and the `config.js` you filled in.
   *Easiest:* ask Claude to push it for you: create the empty repo, then say "push Mecca Books to my meccabooks repo".

## 5. Switch on the website

1. In the repo: **Settings → Pages → Source: GitHub Actions**.
2. Open the **Actions** tab. Wait for **"Publish website"** to turn green (1–2 minutes).
3. Your app is now at **`https://YOUR-GITHUB-NAME.github.io/meccabooks/`**. That's the address everyone uses.
   (Optional later: a nicer address such as `books.secmec.co.za` via *Settings → Pages → Custom domain*.)

## 6. Your first sign-in (owner)

1. Open the address → tap **"Create the owner login"**.
2. Username **vivian** (or what you set in step 2), your name, and a strong password (8+ characters) → **Create owner login**.
3. You're in, with full access. This only works once.

## 7. Set up the books

1. **Chart of Accounts** → **Set up Richards Bay books**. Switch the branch (side menu) to **Vereeniging** → **Set up Vereeniging books**.
2. **Setup** (do it for each branch: switch branch in the side menu):
   - company name, address, VAT and registration numbers, **banking details** (printed on invoices)
   - **Price levels**: Trade 20%, Special 35%, Retail 40% are set as **margin**. If you meant **markup** (cost + 20%), change it here.
   - **Sign-in security**: auto sign-out after 30 idle minutes (protects shared till PCs).
3. Add stock items, customers and suppliers per branch.

## 8. Add your staff (up to 30 or more, no licence fees)

1. **Users & Access → + Add user**: full name, username (e.g. `thabo`), starting password.
2. Tick what they may do, or tap a preset (**Cashier / Sales / Bookkeeper / Manager**), and **tick their branch(es)**.
3. **Create login**: a card shows the web address, username and password to give them.
4. They can change their password after signing in (button under their name in the side menu).

**Day to day:**
- **Reset password**: when someone forgets theirs.
- **Disable**: stops that person immediately on all devices. Their history stays in the Audit Trail.
- **Audit Trail**: every create/edit/delete with who, when, branch and what changed. The database writes it, so nobody can alter it.

## 9. Get it on Android phones

**Option A: install from Chrome (recommended, updates itself)**
1. Open the app address in **Chrome** on the phone.
2. Menu **⋮** → **Add to Home screen** (or **Install app**).
3. Mecca Books appears with its own icon and opens full screen.

**Option B: APK file**
1. In the GitHub repo: **Actions → Build Android APK → Run workflow**.
2. When it's green, open the run and download **MeccaBooks-APK** (bottom of the page), then unzip it.
3. Copy `MeccaBooks.apk` to the phone and open it (allow "install unknown apps" when asked).
   When you change the app later, run the build again and reinstall to update.

---

## Good to know

- **Internet needed:** the app works live against the server, so devices need data or Wi-Fi to capture.
- **What the server itself enforces** (even if someone tampers with the app):
  - branch separation (staff only receive their own branch's data)
  - deletes need the *Delete records* tick
  - chart of accounts, Setup and price/cost changes need their ticks
  - nobody can change their own access
  - the Audit Trail can't be edited
- **What the app enforces:** which screens appear, and hiding cost prices and profit. A technically skilled person with a valid login could still read their own branch's cost prices from the server.
- **Backups:** included on Supabase Pro (daily). *Setup → Export all data* also gives you a file copy at any time.
- **Costs:** Supabase Pro about $25/month. GitHub is free. No per-user fees.

## Troubleshooting

| Message | Fix |
|---|---|
| "there's no invitation for that username" (owner) | The owner username doesn't match step 2. In SQL Editor run: `insert into invites(username, full_name, is_owner) values ('yourname','Your Name', true);` |
| "Supabase wants an email confirmation" | Step 3.1: turn **Confirm email** off, then sign in. |
| "Not connected yet" | `config.js` still has the placeholder values (step 3.3). |
| "Not saved — you don't have the right to do that" | That user's ticks don't allow it. Change them in Users & Access. |
| Adding many users quickly fails | Supabase limits sign-ups per hour from one connection. Wait a while and continue. |
