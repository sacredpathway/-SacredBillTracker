import { cors, json, admin } from "../verify-store-subscription/shared.ts";
import { decodePubSubMessage, rtdnEventRecord } from "../_shared/rtdn-policy.mjs";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const expectedSubscription = (Deno.env.get("GOOGLE_PLAY_RTDN_SUBSCRIPTION") ?? "").trim();
  const expectedPackageName = (Deno.env.get("GOOGLE_PACKAGE_NAME") ?? "").trim();
  const expectedBearer = (Deno.env.get("GOOGLE_PLAY_RTDN_SHARED_TOKEN") ?? "").trim();
  if (!expectedSubscription || !expectedPackageName || !expectedBearer) return json({ error: "google_rtdn_not_configured" }, 503);
  if (req.headers.get("authorization") !== `Bearer ${expectedBearer}`) return json({ error: "unauthorized" }, 401);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  try {
    const decoded = decodePubSubMessage(body, { expectedSubscription, expectedPackageName });
    const event = rtdnEventRecord(decoded, body.environment === "production" ? "production" : "sandbox");
    const db = admin();
    const { error } = await db.rpc("claim_google_store_notification", {
      p_environment: event.environment,
      p_event_id: event.eventId,
      p_purchase_token_hash: event.providerOriginalId,
      p_raw_payload: event.raw,
    });
    if (error) return json({ error: "notification_persistence_unavailable" }, 503);
    // RTDN itself grants nothing. A deployment worker must verify current Play state.
    return json({ accepted: true, event_id: event.eventId, reconciliation_required: true });
  } catch {
    return json({ error: "notification_rejected" }, 400);
  }
});
