# Mosaic Portal

The staff portal for Mosaic — one front door for the tools the team already uses:

| App | Live link | Repo / backend |
|---|---|---|
| **Portal home** (this repo) | [portal.mosaic.org](https://portal.mosaic.org) | `mosaicportal` · auth via the Mosaic Metrics Supabase |
| Metrics | [metrics.mosaic.org](https://metrics.mosaic.org) | `mosaic-metrics` · Supabase `Mosaic Metrics` (`iknjgrltglwupxjtegfh`) |
| Comms | [comms.mosaic.org](https://comms.mosaic.org) | `mosaic-comm` · Supabase `mosaic-comm` (`yrviwbqhjcrlxgozrgay`) |
| Planning Board | [pm.mosaic.org](https://pm.mosaic.org) | `mosaicprojectmanagement` · Supabase `mosaic-comm` |
| Goals | [mosaic-hub.replit.app](https://mosaic-hub.replit.app) | `goaltrackerv2` (Replit) |

## What this repo is

**One file, no build step** — `index.html`, same pattern as Metrics and the
Planning Board. It is **Loyda's portal design (July 2026 handoff package)**
behind one login: Home + Calendar are native, the other sections link out to
the apps that already exist. The full handoff lives in `docs/` — build spec,
style guide, design tokens, event-card component, and Loyda's README. Read
`docs/mosaic-portal-build-spec.md` before changing anything visual.

- **Sign-in** uses the **same Supabase project and accounts as Mosaic
  Metrics** (`iknjgrltglwupxjtegfh`). Every existing Metrics user (16 today),
  their role (admin / staff / volunteer / leader), invites, and password
  resets work here unchanged. No new user system was created. (Note: the
  build spec proposed Google Workspace sign-in instead — the Metrics-accounts
  decision is Hannita's; revisit together if it needs to change.)
- Roles map to the spec's presets: admin → Leadership, staff → Comms,
  leader → Ops, volunteer → Volunteer lead. The Settings role switcher still
  works on top of that default (prototype behavior).
- **Calendar/Home data is still the prototype's sample data** (late July–Aug
  2026). Wiring it to read the Planning Board + Comms live data is the next
  phase; per the spec, the four apps stay the systems of record and the
  portal reads and arranges only.
- **This repo touches nothing else.** It has its own repo and its own
  Cloudflare Pages project — Metrics, Comms, and the Planning Board deploy
  independently and cannot be affected by changes here.

## Going live (one-time setup)

_Done — live since Aug 12, 2026._ For reference:

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
