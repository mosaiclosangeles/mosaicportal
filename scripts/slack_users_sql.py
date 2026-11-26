#!/usr/bin/env python3
"""Read every member of the Mosaic Slack workspace (users.list) and print SQL
that loads them into staff_directory_staging (source 'slack'), to stdout.

SQL cannot call Slack, so this is how "everyone in Slack" reaches the seed.

    SLACK_BOT_TOKEN=xoxb-... python3 scripts/slack_users_sql.py \\
        --corrections corrections.json > /tmp/slack.sql
    psql "$DB_URL" -f /tmp/slack.sql           # or paste into the SQL editor; --psql for the \\set form

The token needs users:read and users:read.email (without the second, Slack
returns no emails and people can only be matched by Slack id).

Skipped: bots and apps, Slackbot, deactivated accounts, guests (single- and
multi-channel) unless their Slack id or email is in the corrections file, and
anyone the corrections mark remove:true — by Slack id or by any email.
The output carries people's names and emails: do not commit it.
"""
import json, os, sys, time, urllib.parse, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _staging_sql import staging_sql

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
    """(kept ids, kept emails, removed ids, removed emails) from the corrections file."""
    keep_ids, keep_emails, rm_ids, rm_emails = set(), set(), set(), set()
    if not path:
        return keep_ids, keep_emails, rm_ids, rm_emails
    data = json.load(open(path, encoding="utf-8"))
    people = data["people"] if isinstance(data, dict) else data
    for p in people:
        ids = {x for x in [p.get("slack"), *(p.get("merge_slack") or [])] if x}
        emails = {x.lower() for x in [p.get("email"), *(p.get("emails_secondary") or [])] if x}
        if p.get("remove"):
            rm_ids |= ids
            rm_emails |= emails
        else:
            keep_ids |= ids
            keep_emails |= emails
    return keep_ids, keep_emails, rm_ids, rm_emails


def select_members(members, keep_ids=(), keep_emails=(), rm_ids=(), rm_emails=()):
    """The users.list members that belong in the directory, as staging rows,
    and a count of what was skipped and why. Pure, so it is testable offline."""
    rows, skipped = [], {"bot": 0, "deleted": 0, "guest": 0, "removed": 0}
    for m in members:
        prof = m.get("profile") or {}
        email = (prof.get("email") or "").lower() or None
        if m.get("is_bot") or m.get("is_app_user") or m.get("id") == "USLACKBOT":
            skipped["bot"] += 1
            continue
        if m.get("deleted"):
            skipped["deleted"] += 1
            continue
        if m.get("id") in rm_ids or (email and email in rm_emails):
            skipped["removed"] += 1
            continue
        guest = bool(m.get("is_restricted") or m.get("is_ultra_restricted"))
        if guest and m.get("id") not in keep_ids and email not in keep_emails:
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
    return rows, skipped


def main(argv):
    use_psql = "--psql" in argv
    corr = argv[argv.index("--corrections") + 1] if "--corrections" in argv else None
    token = os.environ.get("SLACK_BOT_TOKEN")
    if not token:
        sys.exit("Set SLACK_BOT_TOKEN (a bot token with users:read and users:read.email).")
    rows, skipped = select_members(fetch_all(token), *corrections_keys(corr))
    print(f"-- {len(rows)} Slack members; skipped {skipped}.", file=sys.stderr)
    sys.stdout.write(staging_sql(rows, "slack", psql=use_psql, comment=f"{len(rows)} Slack members."))

if __name__ == "__main__":
    main(sys.argv[1:])
