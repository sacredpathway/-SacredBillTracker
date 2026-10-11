export const EXPECTED_BUNDLE_ID = "com.sacredbilltracker.app";
export const EXPECTED_APPLE_APP_ID = 6762890363;
export const HANDLER_VERSION = "8";
export const SUPPORTED_VERSION = "2.0";
// Apple production retries preserve signedDate and can occur through the
// cumulative 1h + 12h + 24h + 48h + 72h schedule. Seven days accepts the
// documented retry window; notificationUUID idempotency prevents replay writes.
export const MAX_SIGNED_DATE_AGE_MS = 7 * 24 * 60 * 60 * 1000;
export const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;
export const ALLOWED_PRODUCT_IDS = new Set([
  "essential_monthly_499",
  "business_monthly_999",
  "unlimited_monthly_1499",
]);

export const RECOGNIZED_NOTIFICATION_TYPES = new Set([
  "TEST", "SUBSCRIBED", "DID_RENEW", "DID_CHANGE_RENEWAL_STATUS",
  "DID_CHANGE_RENEWAL_PREF", "DID_FAIL_TO_RENEW", "GRACE_PERIOD_EXPIRED",
  "EXPIRED", "REFUND", "REVOKE", "RENEWAL_EXTENDED", "REFUND_DECLINED",
  "OFFER_REDEEMED",
]);

export type AppleEnvironment = "Sandbox" | "Production";

// The same authenticated handler URL is configured for both Apple environments.
// Known environments are accepted and persisted; unknown values fail closed.
export function environmentPolicy(environment: unknown): "ACCEPT_AND_TAG" | "REJECT" {
  return environment === "Sandbox" || environment === "Production"
    ? "ACCEPT_AND_TAG"
    : "REJECT";
}

export function validateJwsHeader(header: Record<string, unknown>) {
  const allowedFields = new Set(["alg", "x5c", "crit"]);
  for (const field of Object.keys(header)) {
    if (!allowedFields.has(field)) throw new Error("unsupported_jws_header");
  }
  if (header.alg !== "ES256") throw new Error("unexpected_algorithm");
  if (Array.isArray(header.crit) && header.crit.length > 0) {
    throw new Error("unsupported_critical_header");
  }
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3 ||
      header.x5c.some((item) => typeof item !== "string" || item.length === 0)) {
    throw new Error("invalid_x5c_chain");
  }
}

function assertStoreIdentifier(value: unknown, field: string) {
  if (typeof value !== "string" || !/^[1-9][0-9]{4,30}$/.test(value)) {
    throw new Error(`invalid_${field}`);
  }
}

function assertTimestamp(value: unknown, field: string, now: number) {
  if (typeof value !== "number" || !Number.isSafeInteger(value) ||
      value < 946684800000 || value > now + 10 * 365 * 24 * 60 * 60 * 1000) {
    throw new Error(`invalid_${field}`);
  }
}

export function validateTransactionPayload(
  payload: Record<string, unknown>,
  environment: AppleEnvironment,
  now = Date.now(),
) {
  if (payload.bundleId !== EXPECTED_BUNDLE_ID) throw new Error("nested_wrong_bundle_id");
  if (payload.environment !== environment) throw new Error("nested_wrong_environment");
  assertStoreIdentifier(payload.originalTransactionId, "original_transaction_id");
  assertStoreIdentifier(payload.transactionId, "transaction_id");
  if (typeof payload.productId !== "string" || !ALLOWED_PRODUCT_IDS.has(payload.productId)) {
    throw new Error("unexpected_product_id");
  }
  assertTimestamp(payload.purchaseDate, "purchase_date", now);
  assertTimestamp(payload.expiresDate, "expires_date", now);
  if ((payload.expiresDate as number) < (payload.purchaseDate as number)) {
    throw new Error("expiration_precedes_purchase");
  }
  if (typeof payload.signedDate === "number") assertTimestamp(payload.signedDate, "signed_date", now);
  return payload;
}

export function validateRenewalPayload(
  payload: Record<string, unknown>,
  environment: AppleEnvironment,
  now = Date.now(),
) {
  if (payload.environment !== environment) throw new Error("nested_wrong_environment");
  assertStoreIdentifier(payload.originalTransactionId, "original_transaction_id");
  const productId = payload.autoRenewProductId ?? payload.productId;
  if (typeof productId !== "string" || !ALLOWED_PRODUCT_IDS.has(productId)) {
    throw new Error("unexpected_product_id");
  }
  if (payload.renewalDate !== undefined) assertTimestamp(payload.renewalDate, "renewal_date", now);
  if (payload.gracePeriodExpiresDate !== undefined) {
    assertTimestamp(payload.gracePeriodExpiresDate, "grace_period_expires_date", now);
  }
  if (payload.signedDate !== undefined) assertTimestamp(payload.signedDate, "signed_date", now);
  return payload;
}

export function assertValidityWindow(notBefore: number, notAfter: number, now = Date.now()) {
  if (now < notBefore) throw new Error("certificate_not_yet_valid");
  if (now > notAfter) throw new Error("certificate_expired");
}

export function validateNotificationPayload(payload: Record<string, unknown>, now = Date.now()) {
  if (payload.version !== SUPPORTED_VERSION) throw new Error("unsupported_version");
  if (typeof payload.notificationUUID !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(payload.notificationUUID)) {
    throw new Error("invalid_notification_uuid");
  }
  if (typeof payload.notificationType !== "string" ||
      !RECOGNIZED_NOTIFICATION_TYPES.has(payload.notificationType)) {
    throw new Error("unsupported_notification_type");
  }
  if (typeof payload.signedDate !== "number") throw new Error("missing_signed_date");
  if (payload.signedDate < now - MAX_SIGNED_DATE_AGE_MS ||
      payload.signedDate > now + MAX_FUTURE_SKEW_MS) {
    throw new Error("implausible_signed_date");
  }

  const data = payload.data as Record<string, unknown> | undefined;
  if (!data || data.bundleId !== EXPECTED_BUNDLE_ID) throw new Error("wrong_bundle_id");
  if (Number(data.appAppleId) !== EXPECTED_APPLE_APP_ID) throw new Error("wrong_apple_app_id");
  if (environmentPolicy(data.environment) === "REJECT") throw new Error("wrong_environment");

  return {
    notificationUUID: payload.notificationUUID,
    notificationType: payload.notificationType,
    subtype: typeof payload.subtype === "string" ? payload.subtype : null,
    signedDate: new Date(payload.signedDate).toISOString(),
    environment: data.environment as AppleEnvironment,
    data,
  };
}
