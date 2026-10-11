import assert from "node:assert/strict";
import test from "node:test";
import { verifyAppleRequest } from "../verify-store-subscription/apple-handler.mjs";
import { RECEIPT_JAR_PRODUCT_ID } from "../_shared/entitlement-engine.mjs";

const accountId = "11111111-1111-4111-8111-111111111111";
const otherAccountId = "22222222-2222-4222-8222-222222222222";

function baseTransaction(overrides = {}) {
  return {
    bundleId: "com.sacredbilltracker.app",
    environment: "Sandbox",
    productId: RECEIPT_JAR_PRODUCT_ID,
    appAccountToken: accountId,
    originalTransactionId: "2000000123456789",
    transactionId: "2000000123456790",
    inAppOwnershipType: "PURCHASED",
    type: "Non-Consumable",
    purchaseDate: 1000000,
    signedDate: 1001000,
    ...overrides,
  };
}

function makeDb({ state = "securely_bound", effective, calls = [] } = {}) {
  return {
    calls,
    rpc(name, args) {
      calls.push({ name, args });
      if (name === "record_verified_subscription") return { error: new Error("subscription path should not be called") };
      assert.equal(name, "sbt_record_verified_receipt_jar_purchase");
      return {
        data: {
          state,
          effective: effective ?? {
            account_id: accountId,
            effective_plan_tier: "free",
            receipt_jar_lifetime: state !== "owner_conflict" && args.p_status === "active",
            has_conflict: false,
          },
        },
        error: null,
      };
    },
  };
}

function makeClients(transaction = baseTransaction()) {
  return () => ({
    api: {
      async getTransactionInfo(id) {
        assert.equal(id, transaction.transactionId);
        return { signedTransactionInfo: "header.payload.signature" };
      },
    },
    signatures: {
      async verifyAndDecodeSignedTransaction(jws) {
        assert.equal(jws, "header.payload.signature");
        return transaction;
      },
    },
  });
}

function responseCollector() {
  const seen = [];
  const respond = (body, status = 200) => {
    seen.push({ body, status });
    return { body, status };
  };
  return { seen, respond };
}

async function verify({ transaction = baseTransaction(), db = makeDb(), body = {}, user = { id: accountId } } = {}) {
  const { respond } = responseCollector();
  return await verifyAppleRequest(user, {
    platform: "apple",
    operation: "receipt_jar_lifetime",
    environment: "sandbox",
    product_id: RECEIPT_JAR_PRODUCT_ID,
    transaction_id: transaction.transactionId,
    ...body,
  }, db, { clients: makeClients(transaction), clock: () => 2_000_000, respond });
}

test("verified Receipt Jar invokes lifetime persistence contract and not subscription persistence", async () => {
  const calls = [];
  const result = await verify({ db: makeDb({ calls }) });
  assert.equal(result.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "sbt_record_verified_receipt_jar_purchase");
  assert.equal(calls[0].args.p_product_id, RECEIPT_JAR_PRODUCT_ID);
  assert.equal(calls[0].args.p_status, "active");
  assert.equal(result.body.receipt_jar_lifetime, true);
  assert.equal(result.body.entitlement_snapshot.effective_plan_tier, "free");
});

test("Receipt Jar requires no expiration and grants no plan tier", async () => {
  const result = await verify();
  assert.equal(result.body.entitlement_snapshot.receipt_jar_lifetime, true);
  assert.equal(result.body.entitlement_snapshot.effective_plan_tier, "free");
  assert.equal(result.body.expires_at, undefined);
});

test("duplicate and restore-to-same-account outcomes return authoritative lifetime result", async () => {
  for (const state of ["duplicate", "securely_bound"]) {
    const result = await verify({ db: makeDb({ state }) });
    assert.equal(result.status, 200);
    assert.equal(result.body.store_resolution, state);
    assert.equal(result.body.receipt_jar_lifetime, true);
  }
});

test("ownership conflict does not grant or transfer", async () => {
  const result = await verify({
    db: makeDb({ state: "owner_conflict", effective: { effective_plan_tier: "free", receipt_jar_lifetime: false, has_conflict: true } }),
  });
  assert.equal(result.status, 409);
  assert.equal(result.body.error, "purchase_ownership_conflict");
  assert.equal(result.body.entitlement_snapshot.receipt_jar_lifetime, false);
});

test("refund and revocation remove lifetime", async () => {
  for (const tx of [
    baseTransaction({ revocationDate: 1_500_000, revocationReason: 1 }),
    baseTransaction({ revocationDate: 1_500_000, revocationReason: 0 }),
  ]) {
    const calls = [];
    const result = await verify({ transaction: tx, db: makeDb({ calls, effective: { effective_plan_tier: "free", receipt_jar_lifetime: false, has_conflict: false } }) });
    assert.equal(result.status, 200);
    assert.equal(result.body.receipt_jar_lifetime, false);
    assert.match(calls[0].args.p_status, /refunded|revoked/);
  }
});

test("stale active event cannot restore lifetime", async () => {
  const result = await verify({
    db: makeDb({ state: "ignored_out_of_order", effective: { effective_plan_tier: "free", receipt_jar_lifetime: false, has_conflict: false } }),
  });
  assert.equal(result.status, 200);
  assert.equal(result.body.store_resolution, "ignored_out_of_order");
  assert.equal(result.body.receipt_jar_lifetime, false);
});

test("invalid evidence cannot reach persistence", async () => {
  const calls = [];
  const { respond } = responseCollector();
  const result = await verifyAppleRequest({ id: accountId }, {
    platform: "apple",
    operation: "receipt_jar_lifetime",
    environment: "sandbox",
    product_id: RECEIPT_JAR_PRODUCT_ID,
    signed_transaction_jws: "not-a-jws",
  }, makeDb({ calls }), { clients: makeClients(), clock: () => 2_000_000, respond });
  assert.equal(result.status, 403);
  assert.equal(calls.length, 0);
});

test("wrong bundle, environment, unknown product, and forged lifetime flag cannot reach persistence", async () => {
  for (const transaction of [
    baseTransaction({ bundleId: "com.example.wrong" }),
    baseTransaction({ environment: "Production" }),
    baseTransaction({ productId: "essential_monthly_499", clientLifetime: true }),
  ]) {
    const calls = [];
    const result = await verify({ transaction, db: makeDb({ calls }) });
    assert.equal(result.status, 403);
    assert.equal(calls.length, 0);
  }
});

test("wrong account token is rejected before persistence", async () => {
  const calls = [];
  const result = await verify({ transaction: baseTransaction({ appAccountToken: otherAccountId }), db: makeDb({ calls }) });
  assert.equal(result.status, 403);
  assert.equal(calls.length, 0);
});
