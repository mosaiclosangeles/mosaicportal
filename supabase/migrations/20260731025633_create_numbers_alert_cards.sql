create table if not exists public.numbers_alert_cards (
  id bigint generated always as identity primary key,
  campus_id uuid not null references public.campuses(id),
  alert_date date not null,
  slack_channel text not null,
  slack_message_ts text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campus_id, alert_date)
);

comment on table public.numbers_alert_cards is
  'Tracks the Slack #numbers alert card posted per campus per service date, so same-day resubmissions edit the existing message (via slack_message_ts) instead of posting a new one.';

alter table public.numbers_alert_cards enable row level security;
