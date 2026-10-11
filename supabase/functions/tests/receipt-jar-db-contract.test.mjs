import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { entitlementSnapshot, RECEIPT_JAR_PRODUCT_ID } from "../_shared/entitlement-engine.mjs";

const accountA = "11111111-1111-4111-8111-111111111111";
const accountB = "22222222-2222-4222-8222-222222222222";
const migrationPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "..",
  "SacredBillTracker",
  "staging_only_receipt_jar_lifetime_contract_proposal.sql",
);
const migrationSql = readFileSync(migrationPath, "utf8");

function applyEvent(state, event) {
  const eventKey = `${event.provider}:${event.environment}:${event.eventId}`;
  if (state.events.has(eventKey)) return { state, result: "duplicate" };
  state.events.add(eventKey);

  const purchaseKey = `${event.provider}:${event.environment}:${event.originalId}`;
  const existing = state.purchases.get(purchaseKey);
  if (event.accountToken && event.accountToken !== event.accountId) return { state, result: "owner_conflict" };
  if (existing && existing.accountId !== event.accountId) return { state, result: "owner_conflict" };
  if (existing && existing.eventTime > event.eventTime) return { state, result: "ignored_out_of_order" };

  state.purchases.set(purchaseKey, {
    accountId: event.accountId,
    provider: event.provider,
    environment: event.environment,
    originalId: event.originalId,
    productId: event.productId,
    status: event.status,
    eventTime: event.eventTime,
  });
  return { state, result: "securely_bound" };
}

function effective(state, accountId, planPurchase) {
  const purchases = [...state.purchases.values()]
    .filter((purchase) => purchase.accountId === accountId && purchase.status === "active")
    .map((purchase) => ({ productId: purchase.productId, status: purchase.status }));
  if (planPurchase) purchases.push(planPurchase);
  return entitlementSnapshot({ accountId, environment: "sandbox", verifiedAt: 1000, purchases });
}

function receiptEvent(overrides = {}) {
  return {
    accountId: accountA,
    accountToken: accountA,
    provider: "apple",
    environment: "sandbox",
    eventId: "apple-event-1",
    originalId: "2000000123456789",
    productId: RECEIPT_JAR_PRODUCT_ID,
    status: "active",
    eventTime: 100,
    ...overrides,
  };
}

test("migration proposal is additive staging-only SQL with service-only authoritative RPCs", () => {
  assert.match(migrationSql, /current_setting\('sbt\.staging_project_ref'/);
  assert.match(migrationSql, /thwjnpofhrpxfuvwkfgd/);
  assert.doesNotMatch(migrationSql, /zziauybwemoiqfpidiur/);
  assert.doesNotMatch(migrationSql, /\\bdrop\\s+/i);
  assert.doesNotMatch(migrationSql, /\\bcascade\\b/i);
  assert.match(migrationSql, /create table if not exists public\.sbt_store_purchases/);
  assert.match(migrationSql, /create table if not exists public\.sbt_store_events/);
  assert.match(migrationSql, /create table if not exists public\.sbt_effective_entitlements/);
  assert.match(migrationSql, /create or replace function public\.sbt_record_verified_receipt_jar_purchase/);
  assert.match(migrationSql, /revoke all on function public\.sbt_record_verified_receipt_jar_purchase/);
  assert.match(migrationSql, /grant execute on function public\.sbt_record_verified_receipt_jar_purchase[\s\S]+to service_role/);
  assert.doesNotMatch(migrationSql, /grant execute on function public\.sbt_record_verified_receipt_jar_purchase[\s\S]+to authenticated/);
});

test("verified Apple Receipt Jar grants lifetime without granting a plan", () => {
  const state = { events: new Set(), purchases: new Map() };
  assert.equal(applyEvent(state, receiptEvent()).result, "securely_bound");
  const snapshot = effective(state, accountA);
  assert.equal(snapshot.receipt_jar_lifetime, true);
  assert.equal(snapshot.effective_plan_tier, "free");
});

test("Unlimited and Receipt Jar can coexist independently", () => {
  const state = { events: new Set(), purchases: new Map() };
  applyEvent(state, receiptEvent());
  const snapshot = effective(state, accountA, { productId: "unlimited_monthly_1499", status: "active" });
  assert.equal(snapshot.receipt_jar_lifetime, true);
  assert.equal(snapshot.effective_plan_tier, "unlimited");
});

test("expired subscription does not remove Receipt Jar lifetime", () => {
  const state = { events: new Set(), purchases: new Map() };
  applyEvent(state, receiptEvent());
  const snapshot = effective(state, accountA, { productId: "unlimited_monthly_1499", status: "expired" });
  assert.equal(snapshot.receipt_jar_lifetime, true);
  assert.equal(snapshot.effective_plan_tier, "free");
});

test("duplicate transaction and duplicate event are deterministic", () => {
  const state = { events: new Set(), purchases: new Map() };
  assert.equal(applyEvent(state, receiptEvent()).result, "securely_bound");
  assert.equal(applyEvent(state, receiptEvent()).result, "duplicate");
  assert.equal(applyEvent(state, receiptEvent({ eventId: "apple-event-2", eventTime: 101 })).result, "securely_bound");
  assert.equal(effective(state, accountA).receipt_jar_lifetime, true);
});

test("second account and email equality cannot transfer ownership", () => {
  const state = { events: new Set(), purchases: new Map() };
  applyEvent(state, receiptEvent());
  const conflict = applyEvent(state, receiptEvent({
    accountId: accountB,
    accountToken: accountB,
    eventId: "apple-event-3",
    eventTime: 102,
    verifiedEmail: "same@example.com",
  }));
  assert.equal(conflict.result, "owner_conflict");
  assert.equal(effective(state, accountA).receipt_jar_lifetime, true);
  assert.equal(effective(state, accountB).receipt_jar_lifetime, false);
});

test("refund and revocation remove lifetime grant", () => {
  for (const status of ["refunded", "revoked"]) {
    const state = { events: new Set(), purchases: new Map() };
    applyEvent(state, receiptEvent());
    applyEvent(state, receiptEvent({ eventId: `apple-event-${status}`, status, eventTime: 200 }));
    assert.equal(effective(state, accountA).receipt_jar_lifetime, false);
  }
});

test("stale active event cannot override newer revocation", () => {
  const state = { events: new Set(), purchases: new Map() };
  applyEvent(state, receiptEvent({ eventId: "revocation", status: "revoked", eventTime: 300 }));
  assert.equal(applyEvent(state, receiptEvent({ eventId: "late-active", status: "active", eventTime: 200 })).result, "ignored_out_of_order");
  assert.equal(effective(state, accountA).receipt_jar_lifetime, false);
});
