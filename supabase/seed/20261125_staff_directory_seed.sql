-- Seed the Staff Directory. DRAFT v2 (26 Nov 2026) — not run against the live DB.
--
-- Run AFTER supabase/migrations/20261125_staff_directory.sql, and after
-- loading staff_directory_staging at apply time:
--
--   python3 scripts/directory_corrections_sql.py <corrections.json> | psql "$DB_URL"
--   SLACK_BOT_TOKEN=... python3 scripts/slack_users_sql.py --corrections <corrections.json> | psql "$DB_URL"
--   psql "$DB_URL" -f supabase/seed/20261125_staff_directory_seed.sql
--
-- No one's data is in this file. Everything comes from staging and the live
-- tables. Order of trust (Hannita, 26 Nov):
--
--   1. corrections (staging, source 'corrections') — Hannita's list. Wins.
--      Rows with remove:true are never seeded, and their emails keep every
--      other source from seeding them either.
--   2. Slack (staging, source 'slack' — everyone in users.list; slack_people,
--      the Facilities bot's 22-row cache, as a fallback when nothing was
--      loaded). Fills what corrections left empty; adds anyone else.
--   3. profiles, then pending_invites — portal accounts and saved invites the
--      first two did not know.
--   4. reminder_routing (Paola's Metrics bot) — teams, and a campus for rows
--      that still have none. READ ONLY.
--
-- One person = one row. Two Slack accounts become slack_user_id +
-- slack_ids_secondary; several emails become email + emails_secondary. Where
-- a person has TWO PORTAL PROFILES, neither is deleted or archived: the row
-- links one and says so in needs_review for an admin.
--
-- Idempotent. A second run inserts nobody twice. Corrections are re-applied
-- to rows the seed itself made; a row a person edited in the portal
-- (source 'self') or an admin edited (source 'admin') only has blanks filled
-- and new emails / Slack ids added, so nothing anybody set since is lost.
--
-- Last step (enabled, per Hannita 26 Nov): everyone in the directory without
-- a portal account gets a SAVED invite (pending_invites, role 'staff'). Saved
-- only — nothing is emailed. An admin sends each one from Admin → Users.

create or replace function pg_temp.sd_campus(n text) returns uuid language sql stable as $$
  select c.id from public.campuses c
   where c.parent_campus_id is null
     and (lower(c.name) = lower(btrim(n)) or lower(c.slug) = lower(btrim(n))
          or (lower(btrim(n)) in ('nyc','new york') and c.slug = 'nyc')
          or (lower(btrim(n)) in ('la') and c.slug = 'la')
          or (lower(btrim(n)) = 'online' and c.slug = 'online'))
   order by c.active desc limit 1
$$;

create or replace function pg_temp.sd_arr(j jsonb) returns text[] language sql immutable as $$
  select case when jsonb_typeof(j) = 'array'
              then array(select btrim(x) from jsonb_array_elements_text(j) x where nullif(btrim(x),'') is not null)
              when jsonb_typeof(j) = 'string' and nullif(btrim(j #>> '{}'),'') is not null then array[btrim(j #>> '{}')]
              else '{}'::text[] end
$$;

-- Test and shared accounts are not people (v1, 25 Nov).
create or replace function pg_temp.sd_is_test(n text) returns boolean language sql immutable as $$
  select coalesce(n,'') ~* '\m(test|beta)\M' or coalesce(n,'') ~* '^mosaic admin$'
$$;

create or replace function pg_temp.sd_note(old text, add text) returns text language sql immutable as $$
  select case when add is null or add = '' then old
              when old is null or old = '' then add
              when position(add in old) > 0 then old
              else old || '; ' || add end
$$;

do $seed$
declare
  r record; p jsonb; d public.staff_directory;
  v_emails text[]; v_slacks text[]; v_ids uuid[]; v_id uuid;
  v_campus uuid; v_loc uuid; v_over uuid[]; v_all boolean; v_min text[]; v_note text;
  v_bad text[]; x text; v_c uuid;
  n_ins int := 0; n_upd int := 0; n_inv int := 0;
begin
  create temp table if not exists _sd_removed (email text primary key) on commit drop;
  insert into _sd_removed
  select distinct lower(btrim(payload->>'email')) from staff_directory_staging
   where source = 'corrections' and coalesce((payload->>'remove')::boolean, false)
     and nullif(btrim(payload->>'email'),'') is not null
  on conflict do nothing;

  -- ------------------------------------------------ 1. corrections
  for r in select payload from staff_directory_staging
            where source = 'corrections' and not coalesce((payload->>'remove')::boolean, false)
            order by id loop
    p := r.payload;
    v_note := null;
    v_emails := array(select distinct lower(e) from unnest(array[p->>'email'] || pg_temp.sd_arr(p->'emails_secondary')) e where e is not null);
    -- order kept: the corrections' own "slack" is the primary, merge_slack the rest
    v_slacks := array(select s from unnest(array[nullif(btrim(p->>'slack'),'')] || pg_temp.sd_arr(p->'merge_slack')) with ordinality t(s, o)
                       where s is not null group by s order by min(o));

    v_campus := pg_temp.sd_campus(p->>'campus');
    if p->>'campus' is not null and v_campus is null then
      v_note := pg_temp.sd_note(v_note, 'campus "' || (p->>'campus') || '" not found');
    end if;
    v_loc := null;
    if nullif(p->>'location','') is not null then
      select l.id into v_loc from campus_locations l
       where l.campus_id = v_campus and lower(l.location) = lower(btrim(p->>'location'));
      if v_loc is null then v_note := pg_temp.sd_note(v_note, 'location "' || (p->>'location') || '" not found'); end if;
    end if;
    v_all := false; v_over := '{}';
    foreach x in array pg_temp.sd_arr(p->'oversees') loop
      if lower(x) = 'all' then v_all := true;
      else
        v_c := pg_temp.sd_campus(x);
        if v_c is null then v_note := pg_temp.sd_note(v_note, 'oversees "' || x || '" not found');
        else v_over := v_over || v_c; end if;
      end if;
    end loop;
    if nullif(p->>'oversees_location','') is not null then
      v_note := pg_temp.sd_note(v_note, 'also oversees location ' || (p->>'oversees_location') || ' (no field for that)');
    end if;
    -- Young Adults is Next Gen now (Hannita, 26 Nov)
    v_min := array(select distinct case when m = 'Young Adults' then 'Next Gen' else m end from unnest(pg_temp.sd_arr(p->'ministries')) m);
    v_bad := array(select m from unnest(v_min) m where not exists (select 1 from staff_ministries s where s.name = m));
    if cardinality(v_bad) > 0 then
      v_note := pg_temp.sd_note(v_note, 'ministry not in the list: ' || array_to_string(v_bad, ', '));
      v_min := array(select m from unnest(v_min) m where m <> all(v_bad));
    end if;
    if nullif(p->>'_note','') is not null then v_note := pg_temp.sd_note(v_note, p->>'_note'); end if;
    if (p->>'role') is not null and (p->>'role') not in ('admin','leader','staff','volunteer','campus_pastor','houses') then
      v_note := pg_temp.sd_note(v_note, 'role "' || (p->>'role') || '" not recognised'); p := p - 'role';
    end if;

    v_ids := array(select dd.id from staff_directory dd
                    where staff_directory_all_slack(dd) && v_slacks or staff_directory_all_emails(dd) && v_emails
                    order by (dd.source = 'corrections') desc, dd.created_at);
    -- A person found as two rows (an earlier run made a row from another
    -- source): fold rows the seed made into one; never touch a row a person
    -- or admin edited — flag it instead.
    if cardinality(v_ids) > 1 then
      for d in select * from staff_directory where id = any(v_ids[2:]) loop
        if d.source in ('self','admin') then
          update staff_directory set needs_review = pg_temp.sd_note(needs_review, 'same person as another row? (corrections)') where id = d.id;
          v_ids := array_remove(v_ids, d.id);
        else
          delete from staff_directory where id = d.id;
          v_ids := array_remove(v_ids, d.id);
        end if;
      end loop;
    end if;
    v_id := v_ids[1];

    if v_id is null then
      insert into staff_directory (slack_user_id, slack_ids_secondary, email, emails_secondary, full_name, nicknames, title,
                                   primary_campus_id, location_id, campus_ids_overseen, oversees_all, ministries, role,
                                   source, needs_review)
      values (v_slacks[1], coalesce(v_slacks[2:], '{}'), lower(p->>'email'),
              array(select e from unnest(v_emails) e where e is distinct from lower(p->>'email')),
              coalesce(nullif(btrim(p->>'name'),''), p->>'email'), pg_temp.sd_arr(p->'nicknames'), nullif(btrim(p->>'title'),''),
              v_campus, v_loc, v_over, v_all, v_min, p->>'role', 'corrections', v_note);
      n_ins := n_ins + 1;
    else
      select * into d from staff_directory where id = v_id;
      if d.source in ('self','admin') then
        update staff_directory set
          slack_user_id       = coalesce(d.slack_user_id, v_slacks[1]),
          slack_ids_secondary = d.slack_ids_secondary || v_slacks,
          email               = coalesce(d.email, lower(p->>'email')),
          emails_secondary    = d.emails_secondary || v_emails,
          nicknames           = d.nicknames || pg_temp.sd_arr(p->'nicknames'),
          title               = coalesce(d.title, nullif(btrim(p->>'title'),'')),
          primary_campus_id   = coalesce(d.primary_campus_id, v_campus),
          location_id         = coalesce(d.location_id, case when d.primary_campus_id is null or d.primary_campus_id = v_campus then v_loc end),
          ministries          = case when d.ministries = '{}' then v_min else d.ministries end
         where id = v_id;
      else
        update staff_directory set
          slack_user_id       = coalesce(v_slacks[1], d.slack_user_id),
          slack_ids_secondary = d.slack_ids_secondary || coalesce(v_slacks[2:], '{}') || array_remove(array[d.slack_user_id], v_slacks[1]),
          email               = coalesce(lower(p->>'email'), d.email),
          emails_secondary    = d.emails_secondary || v_emails || array_remove(array[d.email], lower(p->>'email')),
          full_name           = coalesce(nullif(btrim(p->>'name'),''), d.full_name),
          nicknames           = pg_temp.sd_arr(p->'nicknames'),
          title               = nullif(btrim(p->>'title'),''),
          primary_campus_id   = v_campus,
          location_id         = v_loc,
          campus_ids_overseen = v_over,
          oversees_all        = v_all,
          ministries          = v_min,
          role                = p->>'role',
          source              = 'corrections',
          needs_review        = v_note
         where id = v_id;
      end if;
      n_upd := n_upd + 1;
    end if;
  end loop;

  -- ------------------------------------------------ 2. Slack
  -- Everyone users.list returned (scripts/slack_users_sql.py already left out
  -- bots, deactivated accounts and guests not in corrections), plus
  -- slack_people for any id staging does not have.
  for r in
    select s.payload->>'slack' as slack, nullif(lower(btrim(s.payload->>'email')),'') as email,
           coalesce(nullif(btrim(s.payload->>'name'),''), s.payload->>'display_name') as name,
           nullif(btrim(s.payload->>'title'),'') as title,
           coalesce((s.payload->>'is_guest')::boolean, false) as is_guest, 'slack' as src
      from staff_directory_staging s where s.source = 'slack' and nullif(s.payload->>'slack','') is not null
    union all
    select sp.slack_user_id, nullif(lower(btrim(sp.email)),''), sp.real_name, nullif(btrim(sp.title),''), false, 'slack_people'
      from slack_people sp
     where not exists (select 1 from staff_directory_staging s where s.source = 'slack' and s.payload->>'slack' = sp.slack_user_id)
  loop
    if r.email is not null and exists (select 1 from _sd_removed z where z.email = r.email) then continue; end if;
    select * into d from staff_directory dd
     where r.slack = any(staff_directory_all_slack(dd)) or (r.email is not null and r.email = any(staff_directory_all_emails(dd)))
     order by (r.slack = any(staff_directory_all_slack(dd))) desc limit 1;
    if found then
      update staff_directory set
        slack_user_id       = coalesce(d.slack_user_id, r.slack),
        slack_ids_secondary = case when d.slack_user_id is not null and r.slack <> all(staff_directory_all_slack(d))
                                   then d.slack_ids_secondary || r.slack else d.slack_ids_secondary end,
        emails_secondary    = case when d.email is not null and r.email is not null and r.email <> all(staff_directory_all_emails(d))
                                   then d.emails_secondary || r.email else d.emails_secondary end,
        email               = coalesce(d.email, r.email),
        title               = coalesce(d.title, r.title)
       where id = d.id;
    elsif not pg_temp.sd_is_test(r.name) then
      insert into staff_directory (slack_user_id, email, full_name, title, source, needs_review)
      values (r.slack, r.email, coalesce(r.name, r.email, r.slack), r.title, r.src,
              'from Slack only — campus and ministries not set' || case when r.is_guest then '; Slack guest' else '' end);
      n_ins := n_ins + 1;
    end if;
  end loop;

  -- ------------------------------------------------ 3a. profiles
  -- The write trigger already linked a profile by any email on insert. What
  -- is left: profiles nobody has linked — a second profile for someone who
  -- has one (flag it, never delete it), or a person only the portal knows.
  for r in
    select p.id, lower(u.email) as email, coalesce(nullif(btrim(p.display_name),''), p.full_name) as name,
           p.role, coalesce(p.home_campus_id, p.campus_id) as campus
      from profiles p join auth.users u on u.id = p.id
     where p.archived_at is null and coalesce(p.role,'') <> 'houses'
       and not exists (select 1 from staff_directory dd where dd.profile_id = p.id)
     order by u.last_sign_in_at desc nulls last
  loop
    if exists (select 1 from _sd_removed z where z.email = r.email) then continue; end if;
    select * into d from staff_directory dd
     where r.email = any(staff_directory_all_emails(dd))
        or staff_directory_all_slack(dd) && array(select sp.slack_user_id from slack_people sp where sp.profile_id = r.id)
     limit 1;
    if found then
      if d.profile_id is null then
        update staff_directory set profile_id = r.id where id = d.id;
      else
        update staff_directory set needs_review = pg_temp.sd_note(needs_review,
          'two portal profiles (' || coalesce((select lower(u.email) from auth.users u where u.id = d.profile_id), '?') ||
          ' is linked; ' || r.email || ' is not) — keep both, an admin decides')
         where id = d.id;
      end if;
    elsif not pg_temp.sd_is_test(r.name) and not pg_temp.sd_is_test(r.email) then
      insert into staff_directory (email, full_name, primary_campus_id, role, profile_id, source, needs_review)
      values (r.email, case when r.name ~ '@' or r.name is null then r.email else r.name end, r.campus, r.role, r.id, 'profiles',
              'from a portal account only — not in Slack or the corrections');
      n_ins := n_ins + 1;
    end if;
  end loop;

  -- ------------------------------------------------ 3b. saved invites
  for r in
    select lower(pi.email) as email, pi.name, pi.role, pi.campus_id from pending_invites pi
     where not exists (select 1 from staff_directory dd where lower(pi.email) = any(staff_directory_all_emails(dd)))
       and not exists (select 1 from _sd_removed z where z.email = lower(pi.email))
  loop
    if pg_temp.sd_is_test(r.name) or pg_temp.sd_is_test(r.email) then continue; end if;
    insert into staff_directory (email, full_name, primary_campus_id, role, source, needs_review)
    values (r.email, coalesce(nullif(btrim(r.name),''), r.email), r.campus_id, r.role, 'pending_invites',
            'from a saved invite only — not in Slack or the corrections');
    n_ins := n_ins + 1;
  end loop;

  -- ------------------------------------------------ 4. reminder_routing
  update staff_directory sd
     set teams = rr.teams
    from (select slack_user_id, array_agg(group_label order by sort_order) as teams
            from reminder_routing where active and slack_user_id is not null group by 1) rr
   where sd.teams = '{}' and rr.slack_user_id = any(staff_directory_all_slack(sd));

  -- A campus for rows that still have none: the Metrics bot when it names
  -- exactly one, else the profile's home campus, else its permission campus,
  -- else the saved invite's.
  update staff_directory sd
     set primary_campus_id = coalesce(
           (select case when count(distinct rt.campus_id) = 1 then min(rt.campus_id::text)::uuid end
              from reminder_routing rt where rt.active and rt.slack_user_id = any(staff_directory_all_slack(sd))),
           (select coalesce(p.home_campus_id, p.campus_id) from profiles p where p.id = sd.profile_id),
           (select pi.campus_id from pending_invites pi where lower(pi.email) = any(staff_directory_all_emails(sd)) limit 1))
   where sd.primary_campus_id is null and sd.archived_at is null;

  -- ------------------------------------------------ 5. saved invites
  -- Hannita, 26 Nov: everyone in the directory without a portal account gets
  -- a saved invite, role 'staff'. Saved only: no email goes out until an
  -- admin presses "Send invite" in Admin → Users, which calls invite-user.
  insert into pending_invites (email, name, role, campus_id)
  select sd.email, sd.full_name, 'staff', sd.primary_campus_id
    from staff_directory sd
   where sd.profile_id is null and sd.email is not null and sd.archived_at is null
     and not exists (select 1 from auth.users u where lower(u.email) = any(staff_directory_all_emails(sd)))
     and not exists (select 1 from pending_invites pi where lower(pi.email) = any(staff_directory_all_emails(sd)))
     and not exists (select 1 from _sd_removed z where z.email = sd.email)
  on conflict (email) do nothing;
  get diagnostics n_inv = row_count;

  raise notice 'staff directory seed: % inserted, % corrected, % invites saved (none sent)', n_ins, n_upd, n_inv;
end
$seed$;
