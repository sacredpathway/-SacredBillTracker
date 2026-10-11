import { cors, json, admin, getUser } from "../verify-store-subscription/shared.ts";
import { googleAccessToken } from "./crypto.ts";
import { normalizeGoogleSubscription, googleSnapshot } from "../_shared/google-policy.mjs";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const user = await getUser(req);
  if (!user || user.is_anonymous) return json({ error: "authenticated_account_required" }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  const environment = body?.environment === "sandbox" ? "sandbox" : body?.environment === "production" ? "production" : null;
  const purchaseToken = body?.purchase_token;
  const productId = body?.product_id;
  if (!environment || typeof purchaseToken !== "string" || typeof productId !== "string") {
    return json({ error: "invalid_purchase_evidence" }, 400);
  }

  const serviceAccount = (Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ?? "").trim();
  const packageName = (Deno.env.get("GOOGLE_PACKAGE_NAME") ?? "").trim();
  if (!serviceAccount || !packageName) return json({ error: "google_not_configured" }, 503);

  try {
    const accessToken = await googleAccessToken(serviceAccount, "https://www.googleapis.com/auth/androidpublisher");
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
    const response = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
    const payload = await response.json();
    if (!response.ok) return json({ error: "google_verification_unavailable" }, 503);

    const purchase = normalizeGoogleSubscription({
      accountId: user.id,
      environment,
      packageName,
      expectedPackageName: packageName,
      productId,
      purchaseToken,
      response: payload,
      nowSeconds: Math.floor(Date.now() / 1000),
    });

    const db = admin();
    const { error } = await db.rpc("record_verified_subscription", {
      p_owner_id: user.id,
      p_platform: "android_play",
      p_store_product_id: purchase.productId,
      p_status: purchase.status,
      p_current_period_end: purchase.expiresAt ? new Date(purchase.expiresAt * 1000).toISOString() : null,
      p_auto_renew: payload.lineItems?.[0]?.autoRenewingPlan?.autoRenewEnabled === true,
      p_is_sandbox: environment === "sandbox",
      p_original_transaction_id: null,
      p_latest_transaction_id: purchase.orderId,
      p_purchase_token: purchaseToken,
      p_grace_period_end: purchase.status === "grace" ? new Date(purchase.expiresAt * 1000).toISOString() : null,
      p_current_period_start: payload.startTime ?? null,
      p_canceled_at: payload.canceledStateContext ? new Date().toISOString() : null,
      p_raw_payload: payload,
    });
    if (error) return json({ error: "subscription_persistence_unavailable" }, 503);

    return json({ verification_state: "verified", purchase, entitlement_snapshot: googleSnapshot({
      accountId: user.id,
      environment,
      purchases: [purchase],
      verifiedAt: Math.floor(Date.now() / 1000),
    }) });
  } catch {
    return json({ error: "subscription_identity_or_state_rejected", verification_state: "rejected" }, 403);
  }
});
