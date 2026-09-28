# Daily Progress Report — Supabase + GitHub Pages

Static single-file front end (`index.html`) + Supabase (Postgres, Auth, RLS). No server to run.

## Setup
1. Create a Supabase project, run `supabase/schema.sql` in the SQL editor.
2. Put your project URL and anon key at the top of the `<script>` in `index.html`.
3. Sign up in the app, then promote yourself:
   `update profiles set role='manager' where user_id=(select id from auth.users where email='you@company.com');`
4. Push to GitHub, then Settings → Pages → deploy from `main` / root.
5. In Supabase → Authentication → URL Configuration, add your GitHub Pages URL.

## Design notes
- Shared PINs replaced by real accounts (`staff` / `manager`) enforced with Row Level Security.
- `reports` is append-only: no UPDATE/DELETE policies, so past reports cannot be edited; corrections are new rows.
- The anon key is safe to publish; RLS is what protects data.
