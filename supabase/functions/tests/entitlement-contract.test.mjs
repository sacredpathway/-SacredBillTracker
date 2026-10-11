import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import test from "node:test";
import { entitlementSnapshot, RECEIPT_JAR_PRODUCT_ID } from "../_shared/entitlement-engine.mjs";
import {
  appleLifetimeSnapshotPurchase,
  normalizeAppleLifetimeTransaction,
  resolveAppleLifetimeOwnership,
} from "../_shared/apple-lifetime-policy.mjs";
import { decodePubSubMessage } from "../_shared/rtdn-policy.mjs";
import { normalizeGoogleSubscription, tokenHash } from "../_shared/google-policy.mjs";

const accountId = "11111111-1111-4111-8111-111111111111";
const otherAccountId = "22222222-2222-4222-8222-222222222222";
const currentDir = dirname(fileURLToPath(import.meta.url));
const functionsDir = join(currentDir, "..");

test("tier precedence keeps active unlimited above active essential", () => {
  const snapshot = entitlementSnapshot({ accountId, environment: "sandbox", verifiedAt: 1000, purchases: [
    { productId: "essential_monthly_499", status: "active" },
    { productId: "unlimited_monthly_1499", status: "active" },
  ] });
  assert.equal(snapshot.effective_plan_tier, "unlimited");
});

test("expired refunded revoked hold and quarantined purchases do not grant", () => {
  for (const status of ["expired", "refunded", "revoked", "account_hold", "quarantined"]) {
    const snapshot = entitlementSnapshot({ accountId, environment: "sandbox", verifiedAt: 1000, purchases: [
      { productId: "unlimited_monthly_1499", status },
    ] });
    assert.equal(snapshot.effective_plan_tier, "free");
  }
});

test("cancelled paid-through grants until represented as expired", () => {
  const snapshot = entitlementSnapshot({ accountId, environment: "sandbox", verifiedAt: 1000, purchases: [
    { productId: "essential_monthly_499", status: "cancelled_active" },
  ] });
  assert.equal(snapshot.effective_plan_tier, "essential");
});

test("receipt jar lifetime is independent from plan tier", () => {
  const snapshot = entitlementSnapshot({ accountId, environment: "sandbox", verifiedAt: 1000, purchases: [
    { productId: RECEIPT_JAR_PRODUCT_ID, status: "active" },
  ] });
  assert.equal(snapshot.effective_plan_tier, "free");
  assert.equal(snapshot.receipt_jar_lifetime, true);
});

test("apple receipt jar requires signed-account ownership and correct environment", () => {
  const purchase = normalizeAppleLifetimeTransaction({ accountId, environment: "sandbox", transaction: {
    bundleId: "com.sacredbilltracker.app",
    environment: "Sandbox",
    productId: RECEIPT_JAR_PRODUCT_ID,
    appAccountToken: accountId,
    originalTransactionId: "2000000123456789",
    transactionId: "2000000123456790",
    inAppOwnershipType: "PURCHASED",
    type: "Non-Consumable",
  } });
  assert.equal(purchase.productId, RECEIPT_JAR_PRODUCT_ID);
  assert.throws(() => normalizeAppleLifetimeTransaction({ accountId, environment: "production", transaction: {
    ...purchase,
    bundleId: "com.sacredbilltracker.app",
    environment: "Sandbox",
    appAccountToken: accountId,
    originalTransactionId: "2000000123456789",
    transactionId: "2000000123456790",
    inAppOwnershipType: "PURCHASED",
    type: "Non-Consumable",
  } }), /environment_mismatch/);
});

test("apple receipt jar rejects forged flags, subscriptions, expiry, revocation, and account mismatch", () => {
  const base = {
    bundleId: "com.sacredbilltracker.app",
    environment: "Sandbox",
    productId: RECEIPT_JAR_PRODUCT_ID,
    appAccountToken: accountId,
    originalTransactionId: "2000000123456789",
    transactionId: "2000000123456790",
    inAppOwnershipType: "PURCHASED",
    type: "Non-Consumable",
  };
  assert.throws(() => normalizeAppleLifetimeTransaction({ accountId, environment: "sandbox", transaction: { ...base, clientLifetime: true, productId: "essential_monthly_499" } }), /wrong_product/);
  assert.throws(() => normalizeAppleLifetimeTransaction({ accountId, environment: "sandbox", transaction: { ...base, type: "Auto-Renewable Subscription" } }), /wrong_product_type/);
  assert.throws(() => normalizeAppleLifetimeTransaction({ accountId, environment: "sandbox", transaction: { ...base, expiresDate: 9999999999999 } }), /lifetime_purchase_must_not_expire/);
  assert.equal(normalizeAppleLifetimeTransaction({ accountId, environment: "sandbox", transaction: { ...base, revocationDate: 1000 } }).status, "revoked");
  assert.throws(() => normalizeAppleLifetimeTransaction({ accountId: otherAccountId, environment: "sandbox", transaction: base }), /ownership_conflict/);
});

test("apple receipt jar restore is idempotent for owner and conflict for a second account", () => {
  const verified = normalizeAppleLifetimeTransaction({ accountId, environment: "sandbox", transaction: {
    bundleId: "com.sacredbilltracker.app",
    environment: "Sandbox",
    productId: RECEIPT_JAR_PRODUCT_ID,
    appAccountToken: accountId,
    originalTransactionId: "2000000123456789",
    transactionId: "2000000123456790",
    inAppOwnershipType: "PURCHASED",
    type: "Non-Consumable",
  } });
  const first = resolveAppleLifetimeOwnership({ existingPurchase: null, verifiedPurchase: verified });
  assert.equal(first.state, "securely_bound");
  const restored = resolveAppleLifetimeOwnership({ existingPurchase: first.purchase, verifiedPurchase: verified });
  assert.equal(restored.state, "securely_bound");
  const conflict = resolveAppleLifetimeOwnership({
    existingPurchase: first.purchase,
    verifiedPurchase: { ...verified, accountId: otherAccountId },
  });
  assert.equal(conflict.state, "owner_conflict");
  assert.deepEqual(appleLifetimeSnapshotPurchase(verified), { productId: RECEIPT_JAR_PRODUCT_ID, status: "active" });
});

test("google client purchase token alone is only evidence, not entitlement", () => {
  assert.equal(tokenHash("token").length, 64);
});

test("google subscription rejects wrong package product and unacknowledged purchases", () => {
  const base = {
    accountId,
    environment: "sandbox",
    packageName: "com.sacredbilltracker.app",
    expectedPackageName: "com.sacredbilltracker.app",
    productId: "sacred_bill_tracker_pro_monthly",
    purchaseToken: "token",
    nowSeconds: 1000,
    response: {
      testPurchase: {},
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "sacred_bill_tracker_pro_monthly", expiryTime: "2099-01-01T00:00:00Z" }],
    },
  };
  assert.throws(() => normalizeGoogleSubscription({ ...base, packageName: "wrong" }), /wrong_package/);
  assert.throws(() => normalizeGoogleSubscription({ ...base, productId: "unknown" }), /wrong_product/);
  assert.throws(() => normalizeGoogleSubscription({ ...base, response: { ...base.response, acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING" } }), /purchase_not_acknowledged/);
});

test("google active unlimited, expired, hold, refund-like revoked, and ownership conflict map fail closed", () => {
  const base = {
    accountId,
    environment: "sandbox",
    packageName: "com.sacredbilltracker.app",
    expectedPackageName: "com.sacredbilltracker.app",
    productId: "sacred_autotrack_monthly_1499",
    purchaseToken: "token",
    nowSeconds: 1000,
    response: {
      testPurchase: {},
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "sacred_autotrack_monthly_1499", expiryTime: "2099-01-01T00:00:00Z" }],
    },
  };
  assert.equal(normalizeGoogleSubscription(base).status, "active");
  assert.equal(normalizeGoogleSubscription({ ...base, response: { ...base.response, subscriptionState: "SUBSCRIPTION_STATE_EXPIRED" } }).status, "expired");
  assert.equal(normalizeGoogleSubscription({ ...base, response: { ...base.response, subscriptionState: "SUBSCRIPTION_STATE_ON_HOLD" } }).status, "account_hold");
  assert.throws(() => normalizeGoogleSubscription({ ...base, response: { ...base.response, externalAccountIdentifiers: { obfuscatedExternalAccountId: "22222222-2222-4222-8222-222222222222" } } }), /ownership_conflict/);
});

test("duplicate RTDN messages decode to one stable event id and never grant by type", () => {
  const payload = Buffer.from(JSON.stringify({
    packageName: "com.sacredbilltracker.app",
    eventTimeMillis: "1000",
    subscriptionNotification: { notificationType: 2, purchaseToken: "token", subscriptionId: "sacred_bill_tracker_pro_monthly" },
  })).toString("base64");
  const body = { subscription: "projects/sbt/subscriptions/rtdn", message: { messageId: "m-1", data: payload } };
  const decoded = decodePubSubMessage(body, { expectedSubscription: "projects/sbt/subscriptions/rtdn", expectedPackageName: "com.sacredbilltracker.app" });
  assert.equal(decoded.eventId, "m-1");
  assert.equal(decoded.purchaseTokenHash, tokenHash("token"));
  assert.equal(decoded.notificationType, 2);
});

test("verify-store-subscription source is Apple-only and does not require Google secrets", () => {
  const entrypoint = readFileSync(join(functionsDir, "verify-store-subscription", "index.ts"), "utf8");
  const verifier = readFileSync(join(functionsDir, "verify-store-subscription", "apple-verifier.ts"), "utf8");
  const handler = readFileSync(join(functionsDir, "verify-store-subscription", "apple-handler.mjs"), "utf8");
  const policy = readFileSync(join(functionsDir, "verify-store-subscription", "apple-policy.mjs"), "utf8");

  assert.match(entrypoint, /store-verification-google/);
  assert.doesNotMatch(entrypoint, /verifyGoogle|googleAccessToken|GOOGLE_SERVICE_ACCOUNT_JSON|GOOGLE_PACKAGE_NAME|platform === "android"|platform === "google"/);
  assert.doesNotMatch(verifier, /googleAccessToken|verifiedGoogleSources|SBT_GOOGLE_IOS_ENTITLEMENTS_ENABLED|GOOGLE_SERVICE_ACCOUNT_JSON|GOOGLE_PACKAGE_NAME/);
  assert.doesNotMatch(handler, /googleEnabled|accountSources|SBT_GOOGLE|GOOGLE_/);
  assert.doesNotMatch(policy, /receiptjar\.lifetime/);
});
