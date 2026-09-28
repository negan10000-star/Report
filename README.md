# Daily Progress Report — Supabase + GitHub Pages

Static single-file front end (`index.html`) + Supabase (Postgres). No accounts: two PINs, like the original Apps Script version.

## How access works
- One PIN for employees (submit reports), one for managers (view reports + attendance).
- PINs are stored **hashed** in `pin_secrets`. The tables are closed to the public key; all reads/writes go through
  server functions (`supabase/pin_auth.sql`) that check the PIN on every call.
- 10 wrong PINs from one IP locks that IP for 10 minutes.
- `reports` is append-only: the app has no edit/delete function. Corrections are new rows with a note.

## Setup
1. Supabase SQL editor: run `supabase/schema.sql`, then `supabase/pin_auth.sql`.
2. Set your PINs (SQL editor):
   ```sql
   delete from pin_secrets;
   insert into pin_secrets values ('staff',   extensions.crypt('EMPLOYEE_PIN', extensions.gen_salt('bf')));
   insert into pin_secrets values ('manager', extensions.crypt('MANAGER_PIN',  extensions.gen_salt('bf')));
   ```
3. Put your project URL and anon/publishable key at the top of the `<script>` in `index.html`.
4. Push to GitHub, Settings → Pages → deploy from `main` / root.

`teardown_accounts.sql` is only for removing the earlier account-based version.
