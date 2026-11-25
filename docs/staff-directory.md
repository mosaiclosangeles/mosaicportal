# Staff Directory — design note (draft, 25 Nov 2026)

Status: **draft, nothing applied.** Files:

- `supabase/migrations/20261125_staff_directory.sql` — table, triggers, RLS,
  `staff_directory_v`, `staff_directory_list()`, `who_is()`
- `supabase/seed/20261125_staff_directory_seed.sql` — fills it from the live
  tables; idempotent

## Why

Hannita, 25 Nov 2026: *"everybody in Slack needs to have an account in the
staff portal … whether it's active or not … It just means they haven't logged
in yet."* And: *"If Soti asks a question, we should know her campus is LA and
her ministry is kids, so she's probably asking about LA kids."*

Today every agent knows who is asking only by name, and scopes by "Los Angeles
unless a campus is named" (Hannita, 22 Sep). That default is right for most
people and wrong for McLaren in London, Chad in Chicago or Alfonso in Mexico.

## Where the record lives

A new table, `staff_directory`, in the Mosaic Metrics project — the same
project that owns every login, so the portal, Metrics, Facilities and Houses
all read the same people.

**Why a table, not columns on `profiles`.** `profiles.id` is a foreign key to
`auth.users`. Somebody who has never been invited cannot have a profiles row,
and the whole point is that they have a directory row anyway. So the directory
holds the person; `profile_id` links it to their login once they have one.

What it does **not** replace:

| Existing | Stays | Directory's relation to it |
|---|---|---|
| `pending_invites` | the one "account saved, no email sent" list | read only, for status |
| `profiles.role`, `campus_id`, `campus_ids` | permissions, an admin's | the view shows `profiles.role` once there is one |
| `profiles.home_campus_id` | the person's own pick in Settings | a change there is copied into the directory |
| `reminder_routing` (Paola's Metrics bot) | who owns which numbers | read once by the seed; never written |
| `slack_people` (Facilities bot) | cache of Slack `users.info` | read by the seed and `who_is` fallback |

One row per person: `slack_user_id` (unique), `email` (unique, lower-cased),
`full_name`, `primary_campus_id`, `ministry` (one value), `teams` (every area
they own, from `reminder_routing.group_label`), `role` (display role for people
without a profile), `profile_id` (null until activated), `source`,
`needs_review`, `archived_at`.

`primary_campus_id` is **where somebody works**, for scoping an answer. It is
not a permission and grants nothing — the same line the portal already draws
between `home_campus_id` and `campus_id`.

## Activation

Nothing new. The existing flow already goes: Admin saves a `pending_invites`
row → "Send invite" calls `invite-user`, which creates the auth user →
`handle_new_user()` creates the profile → the person signs in.

- An `after insert` trigger on `profiles` links the directory row by email (or
  through `slack_people.profile_id`, the hand-set link for a Slack account
  whose email is not the Mosaic login — Chris Duran, 9 Oct).
- A `before insert/update` trigger on the directory does the same in reverse,
  for a row added after the profile exists.
- **Status is derived, never stored**: `staff_directory_v.status` is
  `active` once `auth.users.last_sign_in_at` is set, otherwise
  `not activated`, with `activation` saying where in between:
  `invite_saved` (pending_invites row) → `invite_sent` (profile, never signed
  in) → `signed_in`; or `no_invite` (nobody has added them yet).

The seed has a final, **commented-out** step that would create a
`pending_invites` row for every directory person without one — Hannita's
"everybody in Slack needs an account". It is left off because it picks a role
(`staff`) for people nobody has assigned one to. Hannita's call.

## Who can see and change it

- Read: anyone with a live portal profile (not Houses-only accounts).
  Through `staff_directory_list()`, because the view reads `auth.users`.
- Write: admins (`is_admin()`, the check every portal table uses).
- Self: a person may update **their own** `primary_campus_id` and `ministry`.
  RLS cannot restrict columns, so `staff_directory_keep_privileged` puts every
  other column back for a non-admin — the same pattern as
  `profiles_keep_privileged`.

## The `who_is` lookup

```sql
select * from who_is('U4H2P85MG');
-- name, email, campus, campus_slug, ministry, teams, role, status, activation, matched_by
```

`SECURITY DEFINER`, executable by `service_role` only (what the connectors and
the Chief of Staff app use). Matches the Slack id; failing that, the email
`slack_people` has for that id (a second Slack account). **No row means "not in
the directory"** — the caller falls back to Los Angeles and says it did not
know who was asking, rather than guessing from a display name.

## The default this changes

Today, in the Metrics, CCB, Typeform, Calendar and Houses connectors and Tiff's
instructions: **"Los Angeles unless somebody names another campus"** (Hannita,
22 Sep). Metrics already moved part-way on 24 Nov ("OUR is the asker's own
campus").

Proposed: **the asker's own campus and ministry, from `who_is`; Los Angeles
only when the directory does not know them.** A campus named in the question
still wins, and so does any workflow that declares its own scope (the RSVP
tracker is all-campus/LA+NYC by Paola's design and is untouched). Carlos
oversees every campus, so his "our" stays all campuses — the directory can
carry that as `ministry = 'Campus leadership'`/role admin, but the rule itself
lives in the instructions, not the data.

This is a change to a rule Hannita set, in instruction text that lives in
`mosaic-mcp-connectors` (each connector's `SERVER_INSTRUCTIONS`) and in Tiff's
org-wide box (`mosaicprojectmanagement/docs/claude-tag-instructions.txt`, near
its size cap). It is **not** made by this migration — only proposed — and
needs her yes before any of those are edited.

## Portal Settings (spec)

A **"You in the directory"** card on Settings, under the existing Home campus
picker:

- Name, email, Slack (linked / not linked), role (read-only, "set by an admin").
- **Campus** — the existing Home campus picker. It already writes
  `profiles.home_campus_id`; the `staff_directory_follow_home_campus` trigger
  copies it across, so there is still one control, not two.
- **Ministry** — a select over the agreed list (below), writing
  `staff_directory.ministry` via the self-update policy.
- **Teams** — read-only chips from `teams`, captioned "from the Metrics
  reminders — ask Paola to change".
- One line explaining why: "Tiff and the other assistants use this to know
  what you're probably asking about."

**Admin → Users**: a Directory tab listing `staff_directory_list()` with the
status pill (Active / Invite sent / Invite saved / No invite), the
`needs_review` note, and a "Create invite" button that writes a
`pending_invites` row — the existing mechanism, not a new one.

Both are specs; no UI is in this branch.

## Open questions

1. **Ministry vocabulary.** The seed proposes one from a word map over
   `reminder_routing` labels: Kids, Worship, Houses & Groups, Young Adults,
   Next Steps, Outreach, Women, Online, Gatherings, Events, Campus leadership
   (+ Creative / Operations from Slack titles). It describes what somebody
   *reports numbers for*, which is not always their ministry — Carlos comes
   out as "Women" because his only routing row is Girls events. The list is a
   design/wording decision (Loyda/Hannita) before it becomes a select.
2. **`slack_people` is not "everybody in Slack".** It holds 22 accounts, seeded
   from #buildings. A full Slack `users.list` sync is needed before the
   directory can claim to cover the workspace.
3. **Pending-invite creation** (above): which role for people nobody has
   assigned one.
4. Duplicate people: two Adan Castillo Slack accounts, two Alan de la Peña
   profiles, Austin's second profile (ASJ), and test/shared accounts
   (Hannita Castro (TEST), Facilities Beta, Mosaic Admin — not seeded).
