# numbers-alert

Per-submission attendance alerts to the Slack **#numbers** channel (`G0122LM0VRB`),
driven by the Mosaic Metrics app. Companion to the "Metrics Automations x Claude"
canvas (in #metrics), which is the source of truth for all card formats.

## How it works

1. Someone enters attendance in the app → rows land in `public.services` +
   `public.attendance` (+ `public.decisions`).
2. Statement-level triggers on `attendance` and `decisions`
   (`20260802201500_numbers_alert_triggers.sql`) call `net.http_post` →
   this edge function, once per affected service.
3. The function rebuilds the **entire** card for that `(campus, date, gathering_type)`
   from the database and posts/edits it in Slack.

**One card per campus per day.** The first submission posts a card; later same-day
submissions for that campus edit the same message (no re-ping). Because the card is
always rebuilt from the DB, it is self-healing — late-added numbers or corrections
refresh it automatically.

**Concurrency.** A submission writes several rows at once, so the function can be
invoked concurrently. It claims atomically by inserting a `PENDING` row into
`numbers_alert_cards` (unique on `campus_id, alert_date`): exactly one caller wins
and posts; the rest wait for the `ts` and edit.

## Card types

All six gathering types are supported (`sunday`, `midweek`, `special`, `groups`,
`next_steps`, `online`); unknown types fall back to a Sunday-style card. The renderer
was verified byte-for-byte against the canvas (2026-07-26 Ecuador Sunday + LA Groups).

## Secrets

The Slack bot token is stored in Supabase Vault as `slack_bot_token` and read at
runtime via the `get_vault_secret` RPC (service-role only). It is never hardcoded.

## Manual / debug invocation

```bash
# Dry run — render without posting:
curl -X POST "$SUPABASE_URL/functions/v1/numbers-alert" \
  -H "Authorization: Bearer $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"dry_run":true,"campus_id":"<uuid>","date":"YYYY-MM-DD","gathering_type":"sunday"}'

# Force (re)build one card:
#   body: {"service_id":"<uuid>"}  or  {"campus_id","date","gathering_type"}
```

## Operations

- **Rotate the token:** regenerate in the Slack app (OAuth & Permissions), then
  `select vault.update_secret((select id from vault.secrets where name='slack_bot_token'), '<new xoxb->');`
- **Pause alerts:** `alter table public.attendance disable trigger numbers_alert_after_insert_attendance;`
  (and the `..._decisions` trigger). Re-enable with `enable trigger`.
- **Change channel:** update `SLACK_CHANNEL` in `index.ts` and redeploy.
