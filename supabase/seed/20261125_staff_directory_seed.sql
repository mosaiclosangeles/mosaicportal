-- Seed the Staff Directory from what Mosaic already knows. DRAFT — not run.
--
-- Run AFTER supabase/migrations/20261125_staff_directory.sql. Idempotent: a
-- second run inserts nobody twice and only fills fields that are still empty,
-- so nothing a person or an admin has since set is overwritten.
--
-- No one's data is written inline — every value comes from the live tables.
-- Order of trust, per Hannita ("the metrics bot already had all of this mapped
-- out … use that as reference to start"):
--   1. reminder_routing  — Paola's Metrics bot mapping. Slack id, campus, and
--                          the areas each person owns. READ ONLY: never written.
--   2. slack_people + profiles, matched on lower(email) — and on
--      slack_people.profile_id, the hand-set link for a Slack account whose
--      email is not the Mosaic login.
--   3. profiles with no Slack match (portal users the directory must still know).
--   4. pending_invites   — the existing "account saved, not activated" list.
--
-- The SELECT below (between the BEGIN/END PROPOSAL markers) is the whole
-- proposal. It was dry-run read-only on 25 Nov 2026 to produce
-- staff_directory_preview.csv; run it on its own to preview again.
-- (The temp view disappears with the session; there is nothing to drop.)

create temp view staff_directory_proposal as
-- BEGIN PROPOSAL
with
au as (select id, lower(email) as email, last_sign_in_at from auth.users),
prof as (
  select p.id, au.email, au.last_sign_in_at, p.role, p.campus_id, p.home_campus_id,
         coalesce(nullif(btrim(p.display_name),''), nullif(btrim(p.full_name),'')) as name
    from profiles p join au on au.id = p.id
   where p.archived_at is null),
-- every email that leads to a profile: the login itself, or a Slack email linked by hand
email_profile as (
  select email, id as profile_id from prof
  union
  select lower(sp.email), sp.profile_id from slack_people sp
   where sp.profile_id is not null and sp.email is not null),
-- Ministry: a word map over the areas a person owns in reminder_routing, with
-- the Slack title as a fallback. A PROPOSAL — the vocabulary is for Hannita and
-- the team to settle (see docs/staff-directory.md).
ministry_map(ord, pattern, ministry) as (values
  -- first match wins, so a campus lead's "all data" row is read before the
  -- words in its covers ("Sunday + groups + special")
  (1,  'all data',                                         'Campus leadership'),
  (2,  'kid|famil|child',                                  'Kids'),
  (3,  'worship|choir|songwrit|msc|album',                 'Worship'),
  (4,  'house|group|bible',                                'Houses & Groups'),
  (5,  'young adult|summer session',                       'Young Adults'),
  (6,  'discipleship|welcome|baptism|next step|on ramp|men''s|community lunch', 'Next Steps'),
  (7,  'outreach|drive|campaign',                          'Outreach'),
  (8,  'girls',                                            'Women'),
  (9,  'online',                                           'Online'),
  (10, 'sunday|gathering|rall',                            'Gatherings'),
  (11, 'golf|leadership advance|global',                   'Events')),
title_map(ord, pattern, ministry) as (values
  (1, 'worship|msc',            'Worship'),
  (2, 'kid',                    'Kids'),
  (3, 'creative',               'Creative'),
  (4, 'pastor',                 'Campus leadership'),
  (5, 'general manager|office', 'Operations')),
-- 1. reminder_routing, one row per Slack id (active rows decide campus/teams/ministry)
rr_rows as (
  select r.*, (select m.ministry from ministry_map m
                where lower(r.group_label || ' ' || coalesce(r.covers,'')) ~ m.pattern
                order by m.ord limit 1) as ministry
    from reminder_routing r),
rr_min as (
  select slack_user_id, ministry, count(*) as n,
         rank() over (partition by slack_user_id order by count(*) desc) as rk
    from rr_rows where active and ministry is not null
   group by 1,2),
rr as (
  select r.slack_user_id,
         (array_agg(r.profile_id) filter (where r.profile_id is not null))[1] as profile_id,
         min(r.owner_name) as owner_name,
         array_agg(distinct r.campus_id) filter (where r.campus_id is not null and r.active) as campuses,
         array_agg(r.group_label order by r.sort_order) filter (where r.active) as teams,
         (select string_agg(m.ministry, ' / ' order by m.ministry) from rr_min m
           where m.slack_user_id = r.slack_user_id and m.rk = 1) as ministry,
         (select max(m.n) from rr_min m where m.slack_user_id = r.slack_user_id and m.rk = 1) as ministry_n
    from reminder_routing r
   where r.slack_user_id is not null
   group by r.slack_user_id),
-- all candidate rows, each resolved to a person key
cand as (
  select 'reminder_routing' as source, 1 as prio, rr.slack_user_id, p.email, rr.profile_id,
         rr.owner_name as name, null::text as title, rr.campuses, rr.teams, rr.ministry, rr.ministry_n,
         null::text as role, null::uuid as invite_campus
    from rr left join prof p on p.id = rr.profile_id
  union all
  select 'slack_people', 2, sp.slack_user_id, lower(sp.email),
         coalesce(sp.profile_id, ep.profile_id), sp.real_name, sp.title, null, null, null, null, null, null
    from slack_people sp left join email_profile ep on ep.email = lower(sp.email)
  union all
  select 'profiles', 3, null, p.email, p.id, p.name, null, null, null, null, null, p.role, null
    from prof p
  union all
  select 'pending_invites', 4, null, lower(pi.email), ep.profile_id, pi.name, null, null, null, null, null,
         pi.role, pi.campus_id
    from pending_invites pi left join email_profile ep on ep.email = lower(pi.email)),
keyed as (
  select c.*,
         coalesce(c.profile_id::text,
                  -- a Slack id already known to reminder_routing joins its person
                  (select rr.profile_id::text from rr where rr.slack_user_id = c.slack_user_id),
                  c.email) as person_key
    from cand c),
person as (
  select k.person_key,
         (array_agg(k.source order by k.prio))[1]                                    as source,
         array_agg(distinct k.slack_user_id) filter (where k.slack_user_id is not null) as slack_ids,
         (array_agg(k.email order by k.prio) filter (where k.email is not null))[1]   as email,
         (array_agg(k.profile_id) filter (where k.profile_id is not null))[1]         as profile_id,
         (array_agg(k.name order by k.prio) filter (where k.name is not null and k.name !~ '@'))[1] as any_name,
         (array_agg(k.title) filter (where k.title is not null))[1]                   as title,
         max(k.campuses)                                                              as rr_campuses,
         max(k.teams)                                                                 as teams,
         (array_agg(k.ministry) filter (where k.ministry is not null))[1]             as rr_ministry,
         max(k.ministry_n)                                                            as ministry_n,
         (array_agg(k.role order by k.prio) filter (where k.role is not null))[1]     as cand_role,
         (array_agg(k.invite_campus) filter (where k.invite_campus is not null))[1]   as invite_campus,
         bool_or(k.source = 'reminder_routing')                                       as in_rr
    from keyed k group by k.person_key),
resolved as (
  select ps.*, case when pr.name !~ '@' then pr.name end as profile_name, pr.role as profile_role, pr.last_sign_in_at,
         pr.home_campus_id, pr.campus_id as perm_campus_id,
         -- campus: Metrics bot (when it names exactly one) → home campus → permission campus → invite
         case when cardinality(ps.rr_campuses) = 1 then ps.rr_campuses[1] end as rr_campus,
         (select array_agg(distinct x) from unnest(
            coalesce(ps.rr_campuses,'{}') || array[pr.home_campus_id, pr.campus_id, ps.invite_campus]) x
           where x is not null) as all_campuses,
         (select tm.ministry from title_map tm where lower(coalesce(ps.title,'')) ~ tm.pattern order by tm.ord limit 1) as title_ministry
    from person ps left join prof pr on pr.id = ps.profile_id)
select r.slack_ids[1]                                                  as slack_user_id,
       r.email,
       coalesce(r.profile_name, r.any_name, r.email)                   as full_name,
       coalesce(r.rr_campus, r.home_campus_id, r.perm_campus_id, r.invite_campus) as primary_campus_id,
       case when r.rr_ministry !~ ' / ' then r.rr_ministry
            when r.rr_ministry is null then r.title_ministry end       as ministry,
       coalesce(r.teams, '{}')                                         as teams,
       coalesce(r.profile_role, r.cand_role)                           as role,
       r.profile_id,
       r.source,
       case when r.last_sign_in_at is not null then 'active' else 'not activated' end as status,
       case when r.last_sign_in_at is not null then 'signed_in'
            when r.profile_id is not null      then 'invite_sent'
            when exists (select 1 from pending_invites pi where lower(pi.email) = r.email) then 'invite_saved'
            else 'no_invite' end                                       as activation,
       (coalesce(r.profile_name, r.any_name, '') ~* '\m(test|beta)\M'
        or coalesce(r.profile_name, r.any_name, '') ~* '^mosaic admin$')  as likely_test,
       nullif(concat_ws('; ',
         case when cardinality(r.all_campuses) > 1 then 'two or more campuses: ' ||
           (select string_agg(c.name, ' / ' order by c.name) from campuses c where c.id = any(r.all_campuses)) end,
         case when cardinality(r.rr_campuses) > 1 then 'reminder_routing names several campuses' end,
         case when r.all_campuses is null then 'no campus (falls back to LA)' end,
         case when r.slack_ids is null then 'no Slack id' end,
         case when cardinality(r.slack_ids) > 1 then 'several Slack ids: ' || array_to_string(r.slack_ids, ', ') end,
         case when r.rr_ministry ~ ' / ' then 'ministry tie: ' || r.rr_ministry end,
         case when r.rr_ministry is null and r.title_ministry is null then 'no ministry' end,
         case when r.rr_ministry is null and r.title_ministry is not null then 'ministry from Slack title only' end,
         case when r.ministry_n = 1 and r.rr_ministry !~ ' / ' then 'ministry from one reminder_routing row' end,
         case when coalesce(r.profile_name, r.any_name, '') ~* '\m(test|beta)\M'
                or coalesce(r.profile_name, r.any_name, '') ~* '^mosaic admin$'
              then 'test or shared account, not a person — not seeded' end,
         case when (select count(*) from person o
                     left join prof op on op.id = o.profile_id
                    where o.person_key <> r.person_key
                      and lower(coalesce(op.name, o.any_name)) = lower(coalesce(r.profile_name, r.any_name))) > 0
              then 'same name as another row — same person?' end
       ), '')                                                          as conflicts
  from resolved r
-- END PROPOSAL
;

-- ---------------------------------------------------------------- insert
-- New people only. Any unique key already present (Slack id, email, profile)
-- means the person exists, and the row is skipped.
insert into public.staff_directory
       (slack_user_id, email, full_name, primary_campus_id, ministry, teams, role, profile_id, source, needs_review)
select slack_user_id, email, full_name, primary_campus_id, ministry, teams, role, profile_id, source, conflicts
  from staff_directory_proposal
 where not likely_test
on conflict do nothing;

-- ---------------------------------------------------------------- fill blanks
-- For people already in the directory: fill only what is still empty. A value
-- somebody set — by hand, in Settings, or in Admin — is never replaced.
update public.staff_directory d
   set slack_user_id     = coalesce(d.slack_user_id, s.slack_user_id),
       email             = coalesce(d.email, s.email),
       primary_campus_id = coalesce(d.primary_campus_id, s.primary_campus_id),
       ministry          = coalesce(d.ministry, s.ministry),
       teams             = case when d.teams = '{}' then s.teams else d.teams end,
       role              = coalesce(d.role, s.role),
       profile_id        = coalesce(d.profile_id, s.profile_id),
       needs_review      = coalesce(d.needs_review, s.conflicts)
  from staff_directory_proposal s
 where not s.likely_test
   and (d.profile_id = s.profile_id or d.slack_user_id = s.slack_user_id or d.email = s.email)
   and (s.slack_user_id is null or d.slack_user_id is not null
        or not exists (select 1 from staff_directory x where x.slack_user_id = s.slack_user_id))
   and (s.email is null or d.email is not null
        or not exists (select 1 from staff_directory x where x.email = s.email))
   and (s.profile_id is null or d.profile_id is not null
        or not exists (select 1 from staff_directory x where x.profile_id = s.profile_id));

-- ---------------------------------------------------------------- accounts
-- Hannita: "everybody in Slack needs to have an account in the staff portal."
-- The existing way to give somebody an account without emailing them yet is a
-- pending_invites row. This step is LEFT COMMENTED OUT on purpose: it chooses a
-- role ('staff') for people nobody has assigned one to, and pending_invites is
-- the portal's Admin list. Uncomment only once Hannita has said which role.
--
-- insert into public.pending_invites (email, name, role, campus_id)
-- select d.email, d.full_name, coalesce(d.role, 'staff'), d.primary_campus_id
--   from public.staff_directory d
--  where d.profile_id is null and d.email is not null and d.archived_at is null
--    and coalesce(d.role,'staff') in ('admin','staff','leader','volunteer')
--    and not exists (select 1 from auth.users u where lower(u.email) = d.email)
-- on conflict (email) do nothing;

