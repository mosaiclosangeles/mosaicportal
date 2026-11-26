-- Behaviour checks for the staff-directory migration, with made-up people.
-- See staff_directory_stubs.sql for how to run it (throwaway Postgres only).
-- Every check raises on failure; the last line prints "all staff directory checks passed".
\set ON_ERROR_STOP 1

insert into campuses (id, name, slug) values
  ('00000000-0000-0000-0000-0000000000a1','Los Angeles','la'),
  ('00000000-0000-0000-0000-0000000000a2','Mexico','mexico'),
  ('00000000-0000-0000-0000-0000000000a3','New York City','nyc');
insert into campus_locations (id, campus_id, location) values
  ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a2','Polanco'),
  ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000a2','Roma Condesa');
insert into auth.users (id, email, last_sign_in_at) values
  ('00000000-0000-0000-0000-000000000001','admin@example.org', now()),
  ('00000000-0000-0000-0000-000000000002','staff.one@example.org', now()),
  ('00000000-0000-0000-0000-000000000003','staff.two@example.org', null);
insert into profiles (id, full_name, role) values
  ('00000000-0000-0000-0000-000000000001','Admin Person','admin'),
  ('00000000-0000-0000-0000-000000000002','Staff One','staff'),
  ('00000000-0000-0000-0000-000000000003','Staff Two','staff');

-- links by a SECONDARY email; normalises case; rejects nothing valid
insert into staff_directory (slack_user_id, slack_ids_secondary, email, emails_secondary, full_name, nicknames,
                             primary_campus_id, location_id, ministries, title, source)
values ('UONE','{UONE2}','one@example.org','{STAFF.ONE@example.org}','Staff One','{S1}',
        '00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000b1','{Kids,Worship}','Lead','corrections'),
       ('UTWO','{}','two@example.org','{two.personal@example.org}','Staff Two','{}','00000000-0000-0000-0000-0000000000a1',null,'{}',null,'slack'),
       ('UNEW','{}','new@example.org','{}','New Person','{}','00000000-0000-0000-0000-0000000000a3',null,'{}',null,'slack');

do $$ declare r record; begin
  select * into r from staff_directory where slack_user_id = 'UONE';
  if r.profile_id is distinct from '00000000-0000-0000-0000-000000000002' then raise exception 'secondary email did not link the profile'; end if;
  if r.emails_secondary <> '{staff.one@example.org}' then raise exception 'secondary email not lower-cased: %', r.emails_secondary; end if;
end $$;

-- the vocabulary is enforced, and an admin can extend it without a migration
do $$ begin
  begin
    update staff_directory set ministries = '{Kids,Underwater Basketweaving}' where slack_user_id = 'UTWO';
    raise exception 'an unknown ministry was accepted';
  exception when check_violation then null; end;
end $$;
insert into staff_ministries (name) values ('Underwater Basketweaving');
update staff_directory set ministries = '{Underwater Basketweaving}' where slack_user_id = 'UTWO';

-- a location must sit inside the primary campus
do $$ begin
  begin
    update staff_directory set location_id = '00000000-0000-0000-0000-0000000000b2' where slack_user_id = 'UTWO';
    raise exception 'a Mexico location was accepted on an LA person';
  exception when check_violation then null; end;
end $$;

-- one person, one row: an email or Slack id may not appear on two rows
do $$ begin
  begin
    update staff_directory set emails_secondary = '{one@example.org}' where slack_user_id = 'UTWO';
    raise exception 'an email already on another row was accepted';
  exception when unique_violation then null; end;
  begin
    update staff_directory set slack_ids_secondary = '{UONE2}' where slack_user_id = 'UTWO';
    raise exception 'a Slack id already on another row was accepted';
  exception when unique_violation then null; end;
end $$;

-- a person edits their own campus and ministries — and nothing else
set role authenticated;
set test.uid = '00000000-0000-0000-0000-000000000002';
update staff_directory set primary_campus_id = '00000000-0000-0000-0000-0000000000a1', ministries = '{Production}',
       title = 'Self-promoted', nicknames = '{X}', emails_secondary = '{}', oversees_all = true, needs_review = 'cleared',
       campus_ids_overseen = '{00000000-0000-0000-0000-0000000000a3}'
 where slack_user_id = 'UONE';
-- and cannot touch anybody else's row
update staff_directory set ministries = '{Kids}' where slack_user_id = 'UTWO';
-- reads colleagues without their secondary emails
do $$ declare n int; m text[]; begin
  select count(*) into n from staff_directory;  -- raw table: own row only
  if n <> 1 then raise exception 'a non-admin read % raw rows, expected only their own', n; end if;
  select emails_secondary into m from staff_directory_list() where email = 'two@example.org';
  if m is distinct from '{}'::text[] then raise exception 'a colleague''s secondary emails reached a non-admin: %', m; end if;
  select emails_secondary into m from staff_directory_list() where email = 'one@example.org';
  if m is distinct from '{staff.one@example.org}'::text[] then raise exception 'own secondary emails hidden from self'; end if;
end $$;
reset role;
reset test.uid;

do $$ declare r record; begin
  select * into r from staff_directory where slack_user_id = 'UONE';
  if r.primary_campus_id <> '00000000-0000-0000-0000-0000000000a1' then raise exception 'own campus change did not land'; end if;
  if r.ministries <> '{Production}' then raise exception 'own ministries change did not land'; end if;
  if r.title <> 'Lead' or r.nicknames <> '{S1}' or r.emails_secondary <> '{staff.one@example.org}'
     or r.oversees_all or r.needs_review is not null or r.campus_ids_overseen <> '{}' then
    raise exception 'a non-admin changed a privileged field: %', row_to_json(r);
  end if;
  if r.location_id is not null then raise exception 'moving campus kept a location from the old campus'; end if;
  if r.source <> 'self' then raise exception 'self edit not marked'; end if;
  select * into r from staff_directory where slack_user_id = 'UTWO';
  if r.ministries <> '{Underwater Basketweaving}' then raise exception 'a non-admin changed somebody else''s row'; end if;
end $$;

-- who_is: primary Slack id, secondary Slack id, any email; carries the v2 fields
do $$ declare r record; begin
  select * into r from who_is('UONE2');
  if r.name is distinct from 'Staff One' or r.matched_by is distinct from 'slack_user_id' then raise exception 'secondary Slack id not matched'; end if;
  select * into r from who_is(null, 'STAFF.ONE@example.org');
  if r.name is distinct from 'Staff One' or r.matched_by is distinct from 'email' then raise exception 'secondary email not matched'; end if;
  if r.ministries is distinct from '{Production}'::text[] or r.campus is distinct from 'Los Angeles' then raise exception 'who_is fields wrong: %', row_to_json(r); end if;
  select * into r from who_is('UNOBODY');
  if found then raise exception 'who_is invented a person'; end if;
end $$;

-- status: signed in / invite sent / invite saved / no invite
insert into pending_invites (email, name, role) values ('two@example.org','Staff Two','staff');
do $$ declare a text; b text; c text; begin
  select activation into a from staff_directory_v where email = 'one@example.org';
  select activation into b from staff_directory_v where email = 'two@example.org';
  select activation into c from staff_directory_v where email = 'new@example.org';
  if a is distinct from 'signed_in' or b is distinct from 'invite_saved' or c is distinct from 'no_invite' then raise exception 'activation wrong: % % %', a, b, c; end if;
end $$;

-- who_is is not for signed-in users
set role authenticated;
do $$ begin
  begin perform who_is('UONE'); raise exception 'authenticated may call who_is';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select 'all staff directory checks passed' as result;
