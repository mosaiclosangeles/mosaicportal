// numbers-alert
//
// Posts a per-submission attendance card to the Slack #numbers channel whenever
// someone enters numbers in the Mosaic Metrics app. One card per campus per day:
// the first submission posts a card; later same-day submissions for that campus
// silently edit the same card (no re-ping). The card is always rebuilt from the
// database, so it is self-healing and idempotent no matter how many times the
// webhook fires while child rows are being written.
//
// Source of truth for all formats/rules: the "Metrics Automations x Claude" canvas
// (#metrics). Card layout below mirrors it exactly, translated to Slack mrkdwn:
//   ***bold+italic***  ->  *_bold+italic_*      (Slack combined)
//   *italic*           ->  _italic_
//   ---                ->  Block Kit divider block
//
// Trigger: Supabase Database Webhook on public.attendance (INSERT) — every card
// type writes at least one attendance row, so this fires once per row and the last
// fire renders the complete card. Also accepts a direct { service_id } or
// { campus_id, date, gathering_type } payload for manual runs, and { dry_run: true }
// to render without posting to Slack.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SLACK_CHANNEL = "G0122LM0VRB"; // #numbers
const SLACK_API = "https://slack.com/api";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ---------- formatting helpers ----------

// Whole-number formatting with thousands separators; null/blank -> "--".
function num(n: number | null | undefined): string {
  if (n === null || n === undefined || Number.isNaN(n)) return "--";
  return n.toLocaleString("en-US");
}

function txt(s: string | null | undefined): string {
  const v = (s ?? "").toString().trim();
  return v.length ? v : "--";
}

// bold+italic (***x*** on the canvas) -> Slack *_x_*
const bi = (s: string) => `*_${s}_*`;
// italic (*x* on the canvas) -> Slack _x_
const it = (s: string) => `_${s}_`;

const WEEKDAYS = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
];
const MONTHS = [
  "January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December",
];
const MONTHS_SHORT = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

// Parse a bare YYYY-MM-DD (no timezone math — a service date is a calendar date).
function parseDate(d: string): Date {
  const [y, m, day] = d.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, day, 12, 0, 0));
}

// "Sunday, July 26, 2026"
function longDate(d: string): string {
  const dt = parseDate(d);
  return `${WEEKDAYS[dt.getUTCDay()]}, ${MONTHS[dt.getUTCMonth()]} ${dt.getUTCDate()}, ${dt.getUTCFullYear()}`;
}

// "Sun, Jun 28 → Sat, Jul 4, 2026" — the Sun→Sat week containing d.
function weekRange(d: string): string {
  const start = parseDate(d);
  // back up to Sunday
  start.setUTCDate(start.getUTCDate() - start.getUTCDay());
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 6);
  const a = `${WEEKDAYS[start.getUTCDay()].slice(0, 3)}, ${MONTHS_SHORT[start.getUTCMonth()]} ${start.getUTCDate()}`;
  const b = `${WEEKDAYS[end.getUTCDay()].slice(0, 3)}, ${MONTHS_SHORT[end.getUTCMonth()]} ${end.getUTCDate()}, ${end.getUTCFullYear()}`;
  return `${a} → ${b}`;
}

// ---------- Slack block assembly ----------
// We build an ordered list of "lines" and "dividers", then map to Block Kit.
type Part = { kind: "text"; lines: string[] } | { kind: "divider" };

function blocksFromParts(parts: Part[]) {
  const blocks: unknown[] = [];
  for (const p of parts) {
    if (p.kind === "divider") {
      blocks.push({ type: "divider" });
    } else {
      const text = p.lines.join("\n");
      if (text.trim().length) {
        blocks.push({ type: "section", text: { type: "mrkdwn", text } });
      }
    }
  }
  return blocks;
}

// ---------- domain types ----------
interface ServiceRow {
  id: string;
  campus_id: string;
  date: string;
  service_label: string | null;
  gathering_type: string;
  speaker: string | null;
  series: string | null;
  message_title: string | null;
  event_tag: string | null;
  location: string | null;
  group_count: number | null;
  segment: string | null;
  notes: string | null;
  created_at: string;
  created_by: string | null;
}

interface Enriched extends ServiceRow {
  areas: Record<string, number>;
  decisions: Record<string, number>;
}

const TYPE_LABEL: Record<string, string> = {
  sunday: "Sunday Service",
  midweek: "Midweek",
  special: "Special Event",
  groups: "Community Groups",
  next_steps: "Next Steps",
  online: "Online Metrics",
};

// Attendance areas that roll into the headline total.
const TOTAL_AREAS = ["auditorium", "other_adults", "kids", "youth"];

function sumTotal(areas: Record<string, number>): number {
  return TOTAL_AREAS.reduce((t, k) => t + (areas[k] ?? 0), 0);
}

function salvation(decisions: Record<string, number>): number {
  return decisions["salvation"] ?? 0;
}

// Standard in-person area lines (All Call first, only when > 0).
function areaLines(
  areas: Record<string, number>,
  keys: string[],
  labels: Record<string, string>,
): string[] {
  const lines: string[] = [];
  const ac = areas["all_call"] ?? 0;
  if (ac > 0) lines.push(`All Call: ${num(ac)} (not in total)`);
  for (const k of keys) lines.push(`${labels[k]}: ${num(areas[k] ?? 0)}`);
  return lines;
}

// First non-null value of a field across the day's services (stable across rebuilds).
function firstOf(services: Enriched[], field: keyof ServiceRow): string | null {
  for (const s of services) {
    const v = s[field];
    if (v !== null && v !== undefined && `${v}`.trim().length) return `${v}`;
  }
  return null;
}

// ---------- card renderers ----------

function renderSunday(submitter: string, campus: string, services: Enriched[]): unknown[] {
  const first = services[0];
  const times = services.map((s) => txt(s.service_label)).join(" · ");

  const campusAreas: Record<string, number> = {};
  let campusDec = 0;
  for (const s of services) {
    for (const [k, v] of Object.entries(s.areas)) campusAreas[k] = (campusAreas[k] ?? 0) + v;
    campusDec += salvation(s.decisions);
  }
  const labels = { auditorium: "Auditorium", other_adults: "Other Adults", kids: "Kids", youth: "Youth" };

  const parts: Part[] = [
    { kind: "text", lines: [bi(`${submitter} has submitted Sunday Service Attendance:`)] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("🔹 OVERVIEW"), "",
      `Campus: ${txt(campus)}`,
      `Location: ${txt(first.location)}`,
      "Attendance Type: Sunday Service",
      `Date: ${longDate(first.date)}`,
      `Services: ${times}`,
    ] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("🔍 DETAILS"), "",
      `Speaker: ${txt(firstOf(services, "speaker"))}`,
      `Series: ${txt(firstOf(services, "series"))}`,
      `Message Title: ${txt(firstOf(services, "message_title"))}`,
      `Event Tag (optional): ${txt(firstOf(services, "event_tag"))}`,
    ] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("📊 CAMPUS TOTAL"), "",
      ...areaLines(campusAreas, ["auditorium", "other_adults", "kids", "youth"], labels),
      bi(`Total Attendance: ${num(sumTotal(campusAreas))}`),
      bi(`Total Decisions: ${num(campusDec)}`),
    ] },
    { kind: "divider" },
  ];

  const svcLines: string[] = [bi("📊 ATTENDANCE BY SERVICE")];
  for (const s of services) {
    svcLines.push("", bi(txt(s.service_label)));
    svcLines.push(...areaLines(s.areas, ["auditorium", "other_adults", "kids", "youth"], labels));
    svcLines.push(bi(`Total: ${num(sumTotal(s.areas))}`));
    svcLines.push(bi(`Decisions: ${num(salvation(s.decisions))}`));
  }
  parts.push({ kind: "text", lines: svcLines });
  parts.push({ kind: "text", lines: [it(`Notes: ${txt(firstOf(services, "notes"))}`)] });
  return blocksFromParts(parts);
}

// Single-gathering in-person types (midweek / special / next_steps).
function renderSingleInPerson(
  submitter: string,
  campus: string,
  services: Enriched[],
  cfg: {
    type: string;
    dateLabel: string;      // "Service Time" | "Event Time"
    details: { field: keyof ServiceRow; label: string }[] | null;
    areaOrder: string[];
    areaLabels: Record<string, string>;
    showDecisions: boolean;
    overviewEventTag?: boolean; // next_steps shows Event Tag in Overview
  },
): unknown[] {
  const first = services[0];
  const areas: Record<string, number> = {};
  let dec = 0;
  for (const s of services) {
    for (const [k, v] of Object.entries(s.areas)) areas[k] = (areas[k] ?? 0) + v;
    dec += salvation(s.decisions);
  }

  const overview = [
    bi("🔹 OVERVIEW"), "",
    `Campus: ${txt(campus)}`,
    `Location: ${txt(first.location)}`,
    `Attendance Type: ${TYPE_LABEL[cfg.type]}`,
    `Date: ${longDate(first.date)}`,
    `${cfg.dateLabel}: ${txt(first.service_label)}`,
  ];
  if (cfg.overviewEventTag) overview.push(`Event Tag: ${txt(firstOf(services, "event_tag"))}`);

  const parts: Part[] = [
    { kind: "text", lines: [bi(`${submitter} has submitted ${TYPE_LABEL[cfg.type]} Attendance:`)] },
    { kind: "divider" },
    { kind: "text", lines: overview },
    { kind: "divider" },
  ];

  if (cfg.details) {
    const detailLines = [bi("🔍 DETAILS"), ""];
    for (const d of cfg.details) detailLines.push(`${d.label}: ${txt(firstOf(services, d.field))}`);
    parts.push({ kind: "text", lines: detailLines });
    parts.push({ kind: "divider" });
  }

  const attLines = [bi("📊 ATTENDANCE"), "", ...areaLines(areas, cfg.areaOrder, cfg.areaLabels)];
  attLines.push(bi(`Total Attendance: ${num(sumTotal(areas))}`));
  if (cfg.showDecisions) attLines.push(bi(`Decisions: ${num(dec)}`));
  parts.push({ kind: "text", lines: attLines });
  parts.push({ kind: "text", lines: [it(`Notes: ${txt(firstOf(services, "notes"))}`)] });
  return blocksFromParts(parts);
}

async function renderGroups(submitter: string, campus: string, services: Enriched[], campusId: string): Promise<unknown[]> {
  const first = services[0];
  let attendance = 0;
  let groups = 0;
  for (const s of services) {
    attendance += s.areas["auditorium"] ?? 0;
    groups += s.group_count ?? 0;
  }

  // Last 3 weeks: prior groups submissions for this campus.
  const { data: prior } = await admin
    .from("services")
    .select("date, group_count, id")
    .eq("campus_id", campusId)
    .eq("gathering_type", "groups")
    .is("deleted_at", null)
    .lt("date", first.date)
    .order("date", { ascending: false })
    .limit(3);

  const priorLines: string[] = [];
  for (const p of prior ?? []) {
    const { data: a } = await admin.from("attendance").select("count").eq("service_id", p.id).eq("area", "auditorium");
    const att = (a ?? []).reduce((t, r: { count: number }) => t + (r.count ?? 0), 0);
    priorLines.push(`${weekRange(p.date)} — # of Groups: ${num(p.group_count)} — Total Attendance: ${num(att)}`);
  }

  const parts: Part[] = [
    { kind: "text", lines: [bi(`${submitter} has submitted Community Groups Attendance:`)] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("🔹 OVERVIEW"), "",
      `Campus: ${txt(campus)}`,
      `Location: ${txt(first.location)}`,
      "Attendance Type: Community Groups",
      `Date range (week): ${weekRange(first.date)}`,
    ] },
    { kind: "divider" },
    { kind: "text", lines: [bi("🔍 DETAILS"), "", `Event Tag: ${txt(firstOf(services, "event_tag"))}`] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("📊 THIS WEEK'S ATTENDANCE"), "",
      `# of Groups (active this week): ${num(groups)}`,
      bi(`Total Attendance: ${num(attendance)}`),
      bi("Decisions: --"),
    ] },
    { kind: "divider" },
    { kind: "text", lines: [bi("📊 LAST 3 WEEKS"), "", ...(priorLines.length ? priorLines : ["--"])] },
    { kind: "text", lines: [it(`Notes: ${txt(firstOf(services, "notes"))}`)] },
  ];
  return blocksFromParts(parts);
}

function renderOnline(submitter: string, campus: string, services: Enriched[]): unknown[] {
  const first = services[0];
  const areas: Record<string, number> = {};
  for (const s of services) {
    for (const [k, v] of Object.entries(s.areas)) areas[k] = (areas[k] ?? 0) + v;
  }
  const reach = [
    { k: "prev_message", label: "YouTube – Previous Sunday Message" },
    { k: "other_content", label: "YouTube – Other Content" },
    { k: "sunday_livestream", label: "YouTube – Sunday Livestream" },
    { k: "podcast_listens", label: "Spotify – Podcast Listens" },
  ];
  const total = reach.reduce((t, r) => t + (areas[r.k] ?? 0), 0);

  const parts: Part[] = [
    { kind: "text", lines: [bi(`${submitter} has submitted Online Metrics Attendance:`)] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("🔹 OVERVIEW"), "",
      `Campus: ${txt(campus)}`,
      "Location: YouTube · Spotify",
      "Attendance Type: Online Metrics",
      `Date: ${longDate(first.date)}`,
      `Service Time: ${txt(first.service_label)}`,
    ] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("🔍 DETAILS"), "",
      `Speaker: ${txt(firstOf(services, "speaker"))}`,
      `Series: ${txt(firstOf(services, "series"))}`,
      `Message Title: ${txt(firstOf(services, "message_title"))}`,
      `Event Tag (optional): ${txt(firstOf(services, "event_tag"))}`,
    ] },
    { kind: "divider" },
    { kind: "text", lines: [
      bi("📈 ONLINE REACH"), "",
      ...reach.map((r) => `${r.label}: ${num(areas[r.k] ?? 0)}`),
      bi(`Online Totals: ${num(total)}`),
      bi("Decisions: --"),
    ] },
    { kind: "text", lines: [it(`Notes: ${txt(firstOf(services, "notes"))}`)] },
  ];
  return blocksFromParts(parts);
}

// ---------- data loading ----------

async function loadDayServices(campusId: string, date: string, gatheringType: string): Promise<Enriched[]> {
  const { data: rows, error } = await admin
    .from("services")
    .select("*")
    .eq("campus_id", campusId)
    .eq("date", date)
    .eq("gathering_type", gatheringType)
    .is("deleted_at", null)
    .order("created_at", { ascending: true });
  if (error) throw error;
  const services = (rows ?? []) as ServiceRow[];

  const enriched: Enriched[] = [];
  for (const s of services) {
    const [{ data: att }, { data: dec }] = await Promise.all([
      admin.from("attendance").select("area, count").eq("service_id", s.id),
      admin.from("decisions").select("type, count").eq("service_id", s.id),
    ]);
    const areas: Record<string, number> = {};
    for (const a of att ?? []) areas[(a as { area: string }).area] = (a as { count: number }).count ?? 0;
    const decisions: Record<string, number> = {};
    for (const d of dec ?? []) {
      const t = (d as { type: string }).type;
      decisions[t] = (decisions[t] ?? 0) + ((d as { count: number }).count ?? 0);
    }
    enriched.push({ ...s, areas, decisions });
  }
  return enriched;
}

async function submitterName(createdBy: string | null): Promise<string> {
  if (!createdBy) return "Someone";
  const { data } = await admin.from("profiles").select("display_name, full_name").eq("id", createdBy).maybeSingle();
  return (data?.display_name || data?.full_name || "Someone").toString();
}

// ---------- Slack ----------

let cachedToken: string | null = null;
async function slackToken(): Promise<string> {
  if (cachedToken) return cachedToken;
  const { data, error } = await admin.rpc("get_vault_secret", { p_name: "slack_bot_token" });
  if (error || !data) throw new Error("could not read slack_bot_token from vault");
  cachedToken = data as string;
  return cachedToken;
}

async function slackCall(method: string, body: Record<string, unknown>) {
  const token = await slackToken();
  const res = await fetch(`${SLACK_API}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8", Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  if (!json.ok) throw new Error(`slack ${method} failed: ${json.error}`);
  return json;
}

// ---------- main handler ----------

async function buildCard(campusId: string, date: string, gatheringType: string) {
  const services = await loadDayServices(campusId, date, gatheringType);
  if (!services.length) return null;

  const { data: campusRow } = await admin.from("campuses").select("name").eq("id", campusId).maybeSingle();
  const campus = campusRow?.name ?? "--";
  const submitter = await submitterName(services[services.length - 1].created_by);

  let blocks: unknown[];
  switch (gatheringType) {
    case "sunday":
      blocks = renderSunday(submitter, campus, services);
      break;
    case "online":
      blocks = renderOnline(submitter, campus, services);
      break;
    case "groups":
      blocks = await renderGroups(submitter, campus, services, campusId);
      break;
    case "midweek":
      blocks = renderSingleInPerson(submitter, campus, services, {
        type: "midweek", dateLabel: "Service Time",
        details: [
          { field: "speaker", label: "Speaker" },
          { field: "series", label: "Series" },
          { field: "message_title", label: "Message Title" },
          { field: "event_tag", label: "Event Tag (optional)" },
        ],
        areaOrder: ["auditorium", "other_adults"],
        areaLabels: { auditorium: "Auditorium", other_adults: "Other Adults" },
        showDecisions: true,
      });
      break;
    case "special":
      blocks = renderSingleInPerson(submitter, campus, services, {
        type: "special", dateLabel: "Event Time",
        details: [
          { field: "speaker", label: "Speaker" },
          { field: "event_tag", label: "Event Tag" },
          { field: "segment", label: "Ministry Segment" },
        ],
        areaOrder: ["auditorium", "other_adults"],
        areaLabels: { auditorium: "Auditorium (Guests)", other_adults: "Other Adults (Volunteers)" },
        showDecisions: true,
      });
      break;
    case "next_steps":
      blocks = renderSingleInPerson(submitter, campus, services, {
        type: "next_steps", dateLabel: "Event Time",
        details: null,
        areaOrder: ["auditorium", "other_adults"],
        areaLabels: {
          auditorium: "Auditorium (people who took the class/session)",
          other_adults: "Other Adults (Volunteers)",
        },
        showDecisions: false,
        overviewEventTag: true,
      });
      break;
    default:
      // Custom types fall back to a Sunday-style card.
      blocks = renderSunday(submitter, campus, services);
  }

  const fallback = `${submitter} has submitted ${TYPE_LABEL[gatheringType] ?? gatheringType} Attendance`;
  return { blocks, fallback };
}

// Resolve the (campus_id, date, gathering_type) key from a webhook/manual payload.
async function resolveKey(payload: Record<string, unknown>) {
  if (payload.campus_id && payload.date && payload.gathering_type) {
    return {
      campusId: payload.campus_id as string,
      date: payload.date as string,
      gatheringType: payload.gathering_type as string,
    };
  }
  const record = (payload.record ?? payload) as Record<string, unknown>;
  let serviceId = (record.service_id as string) ?? (record.id as string) ?? (payload.service_id as string);
  if (record.gathering_type && record.campus_id && record.date) {
    return {
      campusId: record.campus_id as string,
      date: record.date as string,
      gatheringType: record.gathering_type as string,
    };
  }
  if (!serviceId) throw new Error("payload missing service_id / record");
  const { data: svc, error } = await admin
    .from("services")
    .select("campus_id, date, gathering_type, deleted_at")
    .eq("id", serviceId)
    .maybeSingle();
  if (error || !svc) throw new Error("service not found for id " + serviceId);
  return { campusId: svc.campus_id, date: svc.date, gatheringType: svc.gathering_type };
}

Deno.serve(async (req) => {
  try {
    const payload = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const dryRun = payload.dry_run === true;

    const { campusId, date, gatheringType } = await resolveKey(payload);
    const card = await buildCard(campusId, date, gatheringType);
    if (!card) return json({ ok: true, skipped: "no services for key" });

    if (dryRun) {
      return json({ ok: true, dry_run: true, key: { campusId, date, gatheringType }, ...card });
    }

    // One card per (campus_id, alert_date). A submission inserts several rows at
    // once, so this function can be invoked concurrently. Claim atomically: try to
    // insert a PENDING row — exactly one caller wins (unique constraint) and posts;
    // everyone else waits for the ts and edits the existing card.
    const claim = await admin
      .from("numbers_alert_cards")
      .insert({ campus_id: campusId, alert_date: date, slack_channel: SLACK_CHANNEL, slack_message_ts: "PENDING" })
      .select("id")
      .maybeSingle();

    if (!claim.error && claim.data) {
      const res = await slackCall("chat.postMessage", {
        channel: SLACK_CHANNEL, text: card.fallback, blocks: card.blocks,
      });
      await admin.from("numbers_alert_cards")
        .update({ slack_message_ts: res.ts, updated_at: new Date().toISOString() })
        .eq("id", claim.data.id);
      return json({ ok: true, action: "posted", ts: res.ts });
    }

    // Not the claimer: a row already exists (established card, or a sibling call is
    // still posting). Wait briefly for a real ts, then edit that message.
    if (claim.error && claim.error.code !== "23505") throw claim.error;

    let ts: string | null = null;
    for (let i = 0; i < 15; i++) {
      const { data } = await admin.from("numbers_alert_cards")
        .select("slack_message_ts").eq("campus_id", campusId).eq("alert_date", date).maybeSingle();
      if (data?.slack_message_ts && data.slack_message_ts !== "PENDING") { ts = data.slack_message_ts; break; }
      await new Promise((r) => setTimeout(r, 300));
    }
    if (!ts) return json({ ok: false, error: "card still pending after wait" }, 202);

    await slackCall("chat.update", {
      channel: SLACK_CHANNEL, ts, text: card.fallback, blocks: card.blocks,
    });
    await admin.from("numbers_alert_cards")
      .update({ updated_at: new Date().toISOString() })
      .eq("campus_id", campusId).eq("alert_date", date);
    return json({ ok: true, action: "updated", ts });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json" },
  });
}
