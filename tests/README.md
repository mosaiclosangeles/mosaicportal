# Driving the portal in a browser

The portal has no build step and no unit tests; what it needs is something
that clicks the rail and looks at what renders. Three files do that:

| File | Is |
|---|---|
| `portal-stub.js` | stands in for the Supabase client — auth, the tables the portal reads, `functions.invoke`, storage — and answers the planning-board REST calls with `[]` |
| `spa.py` | serves the app for **any** path on :8100, the way Cloudflare Pages does, so `/facilities` and `/calendar` boot the way they do in production rather than 404ing |
| `drive-portal.mjs` | Playwright: clicks the rail, reads the iframe src, checks the sub-menu, and reads `EVENTS` for the facility bookings |

```sh
python3 - <<'PY'
import re
s = open('../index.html').read()
open('portal.html','w').write(
    re.sub(r'<script src="https://cdn[^"]*supabase[^"]*"></script>',
           '<script src="portal-stub.js"></script>', s))
PY
python3 spa.py &          # :8100
node drive-portal.mjs
```

It exists because Facilities shipped twice in a row without being clicked
once: first the whole portal built to a preview URL nobody looked at, then the
rail button rendered the Settings page. Both would have been caught by the
first two assertions in here.
