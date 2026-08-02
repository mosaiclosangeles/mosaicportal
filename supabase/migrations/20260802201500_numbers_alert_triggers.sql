-- Live triggers for the numbers-alert Slack integration.
-- pg_net queues the HTTP call and sends it asynchronously after commit, so
-- inserts are never blocked. Statement-level triggers with transition tables
-- fire once per submission (not once per row). The edge function rebuilds the
-- whole card from the DB and, via its atomic claim, guarantees one Slack post
-- per campus/day with later calls editing the same message.
create extension if not exists pg_net;

create or replace function public.fire_numbers_alert(p_service_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public, net
as $$
declare
  sid uuid;
  fn_url text := 'https://iknjgrltglwupxjtegfh.supabase.co/functions/v1/numbers-alert';
  -- anon key (publishable) satisfies the function's verify_jwt.
  auth_header text := 'Bearer <ANON_JWT>';
begin
  foreach sid in array p_service_ids loop
    if sid is not null then
      perform net.http_post(
        url := fn_url,
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', auth_header),
        body := jsonb_build_object('service_id', sid)
      );
    end if;
  end loop;
end;
$$;

create or replace function public.tg_numbers_alert_attendance()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.fire_numbers_alert(array(select distinct service_id from new_attendance));
  return null;
end;
$$;

create or replace function public.tg_numbers_alert_decisions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.fire_numbers_alert(array(select distinct service_id from new_decisions));
  return null;
end;
$$;

drop trigger if exists numbers_alert_after_insert_attendance on public.attendance;
create trigger numbers_alert_after_insert_attendance
after insert on public.attendance
referencing new table as new_attendance
for each statement execute function public.tg_numbers_alert_attendance();

drop trigger if exists numbers_alert_after_insert_decisions on public.decisions;
create trigger numbers_alert_after_insert_decisions
after insert on public.decisions
referencing new table as new_decisions
for each statement execute function public.tg_numbers_alert_decisions();
