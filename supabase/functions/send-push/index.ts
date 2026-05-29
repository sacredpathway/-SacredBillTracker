// supabase/functions/send-push/index.ts
//
// Sacred Pathway Driver Hub — P5 (Notifications)
//
// Supabase Edge Function: signs an APNs JWT and pushes to all active device_tokens
// for a given user_id. Triggered by:
//   • Postgres trigger on settlements (event = "settlement.synced" / "settlement.created")
//   • Postgres trigger on share_links (event = "share.expired" / "share.expiring_soon")
//   • Direct invoke from the app or a cron job
//
// Deploy:
//   supabase functions deploy send-push --no-verify-jwt
//
// Required secrets (supabase secrets set …):
//   APNS_TEAM_ID         — 10-char Apple developer team id
//   APNS_KEY_ID          — 10-char APNs auth key id
//   APNS_PRIVATE_KEY     — contents of AuthKey_<KEY_ID>.p8 (PEM)
//   APNS_BUNDLE_ID       — e.g. com.sacredpathway.driverhub
//   APNS_ENVIRONMENT     — "production" | "sandbox" (default: production)
//
// Request body:
//   {
//     "user_id": "<uuid>",
//     "event":   "settlement.created" | "settlement.synced" | "share.expired" | …
//     "title":   "New Settlement",
//     "body":    "Pay period PY00063: $2,341.55 ready to review.",
//     "privacyBody": "A new settlement is ready to view.",
//     "settlementId": "<uuid?>",
//     "shareId":      "<uuid?>",
//     "amount":       "2341.55",
//     "silent":       false        // if true → content-available only, no banner
//   }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create as createJwt, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

// ---------- env ----------
const SUPABASE_URL          = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY      = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_TEAM_ID          = Deno.env.get("APNS_TEAM_ID")!;
const APNS_KEY_ID           = Deno.env.get("APNS_KEY_ID")!;
const APNS_PRIVATE_KEY_PEM  = Deno.env.get("APNS_PRIVATE_KEY")!;
const APNS_BUNDLE_ID        = Deno.env.get("APNS_BUNDLE_ID")!;
const APNS_ENVIRONMENT      = Deno.env.get("APNS_ENVIRONMENT") ?? "production";

const APNS_HOST = APNS_ENVIRONMENT === "sandbox"
  ? "https://api.sandbox.push.apple.com"
  : "https://api.push.apple.com";

// ---------- supabase ----------
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ---------- JWT cache ----------
let cachedToken: { jwt: string; issuedAt: number } | null = null;
async function getApnsJwt(): Promise<string> {
  // APNs JWTs must be < 60 minutes old. Refresh every 50.
  if (cachedToken && Date.now() - cachedToken.issuedAt < 50 * 60 * 1000) {
    return cachedToken.jwt;
  }

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(APNS_PRIVATE_KEY_PEM),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const jwt = await createJwt(
    { alg: "ES256", kid: APNS_KEY_ID, typ: "JWT" },
    { iss: APNS_TEAM_ID, iat: getNumericDate(0) },
    key,
  );

  cachedToken = { jwt, issuedAt: Date.now() };
  return jwt;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

// ---------- handler ----------
serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let body: SendPushRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (!body.user_id || !body.event) {
    return json({ error: "missing_user_id_or_event" }, 400);
  }

  // 1. Fetch active device tokens for this user
  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("apns_token, device_id")
    .eq("user_id", body.user_id)
    .eq("active", true);

  if (error) return json({ error: error.message }, 500);
  if (!tokens || tokens.length === 0) {
    return json({ ok: true, sent: 0, reason: "no_active_tokens" });
  }

  // 2. Build APNs payload
  const aps: Record<string, unknown> = body.silent
    ? { "content-available": 1 }
    : {
        alert: { title: body.title ?? "Sacred Pathway", body: body.body ?? "" },
        sound: "default",
        "interruption-level": interruptionLevel(body.event),
      };

  const payload: Record<string, unknown> = {
    aps,
    event: body.event,
    deepLink: deepLinkFor(body.event),
  };
  if (body.settlementId) payload.settlementId = body.settlementId;
  if (body.shareId)      payload.shareId      = body.shareId;
  if (body.amount)       payload.amount       = body.amount;
  if (body.privacyBody)  payload.privacyBody  = body.privacyBody;

  const jwt = await getApnsJwt();

  // 3. Fan-out — APNs calls in parallel, but capped at 8 concurrent.
  const results = await pMap(tokens, 8, async (t) => {
    const res = await fetch(`${APNS_HOST}/3/device/${t.apns_token}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${jwt}`,
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": body.silent ? "background" : "alert",
        "apns-priority": body.silent ? "5" : "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    if (res.status === 410 || res.status === 400) {
      // Bad/expired token — deactivate so we stop trying.
      await supabase
        .from("device_tokens")
        .update({ active: false, updated_at: new Date().toISOString() })
        .eq("device_id", t.device_id);
    }

    return { device_id: t.device_id, status: res.status };
  });

  const sent = results.filter((r) => r.status === 200).length;
  return json({ ok: true, sent, total: tokens.length, results });
});

// ---------- helpers ----------

interface SendPushRequest {
  user_id: string;
  event: string;
  title?: string;
  body?: string;
  privacyBody?: string;
  settlementId?: string;
  shareId?: string;
  amount?: string;
  silent?: boolean;
}

function deepLinkFor(event: string): string {
  switch (event) {
    case "settlement.created": return "/history/detail";
    case "settlement.synced":  return "/history";
    case "sync.failed":        return "/history";
    case "share.expiring_soon":
    case "share.expired":      return "/shares";
    case "export.completed":   return "/history";
    case "earnings.summary.weekly":
    case "earnings.summary.monthly": return "/summary";
    default: return "/history";
  }
}

function interruptionLevel(event: string): string {
  switch (event) {
    case "settlement.created":
    case "share.expiring_soon":
    case "share.expired":
    case "sync.failed":
      return "time-sensitive";
    case "earnings.summary.weekly":
    case "earnings.summary.monthly":
      return "passive";
    default:
      return "active";
  }
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function pMap<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let i = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (true) {
      const idx = i++;
      if (idx >= items.length) return;
      results[idx] = await fn(items[idx]);
    }
  });
  await Promise.all(workers);
  return results;
}
