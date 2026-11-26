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

-- Preview (run first, on its own):
--   select lower(s.payload->>'email') as email, p.role, p.campus_ids,
--          case when p.id is null then 'no portal profile yet — nothing to set'
--               when p.role = 'admin' and coalesce(cardinality(p.campus_ids),0) = 0 then 'already sees every campus'
--               when p.role = 'admin' then 'clear campus_ids'
--               else 'set campus_ids to every active campus' end as would
--     from staff_directory_staging s
--     left join auth.users u on lower(u.email) = lower(s.payload->>'email')
--     left join profiles p on p.id = u.id
--    where s.source = 'corrections' and s.payload ? '_access';

do $golive$
declare r record; n int := 0;
begin
  if not exists (select 1 from staff_directory_staging where source = 'corrections' and payload ? '_access') then
    raise exception 'No corrections with "_access" are loaded — load the corrections file first (scripts/directory_corrections_sql.py).';
  end if;
  for r in
    select p.id, p.role, p.campus_ids, lower(s.payload->>'email') as email
      from staff_directory_staging s
      join auth.users u on lower(u.email) = lower(s.payload->>'email')
      join profiles p on p.id = u.id
     where s.source = 'corrections' and s.payload ? '_access' and p.archived_at is null
  loop
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
  raise notice 'all-campus access: % profile(s) changed', n;
end
$golive$;
