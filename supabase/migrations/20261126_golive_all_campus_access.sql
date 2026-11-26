-- GO-LIVE STEP — portal PERMISSION, not directory data. DRAFT, not applied.
--
-- Hannita, 26 Nov 2026: two people must see ALL campuses in the portal. That
-- is a permission (profiles.role / profiles.campus_ids), so it lives here and
-- not in staff_directory — oversees_all there is informational and grants
-- nothing.
--
-- Who: the corrections rows that carry an "_access" note (Hannita's local
-- file, loaded into staff_directory_staging by
-- scripts/directory_corrections_sql.py). No name or email is written here.
-- A person is found by ANY of their emails (primary or secondary) and through
-- the directory row's profile link, and every live portal profile they have
-- gets it — someone may sign in with their second address. An _access row
-- that finds no profile is reported (NOTICE, and _golive_unmatched for the
-- session), never silently skipped.
-- Run it in the same session as the seed, while staging is loaded.
--
-- How campus visibility works today (checked 26 Nov, read-only):
--   * role 'admin' already sees every campus — is_admin() in RLS, and
--     campusesFor() in the portal returns every campus for an admin…
--   * …UNLESS campus_ids is non-empty: campusesFor() returns campus_ids
--     first, so a list there NARROWS even an admin.
--   * for anyone else, campus_ids is the list of campuses they can see.
-- Both people this is for are role 'admin' with campus_ids null today, so
-- this changes nothing for them now. It exists so the decision is written
-- down and holds if either profile is ever edited.
--
-- So, per person:
--   admin, campus_ids empty     -> nothing to do
--   admin, campus_ids non-empty -> campus_ids := null (back to every campus,
--                                  including campuses added later)
--   not admin                   -> campus_ids := every active top-level
--                                  campus. The role is NOT raised to admin:
--                                  that would grant user management, which
--                                  nobody asked for.

-- Preview (run first, on its own): the same match as below, changing nothing.
--   select s.payload->>'name' as who, p.id, p.role, p.campus_ids
--     from staff_directory_staging s
--     left join lateral (
--       select p.* from profiles p
--        where p.archived_at is null
--          and (p.id in (select u.id from auth.users u
--                         where lower(u.email) = any(array[lower(s.payload->>'email')] ||
--                               array(select lower(e) from jsonb_array_elements_text(coalesce(s.payload->'emails_secondary','[]')) e)))
--               or p.id in (select d.profile_id from staff_directory d
--                            where d.archived_at is null and lower(s.payload->>'email') = any(staff_directory_all_emails(d))))) p on true
--    where s.source = 'corrections' and s.payload ? '_access';

do $golive$
declare a record; r record; v_emails text[]; v_hit boolean; n int := 0;
begin
  if not exists (select 1 from staff_directory_staging where source = 'corrections' and payload ? '_access') then
    raise exception 'No corrections with "_access" are loaded — load the corrections file first (scripts/directory_corrections_sql.py).';
  end if;
  create temp table if not exists _golive_unmatched (who text);
  truncate _golive_unmatched;
  for a in select payload from staff_directory_staging where source = 'corrections' and payload ? '_access' order by id loop
    v_emails := array(select lower(btrim(e)) from unnest(array[a.payload->>'email'] ||
                  array(select jsonb_array_elements_text(coalesce(a.payload->'emails_secondary','[]'::jsonb)))) e
                 where nullif(btrim(e),'') is not null);
    v_hit := false;
    for r in
      select p.id, p.role, p.campus_ids from profiles p
       where p.archived_at is null
         and (p.id in (select u.id from auth.users u where lower(u.email) = any(v_emails))
              or p.id in (select d.profile_id from staff_directory d
                           where d.archived_at is null and staff_directory_all_emails(d) && v_emails))
    loop
      v_hit := true;
      if r.role = 'admin' then
        if coalesce(cardinality(r.campus_ids), 0) > 0 then
          update profiles set campus_ids = null where id = r.id;
          n := n + 1;
        end if;
      else
        update profiles
           set campus_ids = array(select c.id from campuses c
                                   where c.active and c.parent_campus_id is null order by c.name)
         where id = r.id;
        n := n + 1;
      end if;
    end loop;
    if not v_hit then
      insert into _golive_unmatched values (coalesce(a.payload->>'name', a.payload->>'email'));
      raise notice 'all-campus access: no portal profile for % — nothing set; run this again once they have an account',
        coalesce(a.payload->>'name', a.payload->>'email');
    end if;
  end loop;
  raise notice 'all-campus access: % profile(s) changed', n;
end
$golive$;
