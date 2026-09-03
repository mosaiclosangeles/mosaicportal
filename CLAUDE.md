# Mosaic Portal

One front door for the Mosaic staff tools: Home and Calendars are native, and
Metrics, Comms, Planning and Goals are embedded live from their own sites.

- **Live at** `portal.mosaic.org` (Cloudflare Pages, deploys on push)
- **The whole app is `index.html`** — one file, no build step
- **Sign-in** uses the Mosaic Metrics Supabase project, shared across
  `*.mosaic.org` by a cookie, so the embedded apps do not ask again

## The embedded apps are not copies

The portal loads each app live from its own address, so a change shipped to
Metrics, Comms, Planning, Facilities or Goals appears here with no deploy.
Three things are the portal's own and do not follow automatically: **Home and
Calendars**, which read the planning, comms and facilities data directly, and
the **Goals and Facilities sub-menus**, which are hand-written lists in
`GOALS_NAV` and `FAC_NAV` — a page added inside either app has to be added
there too, or it will not appear in the portal.

**Adding a section takes four edits, not one.** Facilities shipped broken
because only three were made: the rail entry, the sub-menu and the embed URL
were there, and the router was not, so clicking Facilities fell through the
`S.section===` chain to its final `else` — which is Settings. Whenever a
section is added, all four have to move together:

| Edit | Miss it and |
|---|---|
| `SECTIONS` | there is no rail button |
| the `S.section===` chain in `render()` | the button shows the Settings page |
| `SECTION_PATH` + `PATH_SECTION` | the URL never changes, and a deep link 404s into Home |
| the `closest(...)` list at the top of the click handler | `data-` buttons in that section are dead, because nothing reaches the handler |

That last one is the least obvious: the delegated click handler starts with one
long `closest()` selector, and an attribute missing from it never gets as far
as its `if`. The Facilities sub-menu was inert for exactly that reason.

**The portal hands its sign-in to the apps it frames.** An embedded app posts
`mosaic-auth-request` to its parent and the portal replies with the session;
the app calls `setSession()` and gets in. This exists because the cookie on
`.mosaic.org` is not readable in every window — a private one is where it
failed — and because Chrome is narrowing what a framed page may read from
storage. Both ends check the other's origin against `*.mosaic.org` and post
to that exact origin, never `"*"`.

**An embedded app must run with `autoRefreshToken:false`.** Refresh tokens
rotate on use. Two clients refreshing one cookie means whichever goes second
spends a token the first already spent, gets a 400 and drops its session —
which is precisely how Facilities came to show a password box inside a portal
the person had just signed into. The portal is the only client that refreshes.

**Facility bookings are a fifth calendar source.** `loadFacilities()` reads
`v_fac_requests` out of the same Supabase project with the signed-in person's
own session, so RLS decides what they see. It draws `block_start`/`block_end`
rather than `start_at`/`end_at`: a booking is the room being unavailable, and
that includes setup and teardown — reading `start_at` would show a 2pm setup
as a 5pm wedding and leave the room apparently free at three.

## Somebody already decided this — ask before undoing it

Several people work on these apps, through several separate Claude sessions
that cannot see each other's conversations. **Before changing existing wording,
layout, behaviour or configuration — not just before adding something — find
out whether someone chose it on purpose. If they did, say so and ask, rather
than changing it and mentioning it afterwards.**

Say it like this, with the name and the date:

> Paola set this up on 6 Aug (commit `a06b0d2`) — changing it would undo that.
> Do you want me to?

Who you are most likely to be touching:

| Who | Usually owns |
|---|---|
| **Hannita** (hannita@mosaic.org) | the portal, admin and permissions, integrations |
| **Loyda** (loyda@mosaic.org) | design and wording, the Rhythm, Goals |
| **Paola** (paola.mejia@mosaic.org) | comms automations, permissions groundwork |
| **Austin** (austin@mosaic.org) | repos and infrastructure setup |
| **Another Claude session** | commits authored by `Claude` — same rules apply |

**A commit says a session made it, never which person was driving it.** Hannita
and Paola both work through a second Claude account, and everything either of
them ships is authored by `Claude` all the same. So never resolve a `Claude`
commit to a person, and never treat one as your own session's work — say what
the commit changed and when, and ask. Guessing "that was you" is how a
collision gets waved through.

**Fetch before you look.** The other session pushes to the same branch, so a
working copy can be behind without saying so, and a `grep` of a stale file
reads exactly like a fact. `git fetch` first, then check — reporting "there is
no X here" off an unfetched checkout has already sent one design down the wrong
road.

How to find out, in about a minute:

- `git log -S"<the exact text you are about to change>" -- <file>` — who last
  touched that string, and when
- `git blame -L <line>,<line> <file>`
- the commit message and PR description
- anything already established earlier in the current conversation

This is best-effort: a decision made verbally or in a channel this session
cannot read will not show up. Say so plainly rather than implying a more
thorough check than actually happened.
