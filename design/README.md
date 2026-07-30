# Mosaic Portal — handoff package

Five files. July 2026. Target launch mid-August.

---

## What's here

| File | What it is | Who it's for |
|---|---|---|
| **mosaic-portal-prototype.html** | Clickable prototype of the whole portal — eight sections, real interactions, no dependencies | You, for testing. Your team, for reactions |
| **mosaic-event-card.html** | The event detail card on its own | Sharing a single screen without the app around it |
| **mosaic-portal-build-spec.md** | Every decision, plus what's explicitly out of scope | Whoever builds it |
| **mosaic-style-guide.html** | Visual style guide — every component rendered live, with the rule that governs it | You and whoever touches the other two apps |
| **mosaic-tokens.css** | The shared stylesheet | Drop into all three apps |

Open the HTML files in a browser. No build step, no install.

---

## Where to start

**Testing the design** → prototype. Things worth trying:

- Calendar → Month, then click **+N more** on a busy Sunday
- Click a **past** Sunday (Jul 26) vs a **future** one (Aug 23) — actuals vs benchmarks
- Toggle the **Comms** filter off and watch the week go quiet
- **Settings → Role → Volunteer lead** — sections disappear from the rail
- **Settings → Role → Leadership** — Giving appears. It's gated, not missing
- **Settings → Type colours** — pick a colour, then go back to Calendar
- Narrow the window below 760px — the rail becomes a bottom bar
- Aug 6 on the calendar — dashed outline means a person is blocking it

**Handing it to a developer** → build spec, then tokens.

**Making the PM board and comms dashboard match** → style guide, section "Retrofitting the two existing apps."

---

## The three rules everything else follows

**Hue means type. Fill means status.** Colour never encodes navigation, scope, or priority. Scope uses weight; priority uses position. This is what will make the three apps look related.

**The calendar holds things that happen. The rail holds things that are due.** Deadlines aren't a calendar layer — they live in Planning and in the Due soon card. Metrics aren't a layer either; they're an attribute of an event, behind a click.

**The portal reads and arranges. The four apps stay the systems of record.** Nothing is editable in v1. Every detail view ends in a link out. This is the single cut that makes two weeks realistic.

---

## Answer these before building

1. **Do comms.mosaic.org and pm.mosaic.org have auth walls?** Both returned readable content unauthenticated during review. They may gate real data client-side — worth confirming. Either way the portal needs its own sign-in, because aggregation concentrates exposure.
2. **Does the planning board carry due dates and owners at *subtask* level?** The "This week" list on Home depends entirely on it.
3. **Is campaign tagging consistent** across the planning board and comms dashboard? The event card groups related sends and tasks by campaign, not date. Without reliable tags it falls back to same-day matching and looks half-empty. Probably the largest dependency in the set.
4. **What's actually in the goal tracker** — numeric targets or qualitative objectives? Numeric gets progress bars; qualitative needs a different shape entirely.
5. **Where does the budget live today?** The only section with no identified system of record.
6. **Who should have giving access, and does aggregate-only satisfy your finance policy?** Worth asking whoever owns financial controls before any of it is built.

---

## Two honest caveats about these files

**Goals and Budgets use invented data.** The goal tracker renders client-side so I couldn't read it; no budget source was identified. Both carry visible "sample data" banners so nobody mistakes them for real figures in a meeting.

**The style guide's status mapping tables use the status names visible on each app's public pages.** If either app has statuses I couldn't see, those tables need rows added.

---

## Sequencing note

Charles Metcalf is **23 August** — about a week after launch. That makes it the acceptance test for the calendar, the countdown, the comms overlay, and the event card all at once. Get the calendar reading real planning-board data in week one rather than saving integration for the end.
