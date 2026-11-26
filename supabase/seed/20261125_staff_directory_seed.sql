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

-- Keys in `want` that no OTHER live row holds. Merging a key another row still
-- owns would trip the one-person-one-row check and, before 27 Nov, roll the
-- whole seed back (portal #12 review, finding 4).
create or replace function pg_temp.sd_free_emails(want text[], self uuid) returns text[] language sql stable as $$
  select coalesce(array(select e from unnest(want) with ordinality t(e, o)
    where e is not null and not exists (select 1 from public.staff_directory x
      where x.archived_at is null and x.id is distinct from self and e = any(public.staff_directory_all_emails(x)))
    order by o), '{}')
$$;
create or replace function pg_temp.sd_free_slacks(want text[], self uuid) returns text[] language sql stable as $$
  select coalesce(array(select e from unnest(want) with ordinality t(e, o)
    where e is not null and not exists (select 1 from public.staff_directory x
      where x.archived_at is null and x.id is distinct from self and e = any(public.staff_directory_all_slack(x)))
    order by o), '{}')
$$;

do $seed$
declare
  r record; p jsonb; d public.staff_directory;
  v_emails text[]; v_slacks text[]; v_ids uuid[]; v_id uuid; v_e text[]; v_s text[]; v_lost text[]; v_q uuid;
  v_campus uuid; v_loc uuid; v_over uuid[]; v_all boolean; v_min text[]; v_note text;
  v_bad text[]; x text; v_c uuid; v_use_slack_people boolean;
  n_ins int := 0; n_upd int := 0; n_inv int := 0; n_arch int := 0; n_skip int := 0;
begin
  -- Removals match on EVERY key the corrections give — primary and secondary
  -- emails, the Slack id and any merged ones (finding 3).
  create temp table if not exists _sd_rm_email (email text primary key) on commit drop;
  create temp table if not exists _sd_rm_slack (slack text primary key) on commit drop;
  insert into _sd_rm_email
  select distinct lower(btrim(e)) from staff_directory_staging s,
         unnest(array[s.payload->>'email'] || pg_temp.sd_arr(s.payload->'emails_secondary')) e
   where s.source = 'corrections' and coalesce((s.payload->>'remove')::boolean, false) and nullif(btrim(e),'') is not null
  on conflict do nothing;
  insert into _sd_rm_slack
  select distinct btrim(x2) from staff_directory_staging s,
         unnest(array[s.payload->>'slack'] || pg_temp.sd_arr(s.payload->'merge_slack')) x2
   where s.source = 'corrections' and coalesce((s.payload->>'remove')::boolean, false) and nullif(btrim(x2),'') is not null
  on conflict do nothing;

  -- ------------------------------------------------ 0. removals
  -- A row an earlier run made for someone now marked remove is archived, not
  -- deleted: its history (and any profile link) stays, it leaves every list.
  update staff_directory sd
     set archived_at = now(), needs_review = pg_temp.sd_note(sd.needs_review, 'removed in the corrections')
   where sd.archived_at is null
     and (staff_directory_all_emails(sd) && array(select email from _sd_rm_email)
          or staff_directory_all_slack(sd) && array(select slack from _sd_rm_slack));
  get diagnostics n_arch = row_count;

  -- ------------------------------------------------ 1. corrections
  for r in select payload from staff_directory_staging
            where source = 'corrections' and not coalesce((payload->>'remove')::boolean, false)
            order by id loop
    p := r.payload;
    v_note := null;
    v_emails := array(select e from unnest(array[lower(btrim(p->>'email'))] || array(select lower(y) from unnest(pg_temp.sd_arr(p->'emails_secondary')) y))
                       with ordinality t(e, o) where nullif(e,'') is not null group by e order by min(o));
    -- order kept: the corrections' own "slack" is the primary, merge_slack the rest
    v_slacks := array(select s from unnest(array[nullif(btrim(p->>'slack'),'')] || pg_temp.sd_arr(p->'merge_slack')) with ordinality t(s, o)
                       where s is not null group by s order by min(o));
    if v_emails && array(select email from _sd_rm_email) or v_slacks && array(select slack from _sd_rm_slack) then
      raise notice 'corrections: % is both kept and removed — skipped', coalesce(p->>'name', p->>'email');
      n_skip := n_skip + 1;
      continue;
    end if;

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

    -- One person at a time: a clash puts THIS person in needs_review and the
    -- run carries on, instead of rolling every other person back (finding 4).
    begin
      v_ids := array(select dd.id from staff_directory dd
                      where dd.archived_at is null
                        and (staff_directory_all_slack(dd) && v_slacks or staff_directory_all_emails(dd) && v_emails)
                      order by (dd.source = 'corrections') desc, (dd.source in ('self','admin')) desc, dd.created_at);
      -- Found as several rows: fold in rows the seed made; a row a person or
      -- an admin edited is kept, keeps its own keys, and is flagged.
      if cardinality(v_ids) > 1 then
        for d in select * from staff_directory where id = any(v_ids[2:]) loop
          if d.source in ('self','admin') then
            update staff_directory set needs_review = pg_temp.sd_note(needs_review,
              'same person as ' || coalesce(p->>'name', p->>'email') || '? (corrections) — merge by hand') where id = d.id;
          else
            delete from staff_directory where id = d.id;
          end if;
        end loop;
      end if;
      v_id := v_ids[1];

      -- Only keys no other live row still holds.
      v_e := pg_temp.sd_free_emails(v_emails, v_id);
      v_s := pg_temp.sd_free_slacks(v_slacks, v_id);
      v_lost := array(select k from unnest(v_emails || v_slacks) k where k <> all(v_e || v_s));
      if cardinality(v_lost) > 0 then
        v_note := pg_temp.sd_note(v_note, 'also ' || array_to_string(v_lost, ', ') || ', held by another row — merge by hand');
      end if;

      if v_id is null then
        if coalesce(v_s[1], v_e[1]) is null then
          raise unique_violation using message = 'every email and Slack id is held by another row';
        end if;
        insert into staff_directory (slack_user_id, slack_ids_secondary, email, emails_secondary, full_name, nicknames, title,
                                     primary_campus_id, location_id, campus_ids_overseen, oversees_all, ministries, role,
                                     source, needs_review)
        values (v_s[1], coalesce(v_s[2:], '{}'),
                case when lower(p->>'email') = any(v_e) then lower(p->>'email') end,
                array(select e from unnest(v_e) e where e is distinct from lower(p->>'email')),
                coalesce(nullif(btrim(p->>'name'),''), p->>'email'), pg_temp.sd_arr(p->'nicknames'), nullif(btrim(p->>'title'),''),
                v_campus, v_loc, v_over, v_all, v_min, p->>'role', 'corrections', v_note);
        n_ins := n_ins + 1;
      else
        select * into d from staff_directory where id = v_id;
        if d.source in ('self','admin') then
          update staff_directory set
            slack_user_id       = coalesce(d.slack_user_id, v_s[1]),
            slack_ids_secondary = d.slack_ids_secondary || v_s,
            email               = coalesce(d.email, case when lower(p->>'email') = any(v_e) then lower(p->>'email') end),
            emails_secondary    = d.emails_secondary || v_e,
            nicknames           = d.nicknames || pg_temp.sd_arr(p->'nicknames'),
            title               = coalesce(d.title, nullif(btrim(p->>'title'),'')),
            primary_campus_id   = coalesce(d.primary_campus_id, v_campus),
            location_id         = coalesce(d.location_id, case when d.primary_campus_id is null or d.primary_campus_id = v_campus then v_loc end),
            ministries          = case when d.ministries = '{}' then v_min else d.ministries end,
            needs_review        = case when cardinality(v_lost) > 0 or cardinality(v_ids) > 1
                                       then pg_temp.sd_note(d.needs_review, coalesce(v_note, 'another row looks like the same person — merge by hand'))
                                       else d.needs_review end
           where id = v_id;
        else
          update staff_directory set
            slack_user_id       = coalesce(case when nullif(btrim(p->>'slack'),'') = any(v_s) then btrim(p->>'slack') end, d.slack_user_id),
            slack_ids_secondary = d.slack_ids_secondary || v_s || array_remove(array[d.slack_user_id], btrim(p->>'slack')),
            email               = coalesce(case when lower(p->>'email') = any(v_e) then lower(p->>'email') end, d.email),
            emails_secondary    = d.emails_secondary || v_e || array_remove(array[d.email], lower(p->>'email')),
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
    exception when unique_violation then
      n_skip := n_skip + 1;
      raise notice 'corrections: % not applied — %', coalesce(p->>'name', p->>'email'), sqlerrm;
      update staff_directory dd set needs_review = pg_temp.sd_note(dd.needs_review, 'corrections could not be applied: ' || sqlerrm)
       where dd.archived_at is null and (staff_directory_all_slack(dd) && v_slacks or staff_directory_all_emails(dd) && v_emails);
    end;
  end loop;

  -- ------------------------------------------------ 2. Slack
  -- Everyone users.list returned (scripts/slack_users_sql.py already left out
  -- bots, deactivated accounts, guests and removals). slack_people — the
  -- Facilities bot's cache, which never forgets an account — is used ONLY
  -- when no Slack list was loaded at all; otherwise it would bring back the
  -- deactivated accounts and guests the list left out (finding 2).
  v_use_slack_people := not exists (select 1 from staff_directory_staging where source = 'slack');
  for r in
    select s.payload->>'slack' as slack, nullif(lower(btrim(s.payload->>'email')),'') as email,
           coalesce(nullif(btrim(s.payload->>'name'),''), s.payload->>'display_name') as name,
           nullif(btrim(s.payload->>'title'),'') as title,
           coalesce((s.payload->>'is_guest')::boolean, false) as is_guest, 'slack' as src
      from staff_directory_staging s where s.source = 'slack' and nullif(s.payload->>'slack','') is not null
    union all
    select sp.slack_user_id, nullif(lower(btrim(sp.email)),''), sp.real_name, nullif(btrim(sp.title),''), false, 'slack_people'
      from slack_people sp where v_use_slack_people
  loop
    if r.slack in (select slack from _sd_rm_slack) or r.email in (select email from _sd_rm_email) then continue; end if;
    begin
      select * into d from staff_directory dd
       where dd.archived_at is null and r.slack = any(staff_directory_all_slack(dd));
      if found then
        -- The Slack id is known. Its email joins the row only if no OTHER row
        -- holds it — otherwise that is two rows for one person, for an admin.
        select dd.id into v_q from staff_directory dd
         where dd.archived_at is null and dd.id <> d.id and r.email = any(staff_directory_all_emails(dd)) limit 1;
        if v_q is not null then
          update staff_directory set needs_review = pg_temp.sd_note(needs_review,
            'Slack account ' || r.slack || ' uses ' || r.email || ', which is on another row — same person?')
           where id in (d.id, v_q);
        else
          update staff_directory set
            emails_secondary = case when d.email is not null and r.email is not null and r.email <> all(staff_directory_all_emails(d))
                                    then d.emails_secondary || r.email else d.emails_secondary end,
            email            = coalesce(d.email, r.email),
            title            = coalesce(d.title, r.title)
           where id = d.id;
        end if;
      else
        select * into d from staff_directory dd
         where dd.archived_at is null and r.email is not null and r.email = any(staff_directory_all_emails(dd)) limit 1;
        if found then
          update staff_directory set
            slack_user_id       = coalesce(d.slack_user_id, r.slack),
            slack_ids_secondary = case when d.slack_user_id is not null then d.slack_ids_secondary || r.slack else d.slack_ids_secondary end,
            title               = coalesce(d.title, r.title)
           where id = d.id;
        elsif not pg_temp.sd_is_test(r.name) then
          insert into staff_directory (slack_user_id, email, full_name, title, source, needs_review)
          values (r.slack, r.email, coalesce(r.name, r.email, r.slack), r.title, r.src,
                  'from Slack only — campus and ministries not set' || case when r.is_guest then '; Slack guest' else '' end);
          n_ins := n_ins + 1;
        end if;
      end if;
    exception when unique_violation then
      n_skip := n_skip + 1;
      raise notice 'slack: % not applied — %', r.slack, sqlerrm;
    end;
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
    if r.email in (select email from _sd_rm_email)
       or exists (select 1 from slack_people sp where sp.profile_id = r.id and sp.slack_user_id in (select slack from _sd_rm_slack)) then
      continue;
    end if;
    begin
      select * into d from staff_directory dd
       where dd.archived_at is null
         and (r.email = any(staff_directory_all_emails(dd))
              or staff_directory_all_slack(dd) && array(select sp.slack_user_id from slack_people sp where sp.profile_id = r.id))
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
    exception when unique_violation then
      n_skip := n_skip + 1;
      raise notice 'profile % not applied — %', r.email, sqlerrm;
    end;
  end loop;

  -- ------------------------------------------------ 3b. saved invites
  for r in
    select lower(pi.email) as email, pi.name, pi.role, pi.campus_id from pending_invites pi
     where not exists (select 1 from staff_directory dd where lower(pi.email) = any(staff_directory_all_emails(dd)))
       and lower(pi.email) not in (select email from _sd_rm_email)
  loop
    if pg_temp.sd_is_test(r.name) or pg_temp.sd_is_test(r.email) then continue; end if;
    begin
      insert into staff_directory (email, full_name, primary_campus_id, role, source, needs_review)
      values (r.email, coalesce(nullif(btrim(r.name),''), r.email), r.campus_id, r.role, 'pending_invites',
              'from a saved invite only — not in Slack or the corrections');
      n_ins := n_ins + 1;
    exception when unique_violation then
      n_skip := n_skip + 1;
      raise notice 'invite % not applied — %', r.email, sqlerrm;
    end;
  end loop;

  -- ------------------------------------------------ 4. reminder_routing
  update staff_directory sd
     set teams = rr.teams
    from (select slack_user_id, array_agg(group_label order by sort_order) as teams
            from reminder_routing where active and slack_user_id is not null group by 1) rr
   where sd.teams = '{}' and sd.archived_at is null and rr.slack_user_id = any(staff_directory_all_slack(sd));

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
  -- staff_directory_save_invite() makes every other check (archived, no
  -- email, an account under any email, an invite already saved); the seed
  -- adds only what the function cannot know: the corrections' removals.
  select count(*) into n_inv
    from staff_directory sd
   where sd.archived_at is null and sd.profile_id is null and sd.email is not null
     and not (staff_directory_all_emails(sd) && array(select email from _sd_rm_email))
     and not (staff_directory_all_slack(sd) && array(select slack from _sd_rm_slack))
     and staff_directory_save_invite(sd.id) = 'saved';

  raise notice 'staff directory seed: % inserted, % corrected, % archived as removed, % skipped (see needs_review), % invites saved (none sent)',
    n_ins, n_upd, n_arch, n_skip, n_inv;
end
$seed$;
