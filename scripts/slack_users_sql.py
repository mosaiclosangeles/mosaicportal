#!/usr/bin/env python3
"""Read every member of the Mosaic Slack workspace (users.list) and print SQL
that loads them into staff_directory_staging (source 'slack'), to stdout.

SQL cannot call Slack, so this is how "everyone in Slack" reaches the seed.

    SLACK_BOT_TOKEN=xoxb-... python3 scripts/slack_users_sql.py \\
        --corrections corrections.json > /tmp/slack.sql
    psql "$DB_URL" -f /tmp/slack.sql           # or --inline for the SQL editor

The token needs users:read and users:read.email (without the second, Slack
returns no emails and people can only be matched by Slack id).

Skipped: bots and apps, Slackbot, deactivated accounts, and guests
(single- and multi-channel) — unless a guest's Slack id or email is in the
corrections file, which is how somebody on staff with a guest account is kept.
The output carries people's names and emails: do not commit it.
"""
import json, os, secrets, sys, time, urllib.parse, urllib.request

API = "https://slack.com/api/users.list"


def fetch_all(token):
    members, cursor = [], ""
    while True:
        q = urllib.parse.urlencode({"limit": 200, **({"cursor": cursor} if cursor else {})})
        req = urllib.request.Request(f"{API}?{q}", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.load(r)
        if not body.get("ok"):
            if body.get("error") == "ratelimited":
                time.sleep(5)
                continue
            sys.exit(f"users.list failed: {body.get('error')}")
        members += body.get("members", [])
        cursor = (body.get("response_metadata") or {}).get("next_cursor") or ""
        if not cursor:
            return members


def corrections_keys(path):
    if not path:
        return set(), set()
    data = json.load(open(path, encoding="utf-8"))
    people = data["people"] if isinstance(data, dict) else data
    ids, emails = set(), set()
    for p in people:
        if p.get("remove"):
            continue
        ids.update(x for x in [p.get("slack"), *(p.get("merge_slack") or [])] if x)
        emails.update(x.lower() for x in [p.get("email"), *(p.get("emails_secondary") or [])] if x)
    return ids, emails


def main(argv):
    inline = "--inline" in argv
    corr = argv[argv.index("--corrections") + 1] if "--corrections" in argv else None
    token = os.environ.get("SLACK_BOT_TOKEN")
    if not token:
        sys.exit("Set SLACK_BOT_TOKEN (a bot token with users:read and users:read.email).")
    keep_ids, keep_emails = corrections_keys(corr)

    rows, skipped = [], {"bot": 0, "deleted": 0, "guest": 0}
    for m in fetch_all(token):
        prof = m.get("profile") or {}
        email = (prof.get("email") or "").lower() or None
        if m.get("is_bot") or m.get("is_app_user") or m.get("id") == "USLACKBOT":
            skipped["bot"] += 1
            continue
        if m.get("deleted"):
            skipped["deleted"] += 1
            continue
        guest = bool(m.get("is_restricted") or m.get("is_ultra_restricted"))
        if guest and m["id"] not in keep_ids and email not in keep_emails:
            skipped["guest"] += 1
            continue
        rows.append({
            "slack": m["id"],
            "name": prof.get("real_name") or m.get("real_name") or prof.get("display_name") or m.get("name"),
            "display_name": prof.get("display_name") or None,
            "email": email,
            "title": prof.get("title") or None,
            "tz": m.get("tz"),
            "is_guest": guest,
        })

    print(f"-- {len(rows)} Slack members; skipped {skipped}. Generated, do not commit.", file=sys.stderr)
    payload = json.dumps(rows, ensure_ascii=False)
    print(f"-- {len(rows)} Slack members. Generated, do not commit.")
    print("begin;")
    print("delete from public.staff_directory_staging where source = 'slack';")
    if inline:
        tag = "j" + secrets.token_hex(6)
        print("insert into public.staff_directory_staging (source, payload)")
        print(f"select 'slack', x from jsonb_array_elements(${tag}${payload}${tag}$::jsonb) x;")
    else:
        print("\\set json '" + payload.replace("'", "''") + "'")
        print("insert into public.staff_directory_staging (source, payload)")
        print("select 'slack', x from jsonb_array_elements(:'json'::jsonb) x;")
    print("commit;")


if __name__ == "__main__":
    main(sys.argv[1:])
