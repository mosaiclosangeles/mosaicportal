-- Mosaic Staff Directory — one record per staff person.
--
-- DRAFT v2 (26 Nov 2026). Not applied. Review docs/staff-directory.md first.
-- v1 (25 Nov) was never applied anywhere, so this file was revised in place
-- rather than stacked with ALTERs against a table that does not exist yet.
--
-- Hannita, 25 Nov 2026: "everybody in Slack needs to have an account in the
-- staff portal … whether it's active or not." 26 Nov: the schema below —
-- several emails, nicknames, campuses overseen, a location inside a campus,
-- several ministries, a title — and one row per person.
--
-- Why a table and not columns on profiles: profiles.id is a foreign key to
-- auth.users (profiles_id_fkey), so a person who has never been invited cannot
-- have a profiles row at all. The directory holds people BEFORE they have a
-- login and links to profiles once they do (profile_id, null until then).
--
-- What it does NOT replace:
--   * pending_invites stays the one "invite saved, no email sent" mechanism.
--   * profiles.role / campus_id / campus_ids stay the PERMISSION fields, an
--     admin's to set. primary_campus_id, campus_ids_overseen and oversees_all
--     here are "where this person works / what they look after", for scoping
--     an answer. They grant nothing. (Portal CLAUDE.md: "A home campus is a
--     preference; campus_id is a permission.")
--   * reminder_routing (Paola's Metrics bot) and slack_people (Facilities bot)
--     are read by the seed, never written.
--
-- No DROP statements: they hang the Supabase MCP (facilities CLAUDE.md).
-- No person's data is in this file. The seed reads it at apply time from
-- staff_directory_staging, which scripts/ fill from local files and Slack.

-- ------------------------------------------------------- ministry vocabulary
-- A lookup table, not a CHECK, so an admin can add a ministry without a
-- migration (Hannita, 26 Nov). Renaming a ministry is an update here plus the
-- array_replace in staff_directory — see docs/staff-directory.md.
create table if not exists public.staff_ministries (
  name        text primary key,
  sort_order  int  not null default 100,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
comment on table public.staff_ministries is
  'The ministry tags a directory person can carry. Admins extend it; staff_directory.ministries must use these names.';

insert into public.staff_ministries (name, sort_order) values
  ('Kids',10),('Worship',20),('Production',30),('Creative',40),('Online',50),
  ('Mosaic MSC',60),('Future',70),('Men',80),('Next Gen',90),('Families',100),
  ('Givers',110),('Finance',120),('Admin',130),('HR',140),('ERM Office',150),
  ('Arena',160),('Global',170),('Girls',180),('Merch',190),('Systems',200),
  ('Database',210),('IT',220),('Pastoral Care',230),('Home Team',240),
  ('Houses & Groups',250),('Next Steps',260),('Campus leadership',270),
  ('Events',280),('Gatherings',290),('Outreach',300),('Women',310)
on conflict (name) do nothing;

-- ---------------------------------------------------------------- the table
create table if not exists public.staff_directory (
  id                   uuid primary key default gen_random_uuid(),
  slack_user_id        text,
  slack_ids_secondary  text[] not null default '{}',
  email                text,
  emails_secondary     text[] not null default '{}',
  full_name            text not null,
  nicknames            text[] not null default '{}',
  title                text,
  primary_campus_id    uuid references public.campuses(id) on delete set null,
  location_id          uuid references public.campus_locations(id) on delete set null,
  campus_ids_overseen  uuid[] not null default '{}',
  oversees_all         boolean not null default false,
  ministries           text[] not null default '{}',
  teams                text[] not null default '{}',
  role                 text,
  profile_id           uuid references public.profiles(id) on delete set null,
  source               text not null default 'manual',
  needs_review         text,
  archived_at          timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint staff_directory_has_key check (slack_user_id is not null or email is not null),
  constraint staff_directory_source_check check (source in
    ('corrections','slack','reminder_routing','slack_people','profiles','pending_invites','manual','admin','self')),
  constraint staff_directory_role_check check (role is null or role in
    ('admin','leader','staff','volunteer','campus_pastor','houses')),
  constraint staff_directory_email_lower check (email is null or email = lower(btrim(email)))
);

comment on table public.staff_directory is
  'One row per Mosaic staff person, with or without a portal login. See docs/staff-directory.md in mosaicportal.';
comment on column public.staff_directory.email is
  'The primary (Mosaic) email. Any of email / emails_secondary links the row to a portal profile and to who_is().';
comment on column public.staff_directory.slack_ids_secondary is
  'A person''s other Slack accounts (one person = one row). who_is() matches these too.';
comment on column public.staff_directory.primary_campus_id is
  'Where this person works — scopes an agent''s answer. NOT a permission; profiles.campus_id is.';
comment on column public.staff_directory.location_id is
  'Which campus_locations row inside the primary campus (Mexico: Polanco / Roma Condesa). Must belong to primary_campus_id.';
comment on column public.staff_directory.campus_ids_overseen is
  'Other campuses this person looks after. Informational, NOT a permission.';
comment on column public.staff_directory.oversees_all is
  'Looks after every campus. Informational — the portal permission is profiles.role/campus_ids (see the go-live step).';
comment on column public.staff_directory.ministries is
  'Ministry tags, each a staff_ministries.name.';
comment on column public.staff_directory.teams is
  'Every area they own, copied from reminder_routing.group_label at seed time. Informational.';
comment on column public.staff_directory.needs_review is
  'Why an admin should look at this row (two portal profiles, Slack-only, …). Cleared by hand.';

create unique index if not exists staff_directory_slack_uq   on public.staff_directory (slack_user_id) where slack_user_id is not null;
create unique index if not exists staff_directory_email_uq   on public.staff_directory (email)         where email is not null;
create unique index if not exists staff_directory_profile_uq on public.staff_directory (profile_id)    where profile_id is not null;
create index if not exists staff_directory_emails2_gin on public.staff_directory using gin (emails_secondary);
create index if not exists staff_directory_slack2_gin  on public.staff_directory using gin (slack_ids_secondary);

-- Every email and Slack id a row answers to. One person = one row, so none of
-- these may belong to two rows (checked in the write trigger, because unique
-- indexes cannot span an array and a scalar).
create or replace function public.staff_directory_all_emails(d public.staff_directory)
returns text[] language sql immutable as $$
  select array(select distinct x from unnest(array[d.email] || d.emails_secondary) x where x is not null)
$$;
create or replace function public.staff_directory_all_slack(d public.staff_directory)
returns text[] language sql immutable as $$
  select array(select distinct x from unnest(array[d.slack_user_id] || d.slack_ids_secondary) x where x is not null)
$$;

-- ------------------------------------------------------- one write trigger
-- In this order, in one function so the order cannot drift:
--   1. a non-admin may change ONLY primary_campus_id and ministries on their
--      own row; everything else is put back (RLS cannot restrict columns —
--      the same pattern as profiles_keep_privileged). No auth.uid() means the
--      service role or a migration: trusted.
--   2. normalise: lower-cased, de-duplicated emails; trimmed arrays.
--   3. validate: ministries in the vocabulary; location inside the primary
--      campus (a campus change clears a location that no longer fits); no
--      email or Slack id shared with another row.
--   4. link a profile by any of the row's emails, if not linked yet.
create or replace function public.staff_directory_before_write()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare bad text; clash text;
begin
  if tg_op = 'UPDATE' and auth.uid() is not null and not public.is_admin() then
    new.id                  := old.id;
    new.slack_user_id       := old.slack_user_id;
    new.slack_ids_secondary := old.slack_ids_secondary;
    new.email               := old.email;
    new.emails_secondary    := old.emails_secondary;
    new.full_name           := old.full_name;
    new.nicknames           := old.nicknames;
    new.title               := old.title;
    new.location_id         := old.location_id;
    new.campus_ids_overseen := old.campus_ids_overseen;
    new.oversees_all        := old.oversees_all;
    new.teams               := old.teams;
    new.role                := old.role;
    new.profile_id          := old.profile_id;
    new.needs_review        := old.needs_review;
    new.archived_at         := old.archived_at;
    new.created_at          := old.created_at;
    new.source              := 'self';
  end if;

  new.updated_at := now();
  new.email := nullif(lower(btrim(new.email)), '');
  new.emails_secondary := array(
    select distinct lower(btrim(x)) from unnest(coalesce(new.emails_secondary,'{}')) x
     where nullif(btrim(x),'') is not null and lower(btrim(x)) is distinct from new.email);
  new.slack_ids_secondary := array(
    select distinct btrim(x) from unnest(coalesce(new.slack_ids_secondary,'{}')) x
     where nullif(btrim(x),'') is not null and btrim(x) is distinct from new.slack_user_id);
  new.nicknames := array(select distinct btrim(x) from unnest(coalesce(new.nicknames,'{}')) x where nullif(btrim(x),'') is not null);
  new.ministries := array(select distinct btrim(x) from unnest(coalesce(new.ministries,'{}')) x where nullif(btrim(x),'') is not null);
  new.campus_ids_overseen := array(select distinct x from unnest(coalesce(new.campus_ids_overseen,'{}')) x
                                    where x is not null and x is distinct from new.primary_campus_id);

  select string_agg(m, ', ') into bad from unnest(new.ministries) m
   where not exists (select 1 from staff_ministries s where s.name = m);
  if bad is not null then
    raise exception 'Not a ministry in staff_ministries: %', bad using errcode = '23514';
  end if;

  if new.location_id is not null and not exists (
       select 1 from campus_locations l where l.id = new.location_id and l.campus_id = new.primary_campus_id) then
    if tg_op = 'UPDATE' and new.primary_campus_id is distinct from old.primary_campus_id then
      new.location_id := null;      -- moved campus: the old location no longer applies
    else
      raise exception 'Location is not in this person''s primary campus' using errcode = '23514';
    end if;
  end if;

  select coalesce(d.full_name, d.email) into clash from staff_directory d
   where d.id <> new.id and d.archived_at is null
     and (staff_directory_all_emails(d) && (array[new.email] || new.emails_secondary)
          or staff_directory_all_slack(d) && (array[new.slack_user_id] || new.slack_ids_secondary))
   limit 1;
  if clash is not null then
    raise exception 'An email or Slack id here already belongs to another directory row (%) — one person, one row', clash
      using errcode = '23505';
  end if;

  if new.profile_id is null then
    select p.id into new.profile_id
      from auth.users u join profiles p on p.id = u.id
     where lower(u.email) = any(array[new.email] || new.emails_secondary) and p.archived_at is null
       and not exists (select 1 from staff_directory d where d.profile_id = p.id and d.id <> new.id)
     order by (lower(u.email) = new.email) desc, u.last_sign_in_at desc nulls last
     limit 1;
  end if;
  return new;
end $$;

create or replace trigger staff_directory_before_write
  before insert or update on public.staff_directory
  for each row execute function public.staff_directory_before_write();

-- ------------------------------------------------------- activation
-- handle_new_user() inserts the profile when invite-user creates the auth
-- user (an invite SENT), so the link lands at invite time and status flips to
-- 'active' at first sign-in, with nothing else to update. Matches any of the
-- row's emails, and slack_people.profile_id (the hand-set link for a Slack
-- account whose email is not the Mosaic login, 9 Oct).
create or replace function public.staff_directory_link_profile()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare em text;
begin
  select lower(u.email) into em from auth.users u where u.id = new.id;
  update staff_directory d
     set profile_id = new.id
   where d.profile_id is null
     and not exists (select 1 from staff_directory x where x.profile_id = new.id)
     and (em = any(staff_directory_all_emails(d))
          or staff_directory_all_slack(d) && array(select sp.slack_user_id from slack_people sp where sp.profile_id = new.id));
  return new;
exception when others then
  return new;  -- never block a sign-up over this
end $$;

create or replace trigger staff_directory_link_profile
  after insert on public.profiles
  for each row execute function public.staff_directory_link_profile();

-- The portal's Home campus picker (Profile) is the person's own choice of
-- where they work. Keep the directory in step with it, one way.
create or replace function public.staff_directory_follow_home_campus()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.home_campus_id is distinct from old.home_campus_id and new.home_campus_id is not null then
    update staff_directory set primary_campus_id = new.home_campus_id where profile_id = new.id;
  end if;
  return new;
exception when others then
  return new;
end $$;

create or replace trigger staff_directory_follow_home_campus
  after update of home_campus_id on public.profiles
  for each row execute function public.staff_directory_follow_home_campus();

-- ------------------------------------------------------- RLS
-- Who is staff: a live portal profile that is not a Houses-only account.
create or replace function public.staff_directory_can_read()
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (select 1 from profiles
                  where id = auth.uid() and archived_at is null
                    and coalesce(role,'') <> 'houses');
$$;

alter table public.staff_ministries enable row level security;
revoke all on public.staff_ministries from anon;
grant select, insert, update on public.staff_ministries to authenticated;

alter table public.staff_directory enable row level security;
revoke all on public.staff_directory from anon;
grant select, insert, update, delete on public.staff_directory to authenticated;

-- The raw table is read by admins and by each person for their OWN row.
-- Everyone else reads colleagues through staff_directory_list(), which leaves
-- out personal (secondary) emails and the review notes.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='staff_ministries' and policyname='staff_ministries_read') then
    create policy staff_ministries_read on public.staff_ministries
      for select to authenticated using (public.staff_directory_can_read());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='staff_ministries' and policyname='staff_ministries_admin_write') then
    create policy staff_ministries_admin_write on public.staff_ministries
      for all to authenticated using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='staff_directory' and policyname='staff_directory_read') then
    create policy staff_directory_read on public.staff_directory
      for select to authenticated using (public.is_admin() or profile_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='staff_directory' and policyname='staff_directory_admin_write') then
    create policy staff_directory_admin_write on public.staff_directory
      for all to authenticated using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='staff_directory' and policyname='staff_directory_self_update') then
    create policy staff_directory_self_update on public.staff_directory
      for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
  end if;
end $$;

-- ------------------------------------------------------- staging
-- Where scripts/ put what they read at apply time — the corrections file
-- (local, never committed) and Slack users.list. The seed merges it. Nothing
-- reads this but the seed; no policy, so only the service role / a migration
-- can touch it.
create table if not exists public.staff_directory_staging (
  id         bigserial primary key,
  source     text not null check (source in ('corrections','slack')),
  payload    jsonb not null,
  loaded_at  timestamptz not null default now()
);
comment on table public.staff_directory_staging is
  'Rows loaded at apply time by scripts/directory_corrections_sql.py and scripts/slack_users_sql.py. Read by the seed only.';
alter table public.staff_directory_staging enable row level security;
revoke all on public.staff_directory_staging from anon, authenticated;

-- ------------------------------------------------------- the view
-- status: 'active' = has signed in at least once; otherwise 'not activated'.
-- activation says where in between:
--   signed_in     profile + auth.users.last_sign_in_at
--   invite_sent   auth user/profile exists, never signed in
--   invite_saved  a pending_invites row for any of their emails (no email sent)
--   no_invite     nothing yet
create or replace view public.staff_directory_v
with (security_invoker = true) as
select d.id,
       d.slack_user_id,
       d.slack_ids_secondary,
       coalesce(d.email, lower(u.email))                              as email,
       d.emails_secondary,
       coalesce(d.full_name, nullif(btrim(p.display_name),''))        as name,
       d.nicknames,
       d.title,
       coalesce(d.primary_campus_id, p.home_campus_id, p.campus_id)   as campus_id,
       c.name                                                         as campus,
       c.slug                                                         as campus_slug,
       d.location_id,
       l.location                                                     as location,
       d.oversees_all,
       d.campus_ids_overseen,
       array(select c2.name from campuses c2 where c2.id = any(d.campus_ids_overseen) order by c2.name) as campuses_overseen,
       d.ministries,
       d.teams,
       coalesce(p.role, d.role, pi.role)                              as role,
       d.profile_id,
       pi.id                                                          as pending_invite_id,
       case when u.last_sign_in_at is not null then 'active' else 'not activated' end as status,
       case when u.last_sign_in_at is not null then 'signed_in'
            when p.id is not null              then 'invite_sent'
            when pi.id is not null             then 'invite_saved'
            else 'no_invite' end                                      as activation,
       u.last_sign_in_at,
       d.source,
       d.needs_review,
       d.updated_at
  from public.staff_directory d
  left join public.profiles p  on p.id = d.profile_id and p.archived_at is null
  left join auth.users u       on u.id = p.id
  left join lateral (select x.id, x.role from public.pending_invites x
                      where lower(x.email) = any(staff_directory_all_emails(d))
                      order by (lower(x.email) = d.email) desc limit 1) pi on true
  left join public.campuses c  on c.id = coalesce(d.primary_campus_id, p.home_campus_id, p.campus_id)
  left join public.campus_locations l on l.id = d.location_id
 where d.archived_at is null;

-- The portal reads the view through this function (auth.users is not readable
-- by authenticated). Signed-in staff only. A non-admin sees colleagues
-- without their secondary (often personal) emails, secondary Slack ids or the
-- review note; their own row comes back whole.
create or replace function public.staff_directory_list()
returns setof public.staff_directory_v
language sql stable security definer set search_path to 'public'
as $$
  select v.id, v.slack_user_id,
         case when public.is_admin() or v.profile_id = auth.uid() then v.slack_ids_secondary else '{}' end,
         v.email,
         case when public.is_admin() or v.profile_id = auth.uid() then v.emails_secondary else '{}' end,
         v.name, v.nicknames, v.title, v.campus_id, v.campus, v.campus_slug, v.location_id, v.location,
         v.oversees_all, v.campus_ids_overseen, v.campuses_overseen, v.ministries, v.teams, v.role,
         v.profile_id, v.pending_invite_id, v.status, v.activation, v.last_sign_in_at, v.source,
         case when public.is_admin() then v.needs_review end,
         v.updated_at
    from public.staff_directory_v v
   where public.staff_directory_can_read()
   order by v.name
$$;

revoke all on public.staff_directory_v from anon, authenticated;
revoke all on function public.staff_directory_list() from public, anon;
grant execute on function public.staff_directory_list() to authenticated;

-- ------------------------------------------------------- who_is
-- The lookup every agent makes first: who is asking? By Slack user id (the
-- primary or any secondary), else by any email the row carries, else through
-- slack_people's email for that Slack id. No row back means "not in the
-- directory". What the caller then defaults to is NOT decided here — the
-- campus-default rule for the agents is still open (Hannita, 26 Nov).
create or replace function public.who_is(p_slack_user_id text default null, p_email text default null)
returns table (name text, email text, emails_secondary text[], nicknames text[], title text,
               campus text, campus_slug text, location text,
               oversees_all boolean, campuses_overseen text[],
               ministries text[], teams text[], role text, status text, activation text,
               matched_by text)
language sql stable security definer set search_path to 'public'
as $$
  select v.name, v.email, v.emails_secondary, v.nicknames, v.title,
         v.campus, v.campus_slug, v.location,
         v.oversees_all, v.campuses_overseen,
         v.ministries, v.teams, v.role, v.status, v.activation, m.how
    from (
      select d.id, 'slack_user_id'::text as how, 1 as rank
        from staff_directory d
       where nullif(btrim(p_slack_user_id),'') is not null and d.archived_at is null
         and btrim(p_slack_user_id) = any(staff_directory_all_slack(d))
      union all
      select d.id, 'email', 2
        from staff_directory d
       where nullif(btrim(p_email),'') is not null and d.archived_at is null
         and lower(btrim(p_email)) = any(staff_directory_all_emails(d))
      union all
      select d.id, 'slack_people.email', 3
        from slack_people sp join staff_directory d on lower(sp.email) = any(staff_directory_all_emails(d))
       where sp.slack_user_id = btrim(p_slack_user_id) and d.archived_at is null
    ) m
    join staff_directory_v v on v.id = m.id
   order by m.rank
   limit 1
$$;

revoke all on function public.who_is(text, text) from public, anon, authenticated;
grant execute on function public.who_is(text, text) to service_role;
