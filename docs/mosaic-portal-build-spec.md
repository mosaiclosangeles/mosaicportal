# Mosaic Portal — Build Spec v1

Owner: Loyda (UX/UI) · Drafted 30 July 2026 · Target launch: mid-August 2026

---

## 1. What we're building

A staff portal that unifies Mosaic's four existing tools behind one shell, one visual language, and one login. The portal **orients**; the existing apps continue to **do the work**.

**v1 is thin on purpose.** Two screens are native and new (Home, Calendar). The other four sections link out to the apps that already exist. Nothing is rebuilt, no data is migrated, and no app's database is touched.

Leaving the portal to reach an app is acceptable. Links open in a new tab so nobody loses their place while signing in.

### Launch scope

| Section | v1 | Later |
|---|---|---|
| Home | Native | — |
| Calendar | Native (reads existing data) | Editing in place |
| Communication | Links to comms.mosaic.org | Native view |
| Planning | Links to pm.mosaic.org | Native timeline |
| Numbers | Links to metrics.mosaic.org, marked BETA | Native, attached to events |
| Goals | Links to the goal tracker, marked BETA | Native, pending content model |

---

## 2. Navigation

Left rail, fixed, always visible. Gray panel, monochrome icons, labels shown.

Eight sections, grouped — a flat list of eight reads as a wall.

**(ungrouped)**
1. **Home** — everything that needs you today
2. **Calendar** — every gathering, send, and deadline

**Work**
3. **Communication** — email, text, and service scripts
4. **Planning** — timeline, milestones, and owners

**Measure**
5. **Numbers** `BETA` — attendance, kids, next steps
6. **Goals** `BETA` — targets and pace for the year
7. **Budgets** `BETA` — budget versus actual by category
8. **Giving** `BETA` · restricted — aggregate totals only

Grouping is where nav growth gets absorbed. Nine or ten items is the practical ceiling for a single rail; past that it needs collapsible groups or a second level.

Settings sits at the bottom, above the account row.

**Badges** count *things needing this person specifically* — not total volume. A badge with no clear definition gets ignored within a week, so if a count can't be defined that way, omit it.

`BETA` marks sections that still point at an external app rather than a native view. It's honest and it buys time.

---

## 3. Screens

### 3.1 Home

The dashboard. Answers "what needs me today."

- **Title block** — "Home", date, week number
- **Primary action** — New event (black button, top right)
- **Four stat cards** — This week / Waiting / Due soon / Attendance. Monochrome: black numeral, gray label. One row, four maximum. If a fifth is requested, the answer is a nav section, not a fifth card.
- **Two lists side by side** — This week (tasks, circular checkboxes) and Coming up (next events, date + title + detail)

**Stat card rule:** a card must hold a single number that changes weekly. "Attendance" qualifies. "Fall launch progress" does not.

### 3.2 Calendar

The week is the default view; Month is available; phone renders as a list.

- **Views** — Week / Month segmented control
- **Type filters** — chip row: All, Gatherings, Comms, Milestones, Sessions. Each chip carries its type hue.
- **Week grid** — seven columns, day header, events stacked in day cells. Hairline column separators only, no heavy walls.
- **Month grid** — same structure, truncated hard, with **"+N more"** as the overflow affordance. Month view collapses comms to a dot or count per day; titles appear in Week view only.
- **Multi-day bars** — campaigns and phases span cells as a single bar (e.g. "Metcalf promotion — 3 week countdown").
- **Click an event** → detail panel containing that event's metrics, its linked comms, and its subtasks. Metrics are an attribute of an event, not a layer on the calendar.
- **Empty metrics state** — most events have no attendance. Show "No attendance recorded" plus a submit link, never a blank panel.

### 3.3 Communication

v1: link out to comms.mosaic.org.

Its existing status pipeline is the source of truth for calendar comms chips: incomplete → in progress → proposed → waiting for approval → approved → scheduled → sent. The portal collapses these to four visual states (see §5).

### 3.4 Planning

v1: link out to pm.mosaic.org.

Native design, ready for v2: a timeline of every campaign, event, and rhythm across the program year, plus a list of upcoming tasks and steps beneath it. Default the timeline to Level 1 and let people drill into Level 2 and 3 — a full program year of all three levels is forty bars deep by October.

### 3.5 Numbers `BETA`

v1: link out to metrics.mosaic.org.

Existing structure: attendance by type (Sunday service, midweek, special events, community groups, next steps), campuses, kids + youth, trends, history.

For the Home stat card and event detail panels, the portal reads a **nightly cached summary** rather than authenticating a user against metrics. Card shows "synced 6:00am."

### 3.6 Goals `BETA`

v1: link out to the goal tracker.

Native design assumes each goal has a target, a period, and a current value pulled from Numbers — displayed as a progress bar with a **pace marker** showing where the goal should be by today. Pace is the whole value: 58% is neither good nor bad until you know how much of the year has elapsed.

**This assumption needs confirming** — see §9.

### 3.7 Budgets `BETA`

Budget versus actual by category, with a pace marker showing where spend should sit if it were even across the year. Categories over pace by more than eight points turn orange.

**Source unknown** — see §9. This is the one section with no identified system of record.

### 3.8 Giving `BETA` · restricted

**Aggregate only.** Year to date against annual expectation, weekly average, giving units, recurring percentage, and a monthly trend.

Rules, which are not negotiable:

- **Donor-level records never enter the portal.** No names, no individual gifts, no statements. Those stay in CCB, which has its own access controls and audit trail.
- **Permission, not preference.** Giving is gated by role. Someone without access sees no nav item, no count, no greyed-out placeholder — no evidence the section exists.
- **Never on Home, never on the calendar.** Giving does not get a stat card in the default layout and is not a calendar layer. Someone screen-sharing Home in a staff meeting should not be able to expose it by accident.
- **Aggregates can still be identifying** in a small enough slice. If campus, month, and category filters are ever combined, a single large gift can become visible by subtraction. Set a floor — suppress any figure derived from fewer than about ten gifts.

The reason this matters more than it might seem: the portal's whole purpose is putting things side by side. Everywhere else that's the feature. Here it's the risk.

---

## 4. Design system

### Typography

`Inter` (self-hosted or Google Fonts), fallback `-apple-system, BlinkMacSystemFont, sans-serif`.
Letter-spacing `-0.011em` on body, `-0.03em` on large titles.

| Role | Size | Weight |
|---|---|---|
| Page title | 30px | 600 |
| Section title | 16px | 600 |
| Stat value | 26px | 600 |
| Body / row | 14px | 400 |
| Label / meta | 12–13px | 400 |
| Badge | 10px | 500, `0.06em` tracking, uppercase |

Weights: 400, 500, 600 only.

### Neutrals

| Token | Hex | Use |
|---|---|---|
| Surface | `#ffffff` | Content area |
| Rail | `#f3f3f2` | Left navigation panel |
| Rail active | `#e6e6e4` | Selected nav row |
| Fill | `#f2f2f1` | Segmented controls, hover |
| Hairline | `#e6e6e5` | Panel borders |
| Separator | `#f0f0f0` | List rows, grid columns |
| Text primary | `#000000` | Titles, values, row text |
| Text secondary | `#8a8a8a` | Labels, metadata |
| Button primary | `#000000` | Primary action, white text |

Radii: `7px` controls, `8px` buttons, `10px` cards, `12px` outer frame.

### Icons

Monochrome outline. `#5c5c5c` inactive, `#000000` active. No colored icons anywhere — color is reserved for meaning.

---

## 5. Color system

**One rule: hue encodes type, fill encodes status.** Color never encodes navigation.

### Type hues

Three types on the calendar. Deadlines are deliberately **not** one of them — the calendar holds things that happen, Planning holds things that are due.

| Type | Source | Shared? | Hue | Tint | Solid |
|---|---|---|---|---|---|
| Events | Planning board — Sunday, midweek, Houses, special | Org-wide | `#4f7fd1` | `#e8f0fa` | `#3f6cba` |
| Comms | Comms dashboard — email, text, script, social | Org-wide | `#e8a33d` | `#fdf3e3` | `#b8791b` |
| Other | Outlook meetings, CCB birthdays | **Personal only** | `#9a9a92` | `#f0f0ed` | `#6e6e67` |

The three hues are deliberately far apart on the wheel — blue and amber are nearly opposite, and Other is a true neutral with no blue in it, so it reads as "no type colour" rather than a third hue. Earlier drafts used blue, purple, and slate, which all sat within about 70° of each other and were hard to tell apart at chip size.

Each type needs three values, not one: the **hue** for borders and dots, a pale **tint** for scheduled states, and a deeper **solid** for done states — the mid-tone hues fail contrast under white text at 10–11px.

Sunday, midweek, and Houses are sub-labels within Events rather than separate types. If Sunday needs to stand out, use a deeper shade of the same blue rather than a different hue — otherwise "hue means type" stops being true.

**The Other layer has a different sharing model to everything else on the screen.** Events and comms are the church's; Outlook meetings and birthdays are one person's. It should never be visible to anyone but its owner, and it should be off by default so nobody is surprised to find their 1:1s rendered next to the Sunday service.

### Full palette (Asana)

| Slate | Red | Orange | Amber | Lime | Green | Blue | Indigo | Purple | Magenta |
|---|---|---|---|---|---|---|---|---|---|
| `#8d979e` | `#cf4b53` | `#de6a45` | `#e8a33d` | `#a9c957` | `#6ac5a7` | `#4f7fd1` | `#6f6ede` | `#9a63d4` | `#ca5391` |

Type colours are user-selectable from this palette in Settings, with a "set for everyone" option for team-wide defaults.

### Status fills

| Status | Treatment | Maps from |
|---|---|---|
| Done / sent | Solid hue, white text | sent, approved, complete |
| Scheduled | Tint background, hue text | scheduled |
| Waiting on someone | White background, dashed hue border | waiting for approval, blocked |
| Drafting | Palest tint, muted text | incomplete, in progress, proposed |

This is why a day reads as "needs a person" before any text is parsed. It also means adding a fifth type later needs one new hue, not a new system.

---

## 6. Data and integration

Four existing apps, unchanged:

| App | URL | Portal reads |
|---|---|---|
| Comms dashboard | comms.mosaic.org | Typed items, dates, status → calendar chips |
| Planning board | pm.mosaic.org | Events, multi-day phases, milestones, owners, subtasks |
| Metrics | metrics.mosaic.org | Nightly attendance summary → stat card, event detail |
| Goal tracker | replit.app (to move) | Targets and current values |
| Outlook | Microsoft Graph | The signed-in person's own meetings → Other layer |
| CCB | existing connector | Birthdays → Other layer |

The Outlook and CCB reads are per-person and read-only. They're the only place the portal touches an individual's data rather than the church's, which is worth keeping in mind when scoping the OAuth work — it's a different consent conversation than the rest.

**No SSO, no embedding, no shared cookie.** Each app keeps its own login exactly as today. This removes the chromeless-mode work, the `.mosaic.org` cookie work, and the domain migration from launch scope.

**The portal itself gets one login:** Google sign-in restricted to the mosaic.org workspace domain. Roughly half a day, no changes to the four apps. This matters because aggregation concentrates exposure — four scattered URLs is not the same risk as one page that indexes speaker plans, campaign timing, attendance, and who owes what.

---

## 7. Roles

One preset system, three jobs. Role sets defaults; individuals can override; nobody configures anything to get a sensible first screen.

| Role | Sees | Stat cards default to |
|---|---|---|
| Leadership | Everything including Giving | Attendance, Due soon |
| Comms | Everything except Giving | This week, Waiting |
| Ops / event management | Calendar, Planning, Budgets | Due soon, This week |
| Volunteer lead | Home, Calendar | This week |

Giving is the only section restricted by default, and it's restricted by **permission** rather than preference — invisible rather than disabled. Budgets is visible more widely on the assumption that ministry leads need to see their own spend; if that's wrong it's a one-line change.

If Numbers is genuinely restricted rather than merely noisy, the section needs a `visibleToRoles` field from day one — retrofitting permissions after launch is the expensive kind of rework.

---

## 8. Explicitly out of scope for v1

- Editing anything in the portal — it reads and arranges only
- Embedded app views, shared session, chromeless mode
- Moving the goal tracker off replit.app
- Native Communication, Planning, Numbers, Goals views
- Drag-and-drop dashboard building, or a layout-arrangement setting
- Campus split (NYC and LA as separate rows) — campus is a filter, not a split
- Dark mode
- Team / directory section

---

## 9. Open questions to verify before building

1. **Do comms.mosaic.org and pm.mosaic.org have auth walls?** Both returned readable content unauthenticated during review — including status pipelines, scopes, and owners. They may gate real data client-side, but this needs confirming, and it's the reason the portal needs its own sign-in regardless.
2. **Does the planning board carry due dates and owners at the *subtask* level, or only on parent items?** The "This week" list is the most valuable thing on Home and depends entirely on this.
3. **What's actually in the goal tracker — numeric targets, qualitative objectives, or both?** Numeric goals get progress bars and pace markers. Qualitative goals ("launch a third campus") need status cards closer to Planning. The section changes completely depending on the answer.
4. **What defines the Communication and Planning badge counts?**
5. **Where does the budget actually live today?** Spreadsheet, QuickBooks, something else? Budgets is the only section with no identified system of record, so it can't be built past sample data until this is answered.
6. **Who should have giving access, and does aggregate-only satisfy your finance policy?** Worth confirming with whoever owns financial controls before a line of it is built, not after.
7. **Is campaign tagging consistent** on the planning board and comms dashboard? The event card groups related sends and subtasks by campaign, not by date. Without reliable tags it silently falls back to same-day matching and looks half-empty — probably a larger dependency than the subtask due dates above.
8. **Is the Other layer in scope for launch?** It needs per-person Microsoft OAuth, which is the only individual-consent work in the whole build. The calendar is complete and useful without it — Events and Comms alone — so it's a clean candidate to cut to week three if the first two weeks get tight.

---

## 10. Suggested build order

**Week 1** — Portal shell, Google sign-in, rail navigation, design tokens. Calendar week view reading planning board events. Comms overlay with the four status treatments.

**Week 2** — Month view with "+N more" and multi-day bars. Event detail panel. Home with stat cards and the two lists. Nightly metrics sync. Phone list view.

**Post-launch** — Native Communication (closest data shape, highest daily use, replace first), then Planning, then Numbers, then Goals.

Note: the Charles Metcalf campaign lands 23 August, roughly a week after launch. It's the first real test of the calendar, the countdown bar, and the comms overlay — worth treating as the acceptance case rather than a coincidence.
