# Staff Directory — design note (draft v2, 26 Nov 2026)

Status: **draft, nothing applied to the live database.** Files:

| File | What |
|---|---|
| `supabase/migrations/20261125_staff_directory.sql` | tables, write trigger, RLS, `staff_directory_v`, `staff_directory_list()`, `who_is()` |
| `supabase/migrations/20261126_golive_all_campus_access.sql` | **go-live, permission step** — the two people who see every campus |
| `supabase/seed/20261125_staff_directory_seed.sql` | fills the directory from staging + live tables; saves invites |
| `scripts/directory_corrections_sql.py` | local corrections JSON → staging SQL on stdout |
| `scripts/slack_users_sql.py` | Slack `users.list` → staging SQL on stdout |
| `supabase/tests/` | SQL behaviour checks with made-up people, for a throwaway local Postgres |

v1 (25 Nov) was never applied, so its migration and seed were revised in place.

## Why

Hannita, 25 Nov: *"everybody in Slack needs to have an account in the staff
portal … whether it's active or not … It just means they haven't logged in
yet."* And the agents should know who is asking — campus and ministry — from
their Slack id rather than guessing from a display name.

## Where the record lives

`staff_directory`, in the Mosaic Metrics project (the one that owns every
login). A table, not columns on `profiles`, because `profiles.id` is a foreign
key to `auth.users`: somebody never invited cannot have a profile, and the
directory has to hold them anyway. `profile_id` links the login once there is
one.

One row per person (Hannita, 26 Nov):

| Column | |
|---|---|
| `email` | the primary (Mosaic) email |
| `emails_secondary text[]` | any of these, or `email`, links the row to a portal profile and to `who_is()` |
| `slack_user_id`, `slack_ids_secondary text[]` | nullable — some staff are not on Slack; a second Slack account is a secondary id, not a second row |
| `full_name`, `nicknames text[]`, `title` | |
| `primary_campus_id` | where they work |
| `location_id` → `campus_locations` | inside that campus (Mexico: Polanco, Roma Condesa). `campus_locations` already models locations — Metrics and the portal's Campuses tab read it — so no new list was invented. Must belong to the primary campus; a campus change clears a location that no longer fits |
| `campus_ids_overseen uuid[]`, `oversees_all` | what else they look after |
| `ministries text[]` | tags from `staff_ministries` |
| `teams text[]` | from `reminder_routing`, informational |
| `role` | display role for people with no profile yet; once there is one, `profiles.role` wins |
| `needs_review` | why an admin should look (two portal profiles, Slack-only, a note from the corrections) |

**None of the campus fields is a permission.** `profiles.role`,
`campus_id` and `campus_ids` stay the permission fields, an admin's to set —
the same line the portal already draws between `home_campus_id` and
`campus_id`.

**Ministries are a lookup table**, `staff_ministries`, so an admin can add one
without a migration (Admin → Users → a person → "Add a ministry to the list").
The write trigger rejects a tag that is not in it. "Young Adults" is now
**Next Gen**; the seed maps the old name if it ever appears. Renaming a tag
later is `update staff_ministries` plus
`update staff_directory set ministries = array_replace(ministries, old, new)`.

**One person, one row** is enforced: no email or Slack id may appear on two
live rows (primary or secondary). Where a person has **two portal profiles**,
neither is deleted or archived — the row links one and `needs_review` names
the other for an admin.

## Loading the data — nothing personal in git

The corrections file (names, personal emails) stays local. At apply time:

```sh
psql "$DB" -f supabase/migrations/20261125_staff_directory.sql
python3 scripts/directory_corrections_sql.py corrections.json | psql "$DB"
SLACK_BOT_TOKEN=xoxb-… python3 scripts/slack_users_sql.py --corrections corrections.json | psql "$DB"
psql "$DB" -f supabase/seed/20261125_staff_directory_seed.sql
# go-live, separately and deliberately:
psql "$DB" -f supabase/migrations/20261126_golive_all_campus_access.sql
```

Both scripts print SQL to stdout and write nothing else; `--inline` prints a
form the Supabase SQL editor accepts (no psql variables). Their output carries
people's data — don't commit it. Each load replaces the previous load from the
same source.

`slack_users_sql.py` needs `users:read` and `users:read.email`. It skips bots,
Slackbot, deactivated accounts and guests — unless a guest's Slack id or email
is in the corrections.

**Precedence:** corrections > Slack > profiles / pending invites. Rows marked
`remove: true` are never seeded, and their emails keep every other source from
seeding them too. The seed is idempotent; on a re-run, rows a person or an
admin has since edited (`source` `self` / `admin`) only have blanks filled.

## Activation and invites

Nothing new: `pending_invites` is still "invite saved, no email sent", and
"Send invite" still calls `invite-user`. `staff_directory_v.activation` is
derived, never stored: `signed_in` → `invite_sent` (profile, never signed in)
→ `invite_saved` (a `pending_invites` row for any of their emails) →
`no_invite`.

**The seed's last step is now on** (Hannita, 26 Nov): everyone in the
directory without a portal account gets a **saved** invite, role `staff`.
Nothing is emailed; an admin presses Send invite.

## Who can see and change it

- **Admins** read and write everything (`is_admin()`).
- **Each person** reads their own raw row, and may change only
  `primary_campus_id` and `ministries` on it. RLS cannot restrict columns, so
  the write trigger puts every other column back for a non-admin — the
  `profiles_keep_privileged` pattern.
- **Colleagues** read each other through `staff_directory_list()`, which
  leaves out secondary emails, secondary Slack ids and the review note for
  anyone but an admin or the person themselves. Secondary emails are often
  personal addresses.

## The portal (option B, Hannita 26 Nov)

- **Admin → Users is the directory.** No separate tab. Every directory person
  is a row, plus any portal account or saved invite the directory does not
  know yet ("Not in directory"), so nothing that used to be listed drops off.
  Status pill (Active / Invite sent / Invite saved / No invite), campus +
  location + overseen, ministry chips, title and nicknames, emails, Slack.
  **Send invite** and **Remove** on saved invites (the old "Invite pending"
  section, folded in); **Save invite** on people with none. A status filter
  sits beside the role filter.
- **Clicking a person** opens every directory field, editable by an admin,
  with **Account & permissions** leading to the existing per-user page.
- **Profile → "You in the directory"** (everyone reaches Profile; the
  Settings page is admin-only): ministries as toggles; primary campus is the
  existing **Home campus** picker — one control, saving it writes both, and
  the `staff_directory_follow_home_campus` trigger covers saves made
  anywhere else. Everything else is read-only, and says an admin sets it.
- If the directory cannot be read (e.g. before the migration is applied),
  Users says so in a banner and lists accounts and saved invites as before.

## Go-live permission step

Two people must see every campus in the portal (Hannita, 26 Nov). That is a
permission, so it is a separate migration and not a directory field. Checked
read-only on 26 Nov: an admin sees every campus (RLS `is_admin()`; the
portal's `campusesFor()`), **unless** `campus_ids` is non-empty, which narrows
even an admin. Both people are already `admin` with `campus_ids` null, so the
step changes nothing today; it clears a narrowing list for an admin, or sets
every active campus for a non-admin (without raising them to admin). Who it
applies to is read from the corrections rows that carry `_access`, so no name
is written in the file.

## `who_is`

```sql
select * from who_is('U…');                       -- by Slack id (primary or secondary)
select * from who_is(null, 'someone@mosaic.org');   -- by any of their emails
-- name, email, emails_secondary, nicknames, title, campus, campus_slug, location,
-- oversees_all, campuses_overseen[], ministries[], teams, role, status, activation, matched_by
```

`SECURITY DEFINER`, `service_role` only. No row means "not in the directory".

## Not decided — and not changed here

**The campus default for the agents** ("the asker's own campus, LA fallback"
vs today's "Los Angeles unless a campus is named", Hannita 22 Sep). Open as of
26 Nov. No connector instructions or Tiff text are touched by this branch;
`who_is()` only makes the fields available.

## Open

1. A field for a **location overseen** (one person oversees one Mexico
   location): no column yet; the seed puts it in `needs_review`.
2. Saved invites that already exist for people the corrections remove are
   left as they are — Admin → Users lists them with a Remove button.
3. A shared account the corrections list as a person gets a row and a saved
   invite like anyone else; remove it there if that is not wanted.
