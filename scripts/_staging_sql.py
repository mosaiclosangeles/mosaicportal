"""Shared by the two loaders: turn a list of rows into SQL that replaces one
source's rows in staff_directory_staging. Printed, never executed here.

Default form is dollar-quoted, which psql and the Supabase SQL editor both read
as-is. `psql=True` gives the \\set + :'json' form instead. psql's quoted
meta-command arguments process backslash escapes (\\n, \\", \\digits), so every
backslash is doubled and every quote doubled — without that, a JSON string
holding \\" or \\n arrives as broken JSON (portal #12 review, finding 1).
"""
import json, secrets


def staging_sql(rows, source, psql=False, comment=""):
    payload = json.dumps(rows, ensure_ascii=False)
    out = []
    if comment:
        out.append(f"-- {comment} Generated, do not commit.")
    out += ["begin;", f"delete from public.staff_directory_staging where source = '{source}';",
            "insert into public.staff_directory_staging (source, payload)"]
    if psql:
        quoted = payload.replace("\\", "\\\\").replace("'", "''")
        out.insert(-1, f"\\set json '{quoted}'")
        out.append(f"select '{source}', x from jsonb_array_elements(:'json'::jsonb) x;")
    else:
        tag = "j" + secrets.token_hex(6)
        while f"${tag}$" in payload:
            tag = "j" + secrets.token_hex(6)
        out.append(f"select '{source}', x from jsonb_array_elements(${tag}${payload}${tag}$::jsonb) x;")
    out.append("commit;")
    return "\n".join(out) + "\n"
