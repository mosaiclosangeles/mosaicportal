-- Minimal stand-ins for what the staff-directory migration expects from the
-- Mosaic Metrics project, so it can be applied to a THROWAWAY local Postgres:
--
--   createdb sd_test
--   psql -d sd_test -v ON_ERROR_STOP=1 \
--     -f supabase/tests/staff_directory_stubs.sql \
--     -f supabase/migrations/20261125_staff_directory.sql \
--     -f supabase/tests/staff_directory_test.sql
--
-- Never run this against a Supabase project: it creates an auth schema.
-- auth.uid() reads the GUC test.uid, so a test can act as a person.
do $r$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
end $r$;
create schema if not exists auth;
grant usage on schema auth to authenticated;
create table auth.users (id uuid primary key, email text, last_sign_in_at timestamptz, created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create table public.campuses (id uuid primary key, name text, slug text, active boolean default true, parent_campus_id uuid);
create table public.campus_locations (id uuid primary key, campus_id uuid references public.campuses(id), location text, active boolean default true);
create table public.profiles (id uuid primary key references auth.users(id), full_name text, display_name text, role text,
  campus_id uuid, campus_ids uuid[], home_campus_id uuid, archived_at timestamptz);
create table public.pending_invites (id uuid primary key default gen_random_uuid(), email text unique, name text,
  role text check (role in ('admin','staff','leader','volunteer')), campus_id uuid references public.campuses(id), created_at timestamptz default now());
create table public.slack_people (slack_user_id text primary key, email text, real_name text, title text, updated_at timestamptz, profile_id uuid);
create table public.reminder_routing (id uuid primary key default gen_random_uuid(), group_label text, campus_id uuid,
  owner_name text, slack_user_id text, profile_id uuid, covers text, active boolean default true, sort_order int default 0);
create function public.is_admin() returns boolean language sql stable security definer set search_path to 'public' as
  $$ select exists (select 1 from profiles where id = auth.uid() and role = 'admin') $$;
grant usage on schema public to authenticated;
grant select on public.profiles, public.campuses, public.campus_locations to authenticated;
