import { RECEIPT_JAR_PRODUCT_ID } from "./entitlement-engine.mjs";

const APP_BUNDLE_ID = "com.sacredbilltracker.app";
const APPLE_ENVIRONMENTS = new Set(["production", "sandbox"]);
const NON_CONSUMABLE_TYPES = new Set(["Non-Consumable", "NON_CONSUMABLE", "non_consumable"]);

function requireUuid(value) {
  if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value ?? "")) throw new Error("invalid_account_id");
}

function normalizeEnvironment(environment) {
  const value = String(environment ?? "").toLowerCase();
  if (!APPLE_ENVIRONMENTS.has(value)) throw new Error("invalid_environment");
  return value;
}

export function normalizeAppleLifetimeTransaction({ accountId, environment, transaction, nowSeconds = Date.now() / 1000 }) {
  requireUuid(accountId);
  const expectedEnvironment = normalizeEnvironment(environment);
  if (!Number.isFinite(nowSeconds) || nowSeconds <= 0) throw new Error("invalid_verified_at");
  if (transaction?.bundleId !== APP_BUNDLE_ID) throw new Error("wrong_bundle");
  if (transaction?.environment?.toLowerCase?.() !== expectedEnvironment) throw new Error("environment_mismatch");
  if (transaction?.productId !== RECEIPT_JAR_PRODUCT_ID) throw new Error("wrong_product");
  if (transaction?.appAccountToken?.toLowerCase?.() !== accountId.toLowerCase()) throw new Error("ownership_conflict");
  if (transaction?.type != null && !NON_CONSUMABLE_TYPES.has(transaction.type)) throw new Error("wrong_product_type");
  if (transaction?.expiresDate != null) throw new Error("lifetime_purchase_must_not_expire");
  if (transaction?.inAppOwnershipType !== "PURCHASED") throw new Error("unsupported_ownership_type");
  const original = String(transaction.originalTransactionId ?? transaction.originalID ?? "");
  if (!/^\d{1,64}$/.test(original)) throw new Error("invalid_original_transaction_id");
  const transactionId = String(transaction.transactionId ?? "");
  if (!/^\d{1,64}$/.test(transactionId)) throw new Error("invalid_transaction_id");
  const signedDate = Number(transaction.signedDate ?? transaction.purchaseDate ?? nowSeconds * 1000);
  if (!Number.isFinite(signedDate) || signedDate <= 0 || signedDate > nowSeconds * 1000 + 300_000) throw new Error("invalid_signed_date");
  const revokedAt = transaction.revocationDate == null ? null : Number(transaction.revocationDate);
  const status = revokedAt == null ? "active" : transaction.revocationReason === 1 ? "refunded" : "revoked";
  return {
    provider: "apple",
    environment: expectedEnvironment,
    providerOriginalId: original,
    providerTransactionId: transactionId,
    productId: RECEIPT_JAR_PRODUCT_ID,
    status,
    accountId,
    active: status === "active",
    lifetime: status === "active",
    entitlementKind: "receipt_jar_lifetime",
    expiresAt: null,
    eventTimeSeconds: Math.floor((revokedAt ?? Number(transaction.purchaseDate ?? signedDate)) / 1000),
    verifiedAt: nowSeconds,
  };
}

export function resolveAppleLifetimeOwnership({ existingPurchase, verifiedPurchase }) {
  if (!verifiedPurchase?.accountId) throw new Error("missing_verified_purchase");
  if (!existingPurchase) return { state: "securely_bound", purchase: verifiedPurchase };
  if (existingPurchase.provider !== "apple") throw new Error("provider_mismatch");
  if (existingPurchase.environment !== verifiedPurchase.environment) throw new Error("environment_mismatch");
  if (existingPurchase.providerOriginalId !== verifiedPurchase.providerOriginalId) throw new Error("original_transaction_mismatch");
  if (existingPurchase.accountId?.toLowerCase?.() !== verifiedPurchase.accountId.toLowerCase()) {
    return { state: "owner_conflict", purchase: null };
  }
  return { state: "securely_bound", purchase: { ...existingPurchase, ...verifiedPurchase } };
}

export function appleLifetimeSnapshotPurchase(verifiedPurchase) {
  if (verifiedPurchase?.productId !== RECEIPT_JAR_PRODUCT_ID || verifiedPurchase?.status !== "active" || verifiedPurchase?.expiresAt !== null) {
    throw new Error("invalid_lifetime_purchase");
  }
  return { productId: RECEIPT_JAR_PRODUCT_ID, status: "active" };
}
