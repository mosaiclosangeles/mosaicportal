#!/usr/bin/env python3
"""Tests for the two staging loaders. Made-up data only.

    python3 scripts/test_loaders.py
    STAFF_DIR_TEST_PSQL="psql -h /tmp -p 5432 -U postgres -d scratch" python3 scripts/test_loaders.py

The round-trip tests need a THROWAWAY Postgres (they create and drop a table
called staff_directory_staging there) and are skipped without one.
"""
import json, os, shlex, subprocess, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _staging_sql import staging_sql
from slack_users_sql import select_members, corrections_keys

AWKWARD = [{"name": 'Q "Quote" O\'Neil', "email": "q@example.org", "slack": "UQ",
            "_note": "line one\nline two \\ back \\n not-a-newline $j$ $$"}]
PSQL = os.environ.get("STAFF_DIR_TEST_PSQL")


@unittest.skipUnless(PSQL, "set STAFF_DIR_TEST_PSQL to a throwaway database")
class RoundTrip(unittest.TestCase):
    def run_sql(self, sql):
        r = subprocess.run(shlex.split(PSQL) + ["-v", "ON_ERROR_STOP=1", "-qAt"], input=sql,
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def setUp(self):
        self.run_sql("drop table if exists staff_directory_staging;"
                     "create table staff_directory_staging(id bigserial, source text, payload jsonb);")

    def check(self, psql):
        self.run_sql(staging_sql(AWKWARD, "corrections", psql=psql))
        got = json.loads(self.run_sql("select json_agg(payload order by id) from staff_directory_staging;"))
        self.assertEqual(got, AWKWARD)

    def test_dollar_quoted_default(self):
        self.check(False)

    def test_psql_variable_form(self):
        self.check(True)

    def test_reload_replaces(self):
        self.run_sql(staging_sql(AWKWARD, "corrections"))
        self.run_sql(staging_sql(AWKWARD, "corrections"))
        self.assertEqual(self.run_sql("select count(*) from staff_directory_staging;").strip(), "1")


def member(i, email=None, **kw):
    return dict({"id": i, "profile": {"email": email, "real_name": i}}, **kw)


class SelectMembers(unittest.TestCase):
    def test_filters(self):
        ms = [member("UOK", "ok@example.org"),
              member("UBOT", is_bot=True), member("USLACKBOT"),
              member("UGONE", "gone@example.org", deleted=True),
              member("UGUEST", "guest@example.org", is_restricted=True),
              member("UKEEPG", "kept.guest@example.org", is_ultra_restricted=True),
              member("URMID", "fine@example.org"),
              member("URMMAIL", "Second.Removed@example.org")]
        rows, skipped = select_members(ms, keep_ids={"UKEEPG"}, keep_emails=set(),
                                       rm_ids={"URMID"}, rm_emails={"second.removed@example.org"})
        self.assertEqual(sorted(r["slack"] for r in rows), ["UKEEPG", "UOK"])
        self.assertEqual(skipped, {"bot": 2, "deleted": 1, "guest": 1, "removed": 2})

    def test_corrections_keys_reads_removals(self, tmp="/tmp/_sd_corr_test.json"):
        json.dump({"people": [
            {"email": "a@example.org", "slack": "UA", "merge_slack": ["UA2"], "emails_secondary": ["A2@example.org"]},
            {"email": "gone@example.org", "slack": "UG", "emails_secondary": ["Gone2@example.org"], "remove": True}]},
            open(tmp, "w"))
        keep_ids, keep_emails, rm_ids, rm_emails = corrections_keys(tmp)
        self.assertEqual(keep_ids, {"UA", "UA2"})
        self.assertEqual(keep_emails, {"a@example.org", "a2@example.org"})
        self.assertEqual(rm_ids, {"UG"})
        self.assertEqual(rm_emails, {"gone@example.org", "gone2@example.org"})


if __name__ == "__main__":
    unittest.main(verbosity=1)
