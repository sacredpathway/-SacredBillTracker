import { json, admin, isUuid } from "./shared.ts";
import { verifyAppleJws } from "./verify.ts";
import {
  HANDLER_VERSION,
  validateRenewalPayload,
  validateNotificationPayload,
  validateTransactionPayload,
} from "./validation.ts";
import { deriveStatus, duplicateDecision } from "./routing.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Record<string, unknown>;
  try { body = await request.json(); }
  catch { return json({ error: "invalid_json" }, 400); }
  if (typeof body.signedPayload !== "string") {
    return json({ error: "missing_signed_payload" }, 400);
  }

  let verified;
  try {
    const outerPayload = await verifyAppleJws(body.signedPayload);
    verified = validateNotificationPayload(outerPayload);
  } catch (error) {
    return json({
      error: "invalid_signed_notification",
      reason: String(error instanceof Error ? error.message : error),
    }, 401);
  }

  const db = admin();
  const receivedAt = new Date().toISOString();
  const claim = await db.rpc("claim_apple_store_notification", {
    p_notification_id: verified.notificationUUID,
    p_notification_type: verified.notificationType,
    p_subtype: verified.subtype,
    p_environment: verified.environment,
    p_signed_date: verified.signedDate,
    p_received_at: receivedAt,
    p_handler_version: HANDLER_VERSION,
    p_raw: {
      notificationType: verified.notificationType,
      subtype: verified.subtype,
      environment: verified.environment,
      bundleId: verified.data.bundleId,
    },
  });
  if (claim.error || !claim.data) return json({ error: "audit_claim_failed" }, 500);
  const claimResult = claim.data as {
    event_id: string;
    claimed: boolean;
    status: string;
  };
  const eventId = claimResult.event_id;
  if (!claimResult.claimed) {
    if (duplicateDecision(claimResult.status) === "RETURN_SUCCESS") {
      return json({ ok: true, duplicate: true });
    }
    // A live processing lease is not acknowledged as complete. Apple can retry;
    // a stale lease becomes reclaimable after five minutes.
    return json({ error: "notification_already_processing" }, 503);
  }

  const finish = async (
    status: "processed" | "ignored" | "retryable_failure" | "permanent_rejection",
    detail: string,
    code = 200,
    errorCode: string | null = null,
  ) => {
    const completion = await db.from("store_notification_events").update({
      status,
      detail,
      error_code: errorCode,
      error_summary:
        status === "retryable_failure" || status === "permanent_rejection"
          ? detail.slice(0, 500)
          : null,
      processed_at: new Date().toISOString(),
    }).eq("id", eventId);
    if (completion.error) {
      return json({ ok: false, error: "audit_completion_failed" }, 500);
    }
    return json({ ok: code === 200, status, detail }, code);
  };

  if (verified.notificationType === "TEST") {
    return finish("processed", "test_notification");
  }

  const data = verified.data;
  let transaction: Record<string, unknown> = {};
  let renewal: Record<string, unknown> = {};
  try {
    if (typeof data.signedTransactionInfo === "string") {
      transaction = validateTransactionPayload(
        await verifyAppleJws(data.signedTransactionInfo),
        verified.environment,
      );
    }
    if (typeof data.signedRenewalInfo === "string") {
      renewal = validateRenewalPayload(
        await verifyAppleJws(data.signedRenewalInfo),
        verified.environment,
      );
    }
  } catch (error) {
    return finish(
      "permanent_rejection",
      String(error instanceof Error ? error.message : error),
      401,
      "nested_jws_invalid",
    );
  }

  const newStatus = deriveStatus(verified.notificationType, verified.subtype);
  if (!newStatus) return finish("ignored", `no_status_change:${verified.notificationType}`);
  if (!transaction.originalTransactionId || !transaction.transactionId || !transaction.productId) {
    return finish("permanent_rejection", "missing_transaction_identity", 400, "missing_transaction_identity");
  }

  let ownerId = isUuid(transaction.appAccountToken) ? transaction.appAccountToken : null;
  if (!ownerId) {
    const existing = await db.from("subscriptions")
      .select("owner_id")
      .eq("original_transaction_id", String(transaction.originalTransactionId))
      .maybeSingle();
    ownerId = existing.data?.owner_id ?? null;
  }
  if (!ownerId) return finish("ignored", "no_user_mapping");

  const expiresMs = Number(transaction.expiresDate || renewal.renewalDate || 0) || null;
  const purchaseMs = Number(transaction.purchaseDate || 0) || null;
  const graceMs = Number(renewal.gracePeriodExpiresDate || 0) || null;
  const canceledAt =
    (verified.notificationType === "DID_CHANGE_RENEWAL_STATUS" &&
      verified.subtype === "AUTO_RENEW_DISABLED") ||
    newStatus === "revoked"
      ? new Date().toISOString()
      : null;

  const result = await db.rpc("record_verified_subscription", {
    p_owner_id: ownerId,
    p_platform: "ios_appstore",
    p_store_product_id: String(transaction.productId),
    p_status: newStatus,
    p_current_period_end: expiresMs ? new Date(expiresMs).toISOString() : null,
    p_auto_renew: renewal.autoRenewStatus === 1,
    p_is_sandbox: verified.environment === "Sandbox",
    p_original_transaction_id: String(transaction.originalTransactionId),
    p_latest_transaction_id: String(transaction.transactionId),
    p_purchase_token: null,
    p_grace_period_end: graceMs ? new Date(graceMs).toISOString() : null,
    p_current_period_start: purchaseMs ? new Date(purchaseMs).toISOString() : null,
    p_canceled_at: canceledAt,
    p_raw_payload: {
      source: "assn_v2",
      notificationType: verified.notificationType,
      subtype: verified.subtype,
      status: newStatus,
    },
  });
  if (result.error) {
    return finish("retryable_failure", result.error.message, 500, "record_failed");
  }

  const completion = await db.from("store_notification_events").update({
    status: "processed",
    owner_id: ownerId,
    original_transaction_id: String(transaction.originalTransactionId),
    transaction_id: String(transaction.transactionId),
    product_id: String(transaction.productId),
    detail: newStatus,
    processed_at: new Date().toISOString(),
  }).eq("id", eventId);
  if (completion.error) {
    return json({ ok: false, error: "audit_completion_failed" }, 500);
  }
  return json({ ok: true, status: newStatus });
});
