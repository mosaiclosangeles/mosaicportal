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

**A comm belongs to an event by its own reference, and only otherwise by
subject.** `comm_events.board_item_id` now exists — the comms app sets it when
a message is started from a planning card — and `commLink()` prefers it: set,
it is the whole answer, with no window and no word matching, and the comm
belongs to that item and no other. That is the upstream fix the paragraph below
was waiting for; it arrived on 10 Sep and this note was stale for a day, which
is its own lesson about keeping the record with the code.

The inference still runs, and still matters, because nothing was backfilled:
every message written before the column existed carries null, and guessing
which of those 242 rows belonged to which event would have attached the wrong
email to an event and read as fact.

**How that inference works, for the rows with no reference.** `commRelated()`
asks whether every distinctive word in the *comm's* name appears in the event's
(`subjectWords()` strips the channel and timing words — email, text, promo,
weekday names — and stems plurals), and `commWindow()` limits it to the item's
own Kick-Off→Debrief runway from the mirror, or ±21 days without one. It reads
one way on purpose: a comm is named more narrowly than the event it serves, so
"Bible Studies" reaches "Regional Bible Studies" but "ERM Text" reaches neither
Team Huddle nor Men's Camp. Same-day was the first rule and it hung two ERM
sends off a staff birthday; exact title was the second and matched almost
nothing. As `board_item_id` gets filled in, this matters less and less — but it
must keep working, because it is the only thing that speaks for every message
already written.

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

**Home's cards are numbers you can open.** A card with a list carries
`data-cardlist`; clicking it calls `openList()`, which draws the items behind
the number in the SAME dialog `openCard()` uses, so picking a row swaps the
contents for the full record rather than stacking a second thing over the
first — and the record carries a way back to the list it came from. What each
card counts is read at click time by `cardListOf()`, never stored, so the list
and the number printed above it cannot disagree; the test asserts they match.
That is also why `CLOSEOUT` is the items and not a tally. Click, not hover: a
hover panel is unreachable on a phone, which is where these get read.

**"Waiting on you" is yours; a campus's missing numbers are the campus's.**
It once counted every flagged item on the board for everyone, so the number read
the same for all of us. `waitingOnMe()` counts what the signed-in person OWNS and
what is still outstanding on it: a Sunday inside six weeks with no speaker, an
item flagged for review, and a Sunday whose attendance was never entered.
`closeOutList()` is the other half — a campus pastor sees their campus's pending
numbers even where somebody else owns the item, because Alisah does not own the
Bible studies and Andres does, so it is waiting on *him* while the numbers are
still missing at *her* campus. The same Sunday therefore reads one way to its
owner and the other to the campus, and never both to one person. Those rows carry
`noClose`: closing one out would mark the board Complete with the attendance it
is waiting for still missing.

**Who you are on the board comes from `board_owners.email`**, the mapping the
Monday digest is keyed on, so Home and the digest cannot disagree about whose
work this is. First-name matching is not merely loose, it is wrong — "Aaron" and
"Aaron Weits" are one person and "ACM" is another — and survives only as the
fallback for somebody not mapped yet. Anyone it gets wrong is fixed by mapping
them, not by guessing harder.

**An absence may only be claimed from a read that succeeded.** `METRICS_LOADED`
gates every attendance check; an empty `METRICS_DATES` from a failed fetch would
accuse every owner on the board of missing a week they filed on time. The same
reason the test stub now answers the `campuses` table: it returned `[]`, so
`campusIdOf()` answered null for everything and every campus-keyed assertion
passed by not running.

**Location and time are not checked, and that is deliberate.** The board's drawer
holds title, dates, time, speaker and description — there is no location field at
all, and the mirror's `location` column is filled for 3 items of 261. Time exists
but the board labels it optional and 87 of 87 upcoming items leave it blank.
Either check would flag the whole board and teach everyone to ignore the card.

**Worth a look is the Monday digest's own ranking, not a second opinion.**
`priorities_for()` in the board's database is what the Slack digest is built
from — it decides the sections, the order and the reason on every row — so the
portal calls the same function rather than working out its own version. Home
and the Monday post disagreeing about what needs attention is exactly how the
competing digest template happened on 13 Aug. The prose stays in the Slack
digest; what crosses over is the ranking, the section and the board's own
`why`. It is keyed on a Slack id, so the signed-in person is resolved through
`board_owners.email`; anybody not mapped there falls back to the flagged list,
which is what everyone had before.

**A merged card's board id lives on the board's part, not on the lead.** A card
leads with whichever part ranks first — for Men's Camp that is the shared
calendar's copy — so reading `pmId()` off the lead sent Planning an empty id
and opened it on its front page. `boardPart()` finds the `pm:` part; use it
anywhere the board's own id is needed.

**A home campus is a preference; `campus_id` is a permission.** Metrics scopes
what a person may SEE by `profiles.campus_id`, which is an admin's to set, so
the campus somebody picks for themselves had to be its own column
(`home_campus_id`) — otherwise setting your own default would re-scope your own
access. It only ever fills a form in. RLS could not restrict which columns a
self-update touches, so `profiles_self_update` is paired with a trigger that
puts role, campus, access and archived-state back for anyone but an admin; the
trigger skips writes with no `auth.uid()`, so the service role and the edge
functions still work.

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

**The portal answers for the apps a frame cannot read.** A planning card shows
what is booked and what was counted for its event, in its Connected panel. The
board cannot read either: both live in the Mosaic Metrics project behind RLS
keyed to `auth.uid()`, and the board runs on a publishable key with no session.
So it asks — `mosaic-connected-request` — and `connectedFor()` answers with the
signed-in person's own session. That is the point rather than a workaround: the
card shows exactly what THIS person may see, decided by the same policies
Facilities and Metrics already enforce. Only the fields the panel draws go back;
a booking carries internal notes and a requester's phone number, and a planning
card is not where either belongs.

**Closing out writes through the database, not through a second copy of the
board's save.** The board saves by reading the row, replaying a small op and
PATCHing behind a `version=eq.N` guard. Reimplementing that protocol in the
portal would be two writers with two copies of a concurrency rule to keep in
step — so the "Close it out" button calls `board_set_status()`, a Postgres
function that does the same change in ONE statement: atomic by definition,
nothing to race against. It writes exactly what the board's `edit` op writes
(`edits[id].status`) and MERGES into that item's existing edits, so a title,
owner or date already saved against it survives. The button never says it
worked before the database returns — a tick over a failed write is how somebody
loses an afternoon and finds out on Monday — and only then is the local copy
marked, because the mirror this page reads is a nightly sync behind.

**Attendance is one campus, and only a Sunday gathering may claim it.** Two
separate ways a card claimed a number nobody had counted for it. `METRICS` used
to sum `in_person_total` across every campus on a date, so 6 Sep read 2,373 —
Los Angeles 1,051 plus Ecuador 811, Mexico 439 and London 72 — and once Home
started saying "This week's attendance in Mexico" that vagueness became a
confident wrong answer. `METRICS_BY_CAMPUS` keeps them apart;
`metricsForCampus()` maps the board's short names onto Metrics' campus ids and
answers with NOTHING for one it does not know, because a blank panel is honest
and a stranger's attendance is not. Separately, the card decided "this is a
Sunday" from the weekday alone — so Kids Training, Choir, Baptisms and Child
Dedications, which are nested under the gathering and inherit its date, each
got handed the whole day. The mirror carries `is_sunday` and `parent_id`, so
`isGathering` reads the board's own answer rather than re-deriving a worse one.
Hannita caught both on the real card, 11 Sep.

**`wantAttendance` is the board's word, and it is honoured, not re-decided.**
Attendance has no reference to match on, so it matches on date and campus — and
an item nested under a Sunday *inherits* that Sunday's date, so Choir, Baptisms
and Child Dedications all carry the gathering's day and campus. Matching those
would hand each of them the Sunday's attendance as its own: three cards claiming
one number, none of which counted them. The board knows about its own nesting,
so `canOwnAttendance()` there decides and this does not go looking when the
answer would be wrong. Hannita caught it on the real board, 10 Sep.

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
