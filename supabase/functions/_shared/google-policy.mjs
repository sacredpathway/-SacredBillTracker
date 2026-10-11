import { createHash } from "node:crypto";
import { entitlementSnapshot, isGrantingStatus, RECEIPT_JAR_PRODUCT_ID } from "./entitlement-engine.mjs";

const GOOGLE_SUBSCRIPTION_STATE = Object.freeze({
  SUBSCRIPTION_STATE_ACTIVE: "active",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace",
  SUBSCRIPTION_STATE_ON_HOLD: "account_hold",
  SUBSCRIPTION_STATE_PAUSED: "paused",
  SUBSCRIPTION_STATE_CANCELED: "cancelled_active",
  SUBSCRIPTION_STATE_EXPIRED: "expired",
  SUBSCRIPTION_STATE_PENDING: "pending",
});

export const GOOGLE_PRODUCTS = new Set([
  "sacred_bill_tracker_pro_monthly",
  "sacred_bill_tracker_pro_yearly",
  "sacred_focus_plus_monthly",
  "sacred_autotrack_monthly_1499",
  "sacred_autotrack_annual_11999",
]);

export function tokenHash(token) {
  if (typeof token !== "string" || token.length < 1 || token.length > 4096) {
    throw new Error("invalid_purchase_token");
  }
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function mapGoogleSubscriptionState(state, expirySeconds, nowSeconds) {
  const mapped = GOOGLE_SUBSCRIPTION_STATE[state] ?? "quarantined";
  if (mapped === "cancelled_active") return expirySeconds > nowSeconds ? "cancelled_active" : "expired";
  return mapped;
}

export function normalizeGoogleSubscription({ accountId, environment, packageName, expectedPackageName, productId, purchaseToken, response, nowSeconds }) {
  if (packageName !== expectedPackageName) throw new Error("wrong_package");
  if (!GOOGLE_PRODUCTS.has(productId)) throw new Error("wrong_product");
  if (response?.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") throw new Error("purchase_not_acknowledged");
  const lineItems = Array.isArray(response?.lineItems) ? response.lineItems.filter((item) => item.productId === productId) : [];
  if (lineItems.length !== 1) throw new Error("product_line_not_unique");
  const expirySeconds = Date.parse(lineItems[0].expiryTime ?? "") / 1000;
  if (!Number.isFinite(expirySeconds)) throw new Error("invalid_expiry");
  const status = mapGoogleSubscriptionState(response.subscriptionState, expirySeconds, nowSeconds);
  const external = response?.externalAccountIdentifiers?.obfuscatedExternalAccountId;
  if (external && external !== accountId) throw new Error("ownership_conflict");
  const sandbox = response.testPurchase != null;
  if ((environment === "sandbox") !== sandbox) throw new Error("environment_mismatch");
  return {
    provider: "google",
    environment,
    providerOriginalId: tokenHash(purchaseToken),
    tokenHash: tokenHash(purchaseToken),
    orderId: response.latestOrderId ?? lineItems[0].latestSuccessfulOrderId ?? null,
    productId,
    status,
    expiresAt: expirySeconds,
    accountId,
    active: isGrantingStatus(status),
    rawState: response.subscriptionState,
  };
}

export function normalizeGoogleOneTimeProduct({ accountId, environment, packageName, expectedPackageName, productId, purchaseToken, response }) {
  if (productId === RECEIPT_JAR_PRODUCT_ID) throw new Error("google_receipt_jar_not_defined");
  if (packageName !== expectedPackageName) throw new Error("wrong_package");
  if (response?.purchaseState !== 0) throw new Error("one_time_product_not_purchased");
  if (response?.acknowledgementState !== 1) throw new Error("purchase_not_acknowledged");
  return {
    provider: "google",
    environment,
    providerOriginalId: tokenHash(purchaseToken),
    tokenHash: tokenHash(purchaseToken),
    productId,
    status: response?.voidedPurchase ? "revoked" : "active",
    accountId,
    active: !response?.voidedPurchase,
  };
}

export function googleSnapshot({ accountId, environment, purchases, verifiedAt }) {
  return entitlementSnapshot({ accountId, environment, purchases, verifiedAt });
}
