# Mosaic Facilities

Facility use, filming and event requests for Mosaic — **facilities.mosaic.org**.

Same pattern as Metrics, Comms, the Planning Board and the Portal: **one file, no
build step.** `index.html` is the whole app. Push to the production branch and
Cloudflare Pages publishes it.

## What it does

| Page | Who | What |
|---|---|---|
| **Requests** | everyone | Your requests; approvers see all of them. Split list + detail, per-resource approve/decline, double-booking warning, notes (public or internal), full history. |
| **New request** | everyone | Four request types — facility use, filming & photo, event, maintenance — each with its own extra questions. Live conflict check against the space before you submit. |
| **Calendar** | everyone | Month view of everything approved or waiting. |
| **Spaces & resources** | admins | The bookable room list and the resource catalog. |

Requests move `submitted → in_review → approved / declined`, or `cancelled` by
the person who asked. Resources are decided one at a time, so a request can be
approved with the chairs and without the livestream rig.

## Sign-in

The **same Supabase project and accounts as Mosaic Metrics and the Portal**
(`iknjgrltglwupxjtegfh`). No new user system. The session is stored in a cookie
on `.mosaic.org`, so anyone already signed in at portal.mosaic.org lands here
without signing in again.

## Where the data lives

**Supabase project `Mosaic Metrics` (`iknjgrltglwupxjtegfh`), `public` schema,
tables prefixed `fac_`.** It sits with auth on purpose — RLS policies key off
`auth.uid()` and the portal's own `can(app, perm)` function, and neither works
across projects.

| Table | Holds |
|---|---|
| `fac_spaces` | Bookable rooms/areas per campus — building, capacity, bookable flag |
| `fac_resources` | The catalog: chairs, tables, AV, staffing, parking. `unit` is `qty` (counted) or `unit` (one per booking); `inventory_qty` is what's on hand |
| `fac_requests` | The request itself. `details` jsonb carries the type-specific answers (filming crew size, drone, COI…) |
| `fac_request_resources` | One row per resource asked for, with its own status |
| `fac_request_comments` | Notes; `is_internal` keeps a note off the requester's view |
| `fac_request_activity` | Every status change, written by trigger |
| `fac_blackouts` | Dates a campus or space is unavailable |
| `v_fac_requests` | Read view: request + campus + space + requester + block window |
| `fac_conflicts(space, start, end, exclude)` | Overlap check, setup/teardown included |

`schema.sql` is the whole thing, in the order it was applied.

### Permissions

Facilities is registered in the portal's own `apps` / `app_permissions` /
`role_app_defaults` tables, so access is managed from **Admin → Roles &
permissions** in the Portal alongside everything else.

| Permission | admin | staff | leader | volunteer |
|---|---|---|---|---|
| `view` | ✓ | ✓ | ✓ | ✓ |
| `submit_request` | ✓ | ✓ | ✓ | ✓ |
| `view_all` | ✓ | ✓ | | |
| `approve` | ✓ | | | |
| `manage_spaces` | ✓ | | | |

RLS enforces all of it in the database, not just the UI: you can always read the
requests you submitted, `view_all` opens the rest, `approve` is what lets a row
change status, and internal notes are invisible without it.

## Going live

1. Cloudflare → **Workers & Pages → Create → Pages → Connect to Git** → this repo.
   Framework preset **None**, build command empty, output directory `/`.
2. Custom domain `facilities.mosaic.org` in the Pages project, then a CNAME at
   GoDaddy pointing at the `*.pages.dev` address (same as portal/comms/metrics/pm).
3. **Supabase → Authentication → URL Configuration** in the `Mosaic Metrics`
   project: add `https://facilities.mosaic.org` to the **Redirect URLs**
   allowlist, so invite and password-reset emails land here.

## Before the team uses it

- **The space list is a starter set.** Nine generic rooms were seeded for Los
  Angeles so the app isn't empty on day one. Replace them with the real room
  list under Spaces & resources, and add the other campuses.
- **Resource inventory numbers are guesses** (400 chairs, 40 tables, 12 mics).
  Correct them or set them to "not tracked".
- Nothing emails or texts anyone yet. Decisions show up in the app; wiring
  notifications to Resend or Clearstream is the next phase.
