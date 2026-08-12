# Mosaic Portal

The staff portal for Mosaic — one front door for the tools the team already uses:

| App | Live link | Repo / backend |
|---|---|---|
| **Portal home** (this repo) | _pending Cloudflare Pages setup_ | `mosaicportal` · auth via the Mosaic Metrics Supabase |
| Metrics | [metrics.mosaic.org](https://metrics.mosaic.org) | `mosaic-metrics` · Supabase `Mosaic Metrics` (`iknjgrltglwupxjtegfh`) |
| Comms | [comms.mosaic.org](https://comms.mosaic.org) | `mosaic-comm` · Supabase `mosaic-comm` (`yrviwbqhjcrlxgozrgay`) |
| Planning Board | [pm.mosaic.org](https://pm.mosaic.org) | `mosaicprojectmanagement` · Supabase `mosaic-comm` |
| Goals | [mosaic-hub.replit.app](https://mosaic-hub.replit.app) | `goaltrackerv2` (Replit) |

## What this repo is

**One file, no build step** — `index.html`, same pattern as Metrics and the
Planning Board. It is the portal *shell* from the 2-week plan: **one login at
the front door + the weekly master calendar home + nav to the four apps.**

- **Sign-in** uses the **same Supabase project and accounts as Mosaic
  Metrics** (`iknjgrltglwupxjtegfh`). Every existing Metrics user (16 today),
  their role (admin / staff / volunteer / leader), invites, and password
  resets work here unchanged. No new user system was created.
- The home calendar is currently the **display prototype** (hardcoded program
  year, edits don't persist — the page says so). Wiring it to read the
  Planning Board's live Supabase data is the next phase; the Planning Board at
  pm.mosaic.org stays the source of truth for planning work.
- **This repo touches nothing else.** It has its own repo and will have its own
  Cloudflare Pages project — Metrics, Comms, and the Planning Board deploy
  independently and cannot be affected by changes here.

## Going live (one-time setup)

1. Cloudflare dashboard → **Workers & Pages → Create → Pages → Connect to
   Git** → pick `mosaiclosangeles/mosaicportal`.
2. Framework preset: **None**. Build command: _(empty)_. Output directory: `/`.
3. Set the production branch (use `main` once this branch is merged).
4. Custom domain: add e.g. `portal.mosaic.org` in the Pages project, then a
   CNAME record at GoDaddy pointing to the `*.pages.dev` address (same as
   comms/metrics/pm).
5. **Supabase → Authentication → URL Configuration**: add the portal's URL to
   the **Redirect URLs** allowlist in the `Mosaic Metrics` project, so invite
   and password-reset emails can land on the portal.

After that, every push to the production branch publishes automatically —
there is no separate deploy step.

## Roadmap (from the 2-week plan canvas)

- Phase 1 (this): shell — one login, calendar home, app nav. ✅
- Phase 2: calendar home reads live event data (Planning Board Supabase);
  Metrics + Comms overlays.
- Later: app-by-app backend merge into one shared Supabase; permissions
  editable by admins; Team/HR area; notification center.
