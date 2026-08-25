-- ============================================================================
-- Mosaic Facilities — schema as applied to Supabase project
-- `Mosaic Metrics` (iknjgrltglwupxjtegfh), public schema, August 2026.
--
-- It lives in the same project as auth/profiles on purpose: RLS keys off
-- auth.uid() and the portal's can(app, perm) helper, and neither crosses
-- projects. Applied as five migrations, in this order.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. facilities_core_tables
-- ---------------------------------------------------------------------------
create table if not exists public.fac_spaces (
  id                uuid primary key default gen_random_uuid(),
  campus_id         uuid not null references public.campuses(id) on delete restrict,
  name              text not null,
  building          text,
  capacity          integer,
  notes             text,
  bookable          boolean not null default true,
  requires_approval boolean not null default true,
  active            boolean not null default true,
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (campus_id, name)
);
comment on table public.fac_spaces is 'Bookable rooms/areas per campus for Mosaic Facilities.';

create table if not exists public.fac_resources (
  id            uuid primary key default gen_random_uuid(),
  key           text not null unique,
  label         text not null,
  icon          text,
  unit          text not null default 'qty' check (unit in ('qty','unit')),
  category      text not null default 'other'
                check (category in ('furniture','av','staffing','facility','media','other')),
  inventory_qty integer,
  campus_id     uuid references public.campuses(id) on delete cascade,
  active        boolean not null default true,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);
comment on column public.fac_resources.campus_id is 'null = offered at every campus.';
comment on column public.fac_resources.inventory_qty is 'null = quantity not tracked.';

create sequence if not exists public.fac_request_ref_seq start 1000;

create table if not exists public.fac_requests (
  id               uuid primary key default gen_random_uuid(),
  ref              text unique,
  request_type     text not null default 'facility_use'
                   check (request_type in ('facility_use','filming','event','maintenance')),
  title            text not null,
  purpose          text,
  status           text not null default 'submitted'
                   check (status in ('draft','submitted','in_review','approved','declined','cancelled','completed')),
  campus_id        uuid not null references public.campuses(id) on delete restrict,
  space_id         uuid references public.fac_spaces(id) on delete set null,
  requested_by     uuid references public.profiles(id) on delete set null,
  requester_name   text,
  requester_email  text,
  requester_phone  text,
  organization     text,
  is_external      boolean not null default false,
  start_at         timestamptz not null,
  end_at           timestamptz not null,
  setup_minutes    integer not null default 0 check (setup_minutes >= 0),
  teardown_minutes integer not null default 0 check (teardown_minutes >= 0),
  attendees        integer check (attendees is null or attendees >= 0),
  category         text,
  details          jsonb not null default '{}'::jsonb,
  requester_notes  text,
  internal_notes   text,
  decided_by       uuid references public.profiles(id) on delete set null,
  decided_at       timestamptz,
  decision_note    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (end_at > start_at)
);
comment on column public.fac_requests.details is
  'Type-specific answers. Filming: crew_size, equipment, drone, distribution, coi_on_file. Maintenance: severity, area.';

create index if not exists fac_requests_window_idx on public.fac_requests (space_id, start_at, end_at);
create index if not exists fac_requests_status_idx on public.fac_requests (status, start_at);
create index if not exists fac_requests_mine_idx   on public.fac_requests (requested_by, created_at desc);

create table if not exists public.fac_request_resources (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.fac_requests(id) on delete cascade,
  resource_id uuid not null references public.fac_resources(id) on delete restrict,
  qty         integer not null default 1 check (qty > 0),
  status      text not null default 'pending' check (status in ('pending','approved','declined')),
  note        text,
  created_at  timestamptz not null default now(),
  unique (request_id, resource_id)
);

create table if not exists public.fac_request_comments (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.fac_requests(id) on delete cascade,
  author_id   uuid references public.profiles(id) on delete set null,
  body        text not null,
  is_internal boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.fac_request_activity (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.fac_requests(id) on delete cascade,
  actor_id    uuid references public.profiles(id) on delete set null,
  action      text not null,
  from_status text,
  to_status   text,
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists fac_activity_request_idx on public.fac_request_activity (request_id, created_at);

create table if not exists public.fac_blackouts (
  id         uuid primary key default gen_random_uuid(),
  campus_id  uuid references public.campuses(id) on delete cascade,
  space_id   uuid references public.fac_spaces(id) on delete cascade,
  label      text not null,
  start_at   timestamptz not null,
  end_at     timestamptz not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (end_at > start_at)
);
comment on table public.fac_blackouts is 'Dates a campus or space is unavailable (holidays, construction, held for Sunday).';

-- ---------------------------------------------------------------------------
-- 2. facilities_triggers_views_functions
-- ---------------------------------------------------------------------------
-- Human-readable reference, e.g. FR-1042 / FL-1043
create or replace function public.fac_set_ref()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.ref is null then
    new.ref := case new.request_type
                 when 'filming'     then 'FL-'
                 when 'maintenance' then 'MX-'
                 when 'event'       then 'EV-'
                 else 'FR-'
               end || nextval('public.fac_request_ref_seq')::text;
  end if;
  return new;
end;
$$;

drop trigger if exists fac_requests_ref on public.fac_requests;
create trigger fac_requests_ref before insert on public.fac_requests
  for each row execute function public.fac_set_ref();

drop trigger if exists fac_requests_touch on public.fac_requests;
create trigger fac_requests_touch before update on public.fac_requests
  for each row execute function public.set_updated_at();

drop trigger if exists fac_spaces_touch on public.fac_spaces;
create trigger fac_spaces_touch before update on public.fac_spaces
  for each row execute function public.set_updated_at();

-- Log every status change so a decision is never a mystery later.
create or replace function public.fac_log_status()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.fac_request_activity (request_id, actor_id, action, to_status)
    values (new.id, auth.uid(), 'submitted', new.status);
  elsif new.status is distinct from old.status then
    insert into public.fac_request_activity (request_id, actor_id, action, from_status, to_status, detail)
    values (new.id, auth.uid(), 'status_changed', old.status, new.status,
            jsonb_build_object('decision_note', new.decision_note));
  end if;
  return new;
end;
$$;

drop trigger if exists fac_requests_log on public.fac_requests;
create trigger fac_requests_log after insert or update on public.fac_requests
  for each row execute function public.fac_log_status();

-- The window a request actually holds the room for, setup/teardown included.
create or replace function public.fac_block_start(r public.fac_requests)
returns timestamptz language sql immutable set search_path to 'public' as $$
  select r.start_at - make_interval(mins => r.setup_minutes);
$$;

create or replace function public.fac_block_end(r public.fac_requests)
returns timestamptz language sql immutable set search_path to 'public' as $$
  select r.end_at + make_interval(mins => r.teardown_minutes);
$$;

-- Does this window collide with something already approved in the same space?
create or replace function public.fac_conflicts(
  p_space_id uuid, p_start timestamptz, p_end timestamptz, p_exclude uuid default null)
returns table(id uuid, ref text, title text, start_at timestamptz, end_at timestamptz, status text)
language sql stable security definer set search_path to 'public' as $$
  select r.id, r.ref, r.title, r.start_at, r.end_at, r.status
  from public.fac_requests r
  where r.space_id = p_space_id
    and r.status in ('approved','in_review','submitted')
    and (p_exclude is null or r.id <> p_exclude)
    and tstzrange(r.start_at - make_interval(mins => r.setup_minutes),
                  r.end_at   + make_interval(mins => r.teardown_minutes), '[)')
        && tstzrange(p_start, p_end, '[)')
  order by r.start_at;
$$;

-- One read for the dashboard: request + campus + space + who asked.
create or replace view public.v_fac_requests
with (security_invoker = true) as
select
  r.*,
  c.name  as campus_name,
  s.name  as space_name,
  s.building as space_building,
  s.capacity as space_capacity,
  coalesce(p.display_name, p.full_name, r.requester_name) as requested_by_name,
  dp.display_name as decided_by_name,
  r.start_at - make_interval(mins => r.setup_minutes) as block_start,
  r.end_at   + make_interval(mins => r.teardown_minutes) as block_end,
  (select count(*) from public.fac_request_resources rr where rr.request_id = r.id) as resource_count,
  (select count(*) from public.fac_request_resources rr
    where rr.request_id = r.id and rr.status = 'pending') as resource_pending_count
from public.fac_requests r
left join public.campuses c  on c.id = r.campus_id
left join public.fac_spaces s on s.id = r.space_id
left join public.profiles p  on p.id = r.requested_by
left join public.profiles dp on dp.id = r.decided_by;

-- ---------------------------------------------------------------------------
-- 3. facilities_rls_and_app_permissions
-- ---------------------------------------------------------------------------
-- Register Facilities in the portal's app/permission model so admins manage
-- access from the same Admin -> Roles & permissions screen as everything else.
insert into public.apps (key, name) values ('facilities','Facilities')
  on conflict (key) do nothing;

insert into public.app_permissions (app_key, perm_key, label, sort_order) values
  ('facilities','view',           'View',                 1),
  ('facilities','submit_request', 'Submit requests',      2),
  ('facilities','view_all',       'View all requests',    3),
  ('facilities','approve',        'Approve/decline',      4),
  ('facilities','manage_spaces',  'Manage spaces & resources', 5),
  ('facilities','notifications',  'Notifications',        6),
  ('facilities','customize',      'Customize App',        7)
on conflict (app_key, perm_key) do update set label = excluded.label, sort_order = excluded.sort_order;

insert into public.role_app_defaults (role, app_key, perm_key, granted) values
  ('admin','facilities','view',true),
  ('admin','facilities','submit_request',true),
  ('admin','facilities','view_all',true),
  ('admin','facilities','approve',true),
  ('admin','facilities','manage_spaces',true),
  ('admin','facilities','notifications',true),
  ('admin','facilities','customize',true),
  ('staff','facilities','view',true),
  ('staff','facilities','submit_request',true),
  ('staff','facilities','view_all',true),
  ('staff','facilities','approve',false),
  ('staff','facilities','manage_spaces',false),
  ('staff','facilities','notifications',true),
  ('staff','facilities','customize',false),
  ('leader','facilities','view',true),
  ('leader','facilities','submit_request',true),
  ('leader','facilities','view_all',false),
  ('leader','facilities','approve',false),
  ('leader','facilities','manage_spaces',false),
  ('leader','facilities','notifications',false),
  ('leader','facilities','customize',false),
  ('volunteer','facilities','view',true),
  ('volunteer','facilities','submit_request',true),
  ('volunteer','facilities','view_all',false),
  ('volunteer','facilities','approve',false),
  ('volunteer','facilities','manage_spaces',false),
  ('volunteer','facilities','notifications',false),
  ('volunteer','facilities','customize',false)
on conflict (role, app_key, perm_key) do update set granted = excluded.granted;

alter table public.fac_spaces            enable row level security;
alter table public.fac_resources         enable row level security;
alter table public.fac_requests          enable row level security;
alter table public.fac_request_resources enable row level security;
alter table public.fac_request_comments  enable row level security;
alter table public.fac_request_activity  enable row level security;
alter table public.fac_blackouts         enable row level security;

-- Catalog: anyone signed in reads it; only manage_spaces changes it.
drop policy if exists fac_spaces_read on public.fac_spaces;
create policy fac_spaces_read on public.fac_spaces
  for select to authenticated using (true);
drop policy if exists fac_spaces_write on public.fac_spaces;
create policy fac_spaces_write on public.fac_spaces
  for all to authenticated
  using (public.can('facilities','manage_spaces')) with check (public.can('facilities','manage_spaces'));

drop policy if exists fac_resources_read on public.fac_resources;
create policy fac_resources_read on public.fac_resources
  for select to authenticated using (true);
drop policy if exists fac_resources_write on public.fac_resources;
create policy fac_resources_write on public.fac_resources
  for all to authenticated
  using (public.can('facilities','manage_spaces')) with check (public.can('facilities','manage_spaces'));

drop policy if exists fac_blackouts_read on public.fac_blackouts;
create policy fac_blackouts_read on public.fac_blackouts
  for select to authenticated using (true);
drop policy if exists fac_blackouts_write on public.fac_blackouts;
create policy fac_blackouts_write on public.fac_blackouts
  for all to authenticated
  using (public.can('facilities','manage_spaces')) with check (public.can('facilities','manage_spaces'));

-- Requests: you always see your own; view_all sees the rest.
drop policy if exists fac_requests_read on public.fac_requests;
create policy fac_requests_read on public.fac_requests
  for select to authenticated
  using (requested_by = auth.uid() or public.can('facilities','view_all'));

drop policy if exists fac_requests_insert on public.fac_requests;
create policy fac_requests_insert on public.fac_requests
  for insert to authenticated
  with check (requested_by = auth.uid() and public.can('facilities','submit_request'));

-- Requesters may edit their own only while it is still open for edits.
drop policy if exists fac_requests_update_own on public.fac_requests;
create policy fac_requests_update_own on public.fac_requests
  for update to authenticated
  using (requested_by = auth.uid() and status in ('draft','submitted'))
  with check (requested_by = auth.uid() and status in ('draft','submitted','cancelled'));

drop policy if exists fac_requests_update_approver on public.fac_requests;
create policy fac_requests_update_approver on public.fac_requests
  for update to authenticated
  using (public.can('facilities','approve')) with check (public.can('facilities','approve'));

drop policy if exists fac_requests_delete on public.fac_requests;
create policy fac_requests_delete on public.fac_requests
  for delete to authenticated using (public.is_admin());

-- Line items follow their parent request.
drop policy if exists fac_rr_read on public.fac_request_resources;
create policy fac_rr_read on public.fac_request_resources
  for select to authenticated using (exists (
    select 1 from public.fac_requests r where r.id = request_id
      and (r.requested_by = auth.uid() or public.can('facilities','view_all'))));

drop policy if exists fac_rr_write_own on public.fac_request_resources;
create policy fac_rr_write_own on public.fac_request_resources
  for all to authenticated
  using (exists (select 1 from public.fac_requests r where r.id = request_id
                  and r.requested_by = auth.uid() and r.status in ('draft','submitted')))
  with check (exists (select 1 from public.fac_requests r where r.id = request_id
                  and r.requested_by = auth.uid() and r.status in ('draft','submitted')));

drop policy if exists fac_rr_write_approver on public.fac_request_resources;
create policy fac_rr_write_approver on public.fac_request_resources
  for all to authenticated
  using (public.can('facilities','approve')) with check (public.can('facilities','approve'));

-- Comments: internal notes stay with the facilities team.
drop policy if exists fac_comments_read on public.fac_request_comments;
create policy fac_comments_read on public.fac_request_comments
  for select to authenticated using (
    exists (select 1 from public.fac_requests r where r.id = request_id
             and (r.requested_by = auth.uid() or public.can('facilities','view_all')))
    and (not is_internal or public.can('facilities','approve')));

drop policy if exists fac_comments_insert on public.fac_request_comments;
create policy fac_comments_insert on public.fac_request_comments
  for insert to authenticated with check (
    author_id = auth.uid()
    and (not is_internal or public.can('facilities','approve'))
    and exists (select 1 from public.fac_requests r where r.id = request_id
                 and (r.requested_by = auth.uid() or public.can('facilities','view_all'))));

drop policy if exists fac_activity_read on public.fac_request_activity;
create policy fac_activity_read on public.fac_request_activity
  for select to authenticated using (exists (
    select 1 from public.fac_requests r where r.id = request_id
      and (r.requested_by = auth.uid() or public.can('facilities','view_all'))));

-- ---------------------------------------------------------------------------
-- 4. facilities_seed_catalog
-- Starter catalog. Spaces are edit-in-app; these are a first pass for LA so the
-- dashboard is usable on day one, not a claim about the real room list.
-- ---------------------------------------------------------------------------
insert into public.fac_resources (key, label, icon, unit, category, inventory_qty, sort_order) values
  ('chairs',      'Chairs',              '🪑', 'qty',  'furniture', 400,  10),
  ('tables',      'Tables',              '🪵', 'qty',  'furniture', 40,   20),
  ('stanchions',  'Stanchions',          '🚧', 'qty',  'furniture', 20,   30),
  ('projector',   'Projector & screen',  '📽',  'unit', 'av',        null, 40),
  ('av',          'AV system / sound',   '🔊', 'unit', 'av',        null, 50),
  ('mics',        'Microphones',         '🎤', 'qty',  'av',        12,   60),
  ('livestream',  'Livestream setup',    '📡', 'unit', 'av',        null, 70),
  ('lighting',    'Stage lighting',      '💡', 'unit', 'av',        null, 80),
  ('piano',       'Grand piano',         '🎹', 'unit', 'av',        null, 90),
  ('drums',       'Drum kit',            '🥁', 'unit', 'av',        null, 100),
  ('kitchen',     'Catering kitchen',    '🍽',  'unit', 'facility',  null, 110),
  ('parking',     'Parking lot',         '🅿️', 'unit', 'facility',  null, 120),
  ('wifi',        'Guest wifi access',   '📶', 'unit', 'facility',  null, 130),
  ('security',    'Security personnel',  '🛡',  'qty',  'staffing',  null, 140),
  ('custodial',   'Custodial staff',     '🧹', 'qty',  'staffing',  null, 150),
  ('av_tech',     'AV technician',       '🎛',  'qty',  'staffing',  null, 160),
  ('host',        'Host / greeter',      '🙋', 'qty',  'staffing',  null, 170),
  ('power',       'Power drops / genny', '🔌', 'qty',  'media',     null, 180),
  ('greenroom',   'Green room',          '🛋',  'unit', 'media',     null, 190),
  ('signage',     'Wayfinding signage',  '🪧', 'unit', 'other',     null, 200)
on conflict (key) do nothing;

insert into public.fac_spaces (campus_id, name, building, capacity, bookable, sort_order)
select c.id, v.name, v.building, v.capacity, true, v.sort_order
from public.campuses c
cross join (values
  ('Auditorium',   'Main building', 800, 10),
  ('Balcony',      'Main building', 200, 20),
  ('Lobby',        'Main building', 150, 30),
  ('Green room',   'Main building',  12, 40),
  ('Classroom A',  'Main building',  40, 50),
  ('Classroom B',  'Main building',  40, 60),
  ('Kids rooms',   'Main building', 120, 70),
  ('Courtyard',    'Outdoor',       200, 80),
  ('Parking lot',  'Outdoor',       null, 90)
) as v(name, building, capacity, sort_order)
where c.name = 'Los Angeles' and c.active
on conflict (campus_id, name) do nothing;

-- ---------------------------------------------------------------------------
-- 5. facilities_function_hardening
-- Trigger functions and the conflict lookup are not public API.
-- ---------------------------------------------------------------------------
revoke execute on function public.fac_log_status() from anon, authenticated;
revoke execute on function public.fac_set_ref()    from anon, authenticated;
revoke execute on function public.fac_conflicts(uuid, timestamptz, timestamptz, uuid) from anon;
