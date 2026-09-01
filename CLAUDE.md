# Mosaic Portal

One front door for the Mosaic staff tools: Home and Calendars are native, and
Metrics, Comms, Planning and Goals are embedded live from their own sites.

- **Live at** `portal.mosaic.org` (Cloudflare Pages, deploys on push)
- **The whole app is `index.html`** — one file, no build step
- **Sign-in** uses the Mosaic Metrics Supabase project, shared across
  `*.mosaic.org` by a cookie, so the embedded apps do not ask again

## The embedded apps are not copies

The portal loads each app live from its own address, so a change shipped to
Metrics, Comms, Planning or Goals appears here with no deploy. Two things are
the portal's own and do not follow automatically: **Home and Calendars**, which
read the planning and comms data directly, and the **Goals sub-menu**, which is
a hand-written list in `GOALS_NAV` — a page added inside Goals has to be added
there too.

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
