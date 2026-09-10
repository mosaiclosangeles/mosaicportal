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

**The Metrics sub-menu is a hand-written copy of Metrics' own tabs**, in
`METRICS_NAV`, and `metricsNavItems()` filters it by `METRICS_ROLE_TABS` — a
deliberate duplicate of `ROLE_TABS` in mosaic-metrics. Two things follow: a tab
added inside Metrics has to be added here too or it will not appear in the
portal, and a tab a role cannot see must not be offered here either. Metrics
bounces a role to Overview rather than erroring, which is worse than an error —
the tab reads as clicked and quietly is not the page that was asked for. The
same is true of the view the frame is sent: `pageEmbed('numbers')` falls back
to Overview rather than asking for a view the rail does not offer.

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

**The calendar has three sources, and they are not the item types.**
`SOURCES` (Mosaic Calendar / Staff / Facilities) is a filter chip over one or
more item types — Staff covers both `other` and `away`, and `comms` maps to no
source at all, so it never draws. Filter through `shown(e)`, never through
`S.filters.has(e.type)`, or the rows Loyda asked to be folded together come
apart again. `tests/drive-portal.mjs` asserts the three by name.

**A comm belongs to an event by subject, not by date.** `comm_events` carries
no reference to the item it serves, so the link is inferred: `commRelated()`
asks whether every distinctive word in the *comm's* name appears in the event's
(`subjectWords()` strips the channel and timing words — email, text, promo,
weekday names — and stems plurals), and `commWindow()` limits it to the item's
own Kick-Off→Debrief runway from the mirror, or ±21 days without one. It reads
one way on purpose: a comm is named more narrowly than the event it serves, so
"Bible Studies" reaches "Regional Bible Studies" but "ERM Text" reaches neither
Team Huddle nor Men's Camp. Same-day was the first rule and it hung two ERM
sends off a staff birthday; exact title was the second and matched almost
nothing. The lasting fix is upstream — an item reference on `comm_events` —
after which this becomes an exact match.

**The calendar has two views, and an entry opens a card over them.** Month is
where it opens; List is the same month read down the page. Both draw from
`evOn()`, so a day cannot show one thing in the grid and another in the list.
Clicking an entry calls `openCard()` — a centred dialog over whatever you were
reading, closed by its ×, the scrim or Escape. It is deliberately **not** a
section: `pageEvent()` renders into the overlay, there is no URL for it and no
history entry, because the page behind it has not changed. The old full-page
`event` section (and its Back button) is gone; so is the week grid, which
Loyda's review called "really off", and which was a second grid to keep in
step with the first.

**A location that is a link is "Online", and a link is followable.** Outlook
keeps the meeting URL in the location field, so an Arena call arrived with a
70-character Zoom address standing where the room should be — in the card's
subtitle, in the list, and a third time under Where, none of them clickable.
`placeOf()` answers where it is (a hybrid location keeps its room and gains
"· Online"), `meetLink()` answers how to get in, and `linkify()` — escape
first, then anchor — makes any address left in the text followable. The URL is
never dropped from the data, only from the place: a card that quietly lost the
only way into the meeting would be worse than an ugly one. Hannita, 10 Sep.

**An embedded app can ask the portal to move, and the ask has two halves.**
`mosaic-can-navigate` is answered with `mosaic-navigate-ok` at load time, and
`mosaic-navigate` moves the section and replies `mosaic-navigated`. Both
matter: a frame cannot tell whether the portal listens, and finding out by
trying is worse than it sounds — the answer arrives after the click, and a
`window.open` from a frame with no user gesture behind it is silently blocked,
so the facilities card renders a button or a plain link depending on the reply.
`NAV_ALLOWED` lists the sections that may be arrived at this way and the fields
each may carry; **Planning belongs in it** — it is the section the facilities
event card actually asks for, and leaving it out sends that click to a new tab,
which is the thing Hannita asked to be rid of. A bare move (no page, no params)
books no form: defaulting it to `page=new` landed people on the board's
new-item form when all they clicked was the name of the app they were reading.

**Facility bookings are one of those sources.** `loadFacilities()` reads
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

How to find out, in about a minute:

- `git log -S"<the exact text you are about to change>" -- <file>` — who last
  touched that string, and when
- `git blame -L <line>,<line> <file>`
- the commit message and PR description
- anything already established earlier in the current conversation

This is best-effort: a decision made verbally or in a channel this session
cannot read will not show up. Say so plainly rather than implying a more
thorough check than actually happened.
