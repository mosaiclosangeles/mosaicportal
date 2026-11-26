-- Go-live step checks, made-up people. Runs after stubs + migration (see
-- staff_directory_stubs.sql). Guards portal #12 review finding 7.
\set ON_ERROR_STOP 1
insert into campuses (id, name, slug) values
  ('00000000-0000-0000-0000-0000000000a1','Los Angeles','la'),
  ('00000000-0000-0000-0000-0000000000a2','Mexico','mexico');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000021','alt.login@example.org'),   -- logs in with a SECONDARY email
  ('00000000-0000-0000-0000-000000000022','boss@example.org');
insert into profiles (id, full_name, role, campus_id, campus_ids) values
  ('00000000-0000-0000-0000-000000000021','Alt Login','staff','00000000-0000-0000-0000-0000000000a1','{00000000-0000-0000-0000-0000000000a1}'),
  ('00000000-0000-0000-0000-000000000022','Boss','admin','00000000-0000-0000-0000-0000000000a1','{00000000-0000-0000-0000-0000000000a1}');
insert into staff_directory_staging (source, payload) values
  ('corrections','{"name":"Alt Login","email":"primary@example.org","emails_secondary":["alt.login@example.org"],"_access":"all"}'),
  ('corrections','{"name":"Boss","email":"boss@example.org","_access":"all"}'),
  ('corrections','{"name":"Nobody Yet","email":"nobody@example.org","_access":"all"}');

\ir ../migrations/20261126_golive_all_campus_access.sql

do $$ declare r record; begin
  select * into r from profiles where id = '00000000-0000-0000-0000-000000000021';
  if cardinality(r.campus_ids) is distinct from 2 or r.role <> 'staff' then
    raise exception 'finding 7: a person whose login is a secondary email did not get every campus: %', row_to_json(r);
  end if;
  select * into r from profiles where id = '00000000-0000-0000-0000-000000000022';
  if r.campus_ids is not null then raise exception 'an admin kept a narrowing campus list'; end if;
  if (select count(*) from _golive_unmatched) <> 1 then
    raise exception 'finding 7: an _access row with no profile was not reported';
  end if;
end $$;
select 'all go-live checks passed' as result;
