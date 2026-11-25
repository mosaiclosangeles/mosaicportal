-- Mosaic Staff Directory — one record per staff person, keyed by Slack user id.
--
-- DRAFT (25 Nov 2026). Not applied. Review docs/staff-directory.md first.
--
-- Hannita, 25 Nov 2026: "everybody in Slack needs to have an account in the
-- staff portal … whether it's active or not … It just means they haven't logged
-- in yet." And: "If Soti asks a question, we should know her campus is LA and
-- her ministry is kids."
--
-- Why a table and not columns on profiles: profiles.id is a foreign key to
-- auth.users (profiles_id_fkey), so a person who has never been invited cannot
-- have a profiles row at all. The directory has to hold people BEFORE they have
-- a login, so it is its own table and links to profiles once they do
-- (profile_id, null until then).
--
-- What it does NOT replace:
--   * pending_invites stays the one "invite saved, no email sent" mechanism.
--     The directory never sends or stores an invite; staff_directory_v only
--     READS pending_invites to say where somebody is in activation.
--   * profiles.campus_id / campus_ids / role stay the PERMISSION fields, an
--     admin's to set. primary_campus_id here is "where this person works", for
--     scoping an answer — the same distinction profiles.home_campus_id already
--     draws (portal CLAUDE.md: "A home campus is a preference; campus_id is a
--     permission"). It never grants access to anything.
--   * reminder_routing is Paola's Metrics bot's table. Read by the seed, never
--     written by anything here.
--   * slack_people is the Facilities bot's cache of users.info. Read, never
--     written.
--
-- No DROP statements: they hang the Supabase MCP (facilities CLAUDE.md).

-- ---------------------------------------------------------------- the table
create table if not exists public.staff_directory (
  id                uuid primary key default gen_random_uuid(),
  slack_user_id     text,
  email             text,
  full_name         text not null,
  primary_campus_id uuid references public.campuses(id) on delete set null,
  ministry          text,
  teams             text[] not null default '{}',
  role              text,
  profile_id        uuid references public.profiles(id) on delete set null,
  source            text not null default 'manual',
  needs_review      text,
  archived_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint staff_directory_has_key check (slack_user_id is not null or email is not null),
  constraint staff_directory_source_check check (source in
    ('reminder_routing','slack_people','profiles','pending_invites','manual','self')),
  constraint staff_directory_role_check check (role is null or role in
    ('admin','leader','staff','volunteer','campus_pastor','houses')),
  constraint staff_directory_email_lower check (email is null or email = lower(btrim(email)))
);

comment on table public.staff_directory is
  'One row per Mosaic staff person, with or without a portal login. Who is asking, from their Slack id. See docs/staff-directory.md in mosaicportal.';
comment on column public.staff_directory.primary_campus_id is
  'Where this person works — scopes an agent''s answer. NOT a permission; profiles.campus_id is.';
comment on column public.staff_directory.ministry is
  'Their main ministry/team (Kids, Worship, …). One value; everything else they own is in teams.';
comment on column public.staff_directory.teams is
  'Every area they own, copied from reminder_routing.group_label at seed time. Informational.';
comment on column public.staff_directory.role is
  'Display role for people with no profile yet. Once activated, profiles.role wins — see staff_directory_v.';
comment on column public.staff_directory.profile_id is
  'Null until the person has a portal account. Linked by email when the profile is created.';
comment on column public.staff_directory.needs_review is
  'Why a person should look at this row (two campuses, derived ministry, …). Cleared by hand.';

create unique index if not exists staff_directory_slack_uq   on public.staff_directory (slack_user_id) where slack_user_id is not null;
create unique index if not exists staff_directory_email_uq   on public.staff_directory (email)         where email is not null;
create unique index if not exists staff_directory_profile_uq on public.staff_directory (profile_id)    where profile_id is not null;

-- ------------------------------------------------------- keep it honest
-- updated_at, lower-cased email, and a profile link found by email on write.
create or replace function public.staff_directory_before_write()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  new.updated_at := now();
  new.email := nullif(lower(btrim(new.email)), '');
  if new.profile_id is null and new.email is not null then
    select p.id into new.profile_id
      from auth.users u join profiles p on p.id = u.id
     where lower(u.email) = new.email and p.archived_at is null
       and not exists (select 1 from staff_directory d where d.profile_id = p.id and d.id <> new.id)
     limit 1;
  end if;
  return new;
end $$;

create or replace trigger staff_directory_before_write
  before insert or update on public.staff_directory
  for each row execute function public.staff_directory_before_write();

-- A person may edit their own campus and ministry, nothing else. RLS cannot
-- restrict columns, so — like profiles_keep_privileged — a trigger puts the
-- rest back for anyone who is not an admin. No auth.uid() means the service
-- role or a migration: trusted.
create or replace function public.staff_directory_keep_privileged()
returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  new.id            := old.id;
  new.slack_user_id := old.slack_user_id;
  new.email         := old.email;
  new.full_name     := old.full_name;
  new.teams         := old.teams;
  new.role          := old.role;
  new.profile_id    := old.profile_id;
  new.needs_review  := old.needs_review;
  new.archived_at   := old.archived_at;
  new.created_at    := old.created_at;
  new.source        := 'self';
  return new;
end $$;

create or replace trigger staff_directory_keep_privileged
  before update on public.staff_directory
  for each row execute function public.staff_directory_keep_privileged();

-- ------------------------------------------------------- activation
-- First sign-in links by email. handle_new_user() inserts the profile when the
-- auth user is created (the invite-user function does that when an invite is
-- SENT), so the link lands at invite time and status flips to 'active' at the
-- first sign-in (auth.users.last_sign_in_at), with nothing else to update.
-- Also follows slack_people.profile_id, the hand-set link for a Slack account
-- whose email is not the Mosaic login (Chris Duran, 9 Oct).
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
     and (d.email = em
          or d.slack_user_id in (select sp.slack_user_id from slack_people sp where sp.profile_id = new.id));
  return new;
exception when others then
  return new;  -- never block a sign-up over this
end $$;

create or replace trigger staff_directory_link_profile
  after insert on public.profiles
  for each row execute function public.staff_directory_link_profile();

-- The portal's existing "home campus" picker (Settings) is the person's own
-- choice of where they work. Keep the directory in step with it, one way:
-- a home campus chosen in Settings becomes the directory's primary campus.
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
alter table public.staff_directory enable row level security;
revoke all on public.staff_directory from anon;
grant select, insert, update, delete on public.staff_directory to authenticated;

-- Anyone with a live portal profile can read the directory (it is a staff
-- directory; colleagues' names, campus and email are not private among staff).
-- Houses-only accounts are not staff and do not read it.
create or replace function public.staff_directory_can_read()
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (select 1 from profiles
                  where id = auth.uid() and archived_at is null
                    and coalesce(role,'') <> 'houses');
$$;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='staff_directory' and policyname='staff_directory_read') then
    create policy staff_directory_read on public.staff_directory
      for select to authenticated using (public.staff_directory_can_read());
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

-- ------------------------------------------------------- the view
-- status: 'active' = has signed in at least once; anything else 'not activated'.
-- activation says where in between:
--   signed_in     profile + auth.users.last_sign_in_at
--   invite_sent   auth user/profile exists, never signed in
--   invite_saved  a pending_invites row (saved in Admin, no email sent yet)
--   no_invite     nothing yet — an admin needs to add them in Admin → Users
-- Campus: the directory's own value, else the profile's home campus, else its
-- permission campus. Role: the profile's (an admin's decision) once there is one.
create or replace view public.staff_directory_v
with (security_invoker = true) as
select d.id,
       d.slack_user_id,
       coalesce(d.email, lower(u.email))                              as email,
       coalesce(nullif(btrim(p.display_name),''), d.full_name)        as name,
       coalesce(d.primary_campus_id, p.home_campus_id, p.campus_id)   as campus_id,
       c.name                                                         as campus,
       c.slug                                                         as campus_slug,
       d.ministry,
       d.teams,
       coalesce(p.role, d.role, pi.role)                              as role,
       d.profile_id,
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
  left join public.pending_invites pi on lower(pi.email) = d.email
  left join public.campuses c  on c.id = coalesce(d.primary_campus_id, p.home_campus_id, p.campus_id)
 where d.archived_at is null;

-- security_invoker means the view obeys the table's RLS — but auth.users is not
-- readable by authenticated, so the portal reads the view through this
-- function instead (signed-in staff only, same rule as the table).
create or replace function public.staff_directory_list()
returns setof public.staff_directory_v
language sql stable security definer set search_path to 'public'
as $$
  select * from public.staff_directory_v
   where public.staff_directory_can_read()
   order by name
$$;

revoke all on public.staff_directory_v from anon, authenticated;
revoke all on function public.staff_directory_list() from public, anon;
grant execute on function public.staff_directory_list() to authenticated;

-- ------------------------------------------------------- who_is
-- The lookup every agent makes first: who is asking? By Slack user id; if that
-- id is not in the directory, through slack_people's email for it (a second
-- Slack account, or one added before the directory knew it).
-- No row back means "not in the directory": the caller falls back to Los
-- Angeles AND says it did not know who was asking.
create or replace function public.who_is(p_slack_user_id text)
returns table (name text, email text, campus text, campus_slug text, ministry text,
               teams text[], role text, status text, activation text, matched_by text)
language sql stable security definer set search_path to 'public'
as $$
  select v.name, v.email, v.campus, v.campus_slug, v.ministry, v.teams, v.role,
         v.status, v.activation, m.how
    from (
      select d.id, 'slack_user_id'::text as how, 1 as rank
        from staff_directory d
       where d.slack_user_id = btrim(p_slack_user_id) and d.archived_at is null
      union all
      select d.id, 'slack_people.email', 2
        from slack_people sp join staff_directory d on d.email = lower(sp.email)
       where sp.slack_user_id = btrim(p_slack_user_id) and d.archived_at is null
    ) m
    join staff_directory_v v on v.id = m.id
   order by m.rank
   limit 1
$$;

revoke all on function public.who_is(text) from public, anon, authenticated;
grant execute on function public.who_is(text) to service_role;
