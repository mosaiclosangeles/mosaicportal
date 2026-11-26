-- Seed checks, made-up people. Runs after staff_directory_stubs.sql and the
-- migration on a THROWAWAY Postgres (see staff_directory_stubs.sql):
--   psql -d sd_test -v ON_ERROR_STOP=1 -f supabase/tests/staff_directory_stubs.sql \
--     -f supabase/migrations/20261125_staff_directory.sql -f supabase/tests/staff_directory_seed_test.sql
-- Each block names the portal #12 review finding it guards.
\set ON_ERROR_STOP 1

insert into campuses (id, name, slug) values ('00000000-0000-0000-0000-0000000000a1','Los Angeles','la');
insert into auth.users (id, email, last_sign_in_at) values
  ('00000000-0000-0000-0000-000000000011','keep@example.org', now()),
  ('00000000-0000-0000-0000-000000000012','rm.home@example.org', null);
insert into profiles (id, full_name, role) values
  ('00000000-0000-0000-0000-000000000011','Keep Person','staff'),
  ('00000000-0000-0000-0000-000000000012','Removed Person','staff');
-- An invite that already existed before the seed, for someone being removed.
insert into pending_invites (email, name, role) values ('rm.home@example.org','Removed Person','staff');
-- The Facilities bot's cache: one account Slack no longer lists (deactivated).
insert into slack_people (slack_user_id, email, real_name) values ('UGONE','gone@example.org','Gone Account');

-- Rows that exist before this run.
-- Finding 3: a row an earlier run made for someone now marked remove.
insert into staff_directory (slack_user_id, email, full_name, source) values ('URM', 'rm.work@example.org', 'Removed Person', 'slack');
-- Finding 4 (corrections): one person as two admin-edited rows.
insert into staff_directory (slack_user_id, email, full_name, source) values ('UTWO', 'two@example.org', 'Two A', 'admin');
insert into staff_directory (slack_user_id, email, full_name, source) values ('UTWO2', 'two.alt@example.org', 'Two B', 'admin');
-- Finding 4 (Slack): a Slack id on one row, that member's email on another.
insert into staff_directory (slack_user_id, email, full_name, source) values ('UP', 'p@example.org', 'Row P', 'admin');
insert into staff_directory (slack_user_id, email, full_name, source) values ('UQ', 'x@example.org', 'Row Q', 'admin');

insert into staff_directory_staging (source, payload) values
  ('corrections', '{"name":"Keep Person","email":"keep@example.org","slack":"UKEEP","campus":"Los Angeles","ministries":["Kids"]}'),
  ('corrections', '{"name":"Two Rows","email":"two@example.org","slack":"UTWO","merge_slack":["UTWO2"],"emails_secondary":["two.alt@example.org"],"campus":"Los Angeles"}'),
  ('corrections', '{"email":"rm@example.org","emails_secondary":["rm.home@example.org"],"slack":"URM","remove":true}'),
  ('corrections', '{"name":"Fine Person","email":"fine@example.org","slack":"UFINE","campus":"Los Angeles"}'),
  ('slack', '{"slack":"UKEEP","email":"keep@example.org","name":"Keep Person"}'),
  ('slack', '{"slack":"URM","email":"rm.work@example.org","name":"Removed Person"}'),
  ('slack', '{"slack":"UP","email":"x@example.org","name":"Row P"}'),
  ('slack', '{"slack":"UNEW","email":"new@example.org","name":"New Person"}');

\ir ../seed/20261125_staff_directory_seed.sql

do $$ declare n int; r record; begin
  -- Finding 4: the run completed (we got here) and nothing was lost.
  if not exists (select 1 from staff_directory where full_name = 'Fine Person') then
    raise exception 'finding 4: the seed did not get past the clash — Fine Person missing';
  end if;
  if not exists (select 1 from staff_directory where full_name = 'New Person' and archived_at is null) then
    raise exception 'a new Slack member was not added';
  end if;
  select * into r from staff_directory where slack_user_id = 'UTWO2';
  if r.email is distinct from 'two.alt@example.org' or r.archived_at is not null then
    raise exception 'finding 4: an admin-edited row lost its own email: %', row_to_json(r);
  end if;
  if r.needs_review is null then raise exception 'finding 4: the second admin row was not flagged'; end if;
  select * into r from staff_directory where slack_user_id = 'UTWO';
  if r.needs_review is null then raise exception 'finding 4: the kept row was not flagged'; end if;
  if r.primary_campus_id is distinct from '00000000-0000-0000-0000-0000000000a1' then
    raise exception 'finding 4: the correction was not applied to the kept row (its keys clashed)';
  end if;
  select * into r from staff_directory where slack_user_id = 'UP';
  if 'x@example.org' = any(r.emails_secondary) then raise exception 'finding 4: Slack merged an email another row owns'; end if;
  if r.needs_review is null then raise exception 'finding 4: the Slack clash was not flagged'; end if;

  -- Finding 2: slack_people does not bring back an account users.list dropped.
  if exists (select 1 from staff_directory where slack_user_id = 'UGONE' or email = 'gone@example.org') then
    raise exception 'finding 2: a deactivated account came back from slack_people';
  end if;
  if exists (select 1 from pending_invites where email = 'gone@example.org') then
    raise exception 'finding 2: a deactivated account got an invite';
  end if;

  -- Finding 3: a removal matches by Slack id and by secondary email, in every source.
  select count(*) into n from staff_directory
   where archived_at is null and (slack_user_id = 'URM' or email in ('rm@example.org','rm.home@example.org','rm.work@example.org'));
  if n > 0 then raise exception 'finding 3: % live row(s) for a removed person', n; end if;
  if not exists (select 1 from staff_directory where slack_user_id = 'URM' and archived_at is not null) then
    raise exception 'finding 3: the existing row for a removed person was not archived';
  end if;
  select count(*) into n from pending_invites where email in ('rm@example.org','rm.work@example.org');
  if n > 0 then raise exception 'finding 3: a removed person got a new invite'; end if;
end $$;

-- And a second run changes nothing it should not.
\ir ../seed/20261125_staff_directory_seed.sql
do $$ begin
  if (select count(*) from staff_directory where archived_at is null and (slack_user_id = 'URM' or email like 'rm%')) > 0 then
    raise exception 'a re-run revived a removed person';
  end if;
end $$;

select 'all staff directory seed checks passed' as result;
