#!/usr/bin/env python3
"""Turn the LOCAL staff-directory corrections file into SQL that loads it into
staff_directory_staging, printed to stdout. Nothing is written anywhere else.

The corrections file holds people's names and personal emails, so it never goes
into git, and neither does this script's output. Run it at apply time:

    python3 scripts/directory_corrections_sql.py corrections.json > /tmp/load.sql
    psql "$DB_URL" -f /tmp/load.sql            # default: psql \\set + :'json'
    # or, for the Supabase SQL editor (no psql variables):
    python3 scripts/directory_corrections_sql.py --inline corrections.json

The file is {"people": [ {...}, ... ]} (or a bare list). Each object goes in as
one jsonb row, unchanged; supabase/seed/20261125_staff_directory_seed.sql reads
the keys it knows (name, slack, merge_slack, email, emails_secondary, nicknames,
campus, location, oversees, oversees_location, ministries, title, role, remove,
_note) and reports anything it cannot place in needs_review.

Loading replaces the previous corrections load (a DELETE of source='corrections'
staging rows), so running it twice does not double anybody.
"""
import json, secrets, sys

KNOWN = {"name", "slack", "merge_slack", "email", "emails_secondary", "nicknames",
         "campus", "location", "oversees", "oversees_location", "ministries",
         "title", "role", "remove", "merge_profile_of", "_note", "_access"}


def main(argv):
    inline = "--inline" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if len(paths) != 1:
        sys.exit(__doc__)
    data = json.load(open(paths[0], encoding="utf-8"))
    people = data["people"] if isinstance(data, dict) else data
    if not isinstance(people, list):
        sys.exit("expected a list of people (or {'people': [...]})")

    problems = []
    for i, p in enumerate(people):
        if not isinstance(p, dict):
            problems.append(f"row {i}: not an object")
            continue
        if not (p.get("email") or p.get("slack")):
            problems.append(f"row {i}: needs an email or a slack id")
        extra = set(p) - KNOWN
        if extra:
            print(f"-- note: row {i} has keys the seed does not read: {sorted(extra)}", file=sys.stderr)
    if problems:
        sys.exit("\n".join(problems))

    payload = json.dumps(people, ensure_ascii=False)
    removed = sum(1 for p in people if p.get("remove"))
    print(f"-- {len(people)} correction rows ({removed} marked remove). Generated, do not commit.")
    print("begin;")
    print("delete from public.staff_directory_staging where source = 'corrections';")
    if inline:
        tag = "j" + secrets.token_hex(6)
        while f"${tag}$" in payload:
            tag = "j" + secrets.token_hex(6)
        print("insert into public.staff_directory_staging (source, payload)")
        print(f"select 'corrections', x from jsonb_array_elements(${tag}${payload}${tag}$::jsonb) x;")
    else:
        quoted = payload.replace("'", "''")
        print(f"\\set json '{quoted}'")
        print("insert into public.staff_directory_staging (source, payload)")
        print("select 'corrections', x from jsonb_array_elements(:'json'::jsonb) x;")
    print("commit;")


if __name__ == "__main__":
    main(sys.argv[1:])
