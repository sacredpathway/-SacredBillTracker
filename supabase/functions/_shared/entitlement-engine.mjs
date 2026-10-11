export const PRODUCT_TIERS = Object.freeze({
  essential_monthly_499: "essential",
  business_monthly_999: "business",
  unlimited_monthly_1499: "unlimited",
  "com.sacredbilltracker.app.pro.monthly": "business",
  "com.sacredbilltracker.app.pro.yearly": "business",
  sacred_focus_plus_monthly: "free",
  "com.sacredbilltracker.app.autotrack.monthly": "unlimited",
  "com.sacredbilltracker.app.autotrack.annual": "unlimited",
});

export const RECEIPT_JAR_PRODUCT_ID = "com.sacredbilltracker.app.receiptjar.lifetime";

export const GRANTING_STATES = new Set(["active", "trial", "grace", "cancelled_active"]);
export const NON_GRANTING_STATES = new Set([
  "billing_retry",
  "account_hold",
  "expired",
  "revoked",
  "refunded",
  "quarantined",
  "paused",
  "pending",
]);

const TIER_RANK = Object.freeze({ free: 0, essential: 1, business: 2, unlimited: 3 });

export function planTierForProduct(productId) {
  return PRODUCT_TIERS[productId] ?? "free";
}

export function maxTier(a, b) {
  return (TIER_RANK[b] ?? 0) > (TIER_RANK[a] ?? 0) ? b : a;
}

export function normalizedStatus(input) {
  if (GRANTING_STATES.has(input) || NON_GRANTING_STATES.has(input)) return input;
  return "quarantined";
}

export function isGrantingStatus(status) {
  return GRANTING_STATES.has(normalizedStatus(status));
}

export function purchaseKey(purchase) {
  if (!purchase || !purchase.provider || !purchase.environment || !purchase.providerOriginalId) {
    throw new Error("invalid_purchase_identity");
  }
  return `${purchase.provider}:${purchase.environment}:${purchase.providerOriginalId}`;
}

export function eventKey(event) {
  if (!event || !event.provider || !event.environment || !event.eventId) {
    throw new Error("invalid_event_identity");
  }
  return `${event.provider}:${event.environment}:${event.eventId}`;
}

export function conflictState(existingOwner, requestedOwner) {
  if (!existingOwner || existingOwner === requestedOwner) return "securely_bound";
  return "ownership_conflict";
}

export function entitlementSnapshot({ accountId, environment, purchases, rewards = [], verifiedAt }) {
  if (!accountId || !environment) throw new Error("invalid_snapshot_owner");
  const now = typeof verifiedAt === "number" ? verifiedAt : Math.floor(Date.now() / 1000);
  let effectivePlanTier = "free";
  let receiptJarLifetime = false;
  let hasConflict = false;

  for (const purchase of purchases ?? []) {
    const status = normalizedStatus(purchase.status);
    if (status === "quarantined" || purchase.conflict === true) hasConflict = true;
    if (!isGrantingStatus(status)) continue;
    if (purchase.productId === RECEIPT_JAR_PRODUCT_ID) {
      receiptJarLifetime = true;
      continue;
    }
    effectivePlanTier = maxTier(effectivePlanTier, planTierForProduct(purchase.productId));
  }

  for (const reward of rewards) {
    if (reward.expiresAt != null && reward.expiresAt <= now) continue;
    effectivePlanTier = maxTier(effectivePlanTier, reward.tier ?? "free");
  }

  return {
    version: 1,
    account_id: accountId,
    environment,
    verified_at: now,
    effective_plan_tier: effectivePlanTier,
    receipt_jar_lifetime: receiptJarLifetime,
    has_conflict: hasConflict,
    ownership_resolution: hasConflict ? "quarantined" : "securely_bound",
  };
}
