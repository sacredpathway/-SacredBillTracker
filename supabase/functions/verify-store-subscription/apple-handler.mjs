import {bindVerifiedApple} from './apple-binding.mjs';
import {APP, PRODUCTS, currentAppleEntitlement, makeSnapshot, VerificationRejected} from './apple-policy.mjs';
import {normalizeAppleLifetimeTransaction} from '../_shared/apple-lifetime-policy.mjs';
import {RECEIPT_JAR_PRODUCT_ID} from '../_shared/entitlement-engine.mjs';
const Environment = {PRODUCTION:'Production',SANDBOX:'Sandbox'};

async function sha256Hex(input) {
 const bytes = new TextEncoder().encode(input);
 const digest = await crypto.subtle.digest('SHA-256', bytes);
 return [...new Uint8Array(digest)].map((b)=>b.toString(16).padStart(2,'0')).join('');
}

function lowerEnvironment(environment) {
 return environment === Environment.SANDBOX ? 'sandbox' : 'production';
}

function receiptJarSnapshot({user, environment, effective, verifiedAt, state}) {
 return {version:1,account_id:user.id.toLowerCase(),bundle_id:APP,environment:lowerEnvironment(environment),
  verified_at:verifiedAt,effective_plan_tier:effective?.effective_plan_tier ?? 'free',
  receipt_jar_lifetime:effective?.receipt_jar_lifetime === true,has_conflict:effective?.has_conflict === true,
  ownership_resolution:state === 'owner_conflict' ? 'owner_conflict' : effective?.has_conflict ? 'quarantined' : 'securely_bound'};
}

async function verifiedReceiptJarTransaction({body, clients, environment}) {
 if (typeof body.signed_transaction_jws === 'string' && body.signed_transaction_jws.split('.').length === 3) {
  return await clients.signatures.verifyAndDecodeSignedTransaction(body.signed_transaction_jws);
 }
 const transactionId = String(body.transaction_id ?? body.original_transaction_id ?? '');
 if (!/^\d{1,64}$/.test(transactionId)) throw new VerificationRejected('invalid_receipt_jar_transaction_id');
 if (!clients.api?.getTransactionInfo) throw new Error('Apple transaction lookup unavailable');
 const response = await clients.api.getTransactionInfo(transactionId);
 const signed = response?.signedTransactionInfo;
 if (typeof signed !== 'string') throw new Error('Apple transaction lookup unavailable');
 const tx = await clients.signatures.verifyAndDecodeSignedTransaction(signed);
 if(tx.environment !== environment) throw new VerificationRejected('environment_mismatch');
 return tx;
}

async function verifyReceiptJar(user, body, db, {clients: appleClients, clock, respond: json, signal}) {
 if (user.is_anonymous) return json({error:'authenticated_account_required'},403);
 const requestedEnvironment = body.environment || 'production';
 if (!['production','sandbox'].includes(requestedEnvironment)) return json({error:'invalid_environment'},400);
 const environment = requestedEnvironment === 'sandbox' ? Environment.SANDBOX : Environment.PRODUCTION;
 try {
  const clients = appleClients(environment);
  const tx = await verifiedReceiptJarTransaction({body, clients, environment});
  const now = clock();
  let purchase;
  try {
   purchase = normalizeAppleLifetimeTransaction({accountId:user.id,environment:requestedEnvironment,transaction:tx,nowSeconds:now/1000});
  } catch {
   throw new VerificationRejected('Receipt Jar identity or state rejected');
  }
  const eventMs = purchase.eventTimeSeconds * 1000;
  const eventId = `apple-receipt-jar:${purchase.environment}:${purchase.providerOriginalId}:${purchase.providerTransactionId}:${purchase.status}:${eventMs}`;
  const payloadHash = await sha256Hex(JSON.stringify({transaction:tx,status:purchase.status,eventId}));
  const {data,error}=await db.rpc('sbt_record_verified_receipt_jar_purchase',{
   p_account_id:user.id,p_provider:'apple',p_environment:purchase.environment,p_product_id:purchase.productId,
   p_provider_original_id:purchase.providerOriginalId,p_provider_latest_id:purchase.providerTransactionId,
   p_status:purchase.status,p_event_id:eventId,p_event_type:`RECEIPT_JAR_${purchase.status.toUpperCase()}`,
   p_event_time:new Date(eventMs).toISOString(),p_verified_at:new Date(now).toISOString(),
   p_raw_payload_hash:payloadHash,p_account_token:tx.appAccountToken??null
  });
  if(error) throw Error('Receipt Jar persistence unavailable');
  const state = data?.state ?? 'verification_rejected';
  const effective = data?.effective;
  const snapshot = receiptJarSnapshot({user,environment,effective,verifiedAt:now/1000,state});
  if(state === 'owner_conflict') return json({error:'purchase_ownership_conflict',verification_state:'rejected',
   platform:'ios',product_id:RECEIPT_JAR_PRODUCT_ID,status:purchase.status,receipt_jar_lifetime:false,
   entitlement_snapshot:{...snapshot,receipt_jar_lifetime:false,ownership_resolution:'owner_conflict'}},409);
  if(state === 'verification_rejected') throw new VerificationRejected('Receipt Jar persistence rejected');
  signal(`receipt_jar_${state}`);
  return json({verification_state:'verified',platform:'ios',product_id:RECEIPT_JAR_PRODUCT_ID,status:purchase.status,
   receipt_jar_lifetime:snapshot.receipt_jar_lifetime,ownership_resolution:snapshot.ownership_resolution,
   entitlement_snapshot:snapshot,store_resolution:state});
 } catch (error) {
  signal(error instanceof VerificationRejected && error.code==='environment_mismatch'?'environment_mismatch':'receipt_jar_verification_failure');
  return error instanceof VerificationRejected ? json({error:'receipt_jar_identity_or_state_rejected',verification_state:'rejected'},403)
   : json({error:'apple_verification_unavailable',verification_state:'unavailable'},503);
 }
}

export async function verifyAppleRequest(user, body, db, {clients: appleClients, clock = Date.now, respond: json, allowNewClaims=false, signal=()=>{}}) {
 if (user.is_anonymous) return json({error:'authenticated_account_required'},403);
 const receiptJarMode = body.operation === 'receipt_jar_lifetime' || body.product_id === RECEIPT_JAR_PRODUCT_ID;
 if (receiptJarMode) return await verifyReceiptJar(user, body, db, {clients:appleClients, clock, respond:json, signal});
 const snapshotMode = body.operation === 'entitlement_snapshot';
 const requestedEnvironment = body.environment || 'production';
 if (!['production','sandbox'].includes(requestedEnvironment) || (!snapshotMode && requestedEnvironment !== 'production')) return json({error:'invalid_environment'},400);
 const environment = requestedEnvironment === 'sandbox' ? Environment.SANDBOX : Environment.PRODUCTION;
 if (body.operation && !snapshotMode) return json({error:'invalid_operation'},400);
 const requested = snapshotMode ? body.original_transaction_ids : [body.original_transaction_id];
 if (!Array.isArray(requested) || requested.length > 32 || requested.some(id=>typeof id!=='string'||!/^\d{1,64}$/.test(id)))
  return json({error:'invalid_original_transaction_ids'},400);
 try {
  const {data: known,error} = await db.from('subscriptions').select('original_transaction_id')
   .eq('owner_id',user.id).eq('platform','ios_appstore').eq('is_sandbox',environment === Environment.SANDBOX);
  if (error) throw Error('Subscription lookup unavailable');
  const {data:bindings,error:bindingError}=snapshotMode ? await db.from('sbt_reviewed_purchase_bindings').select('store_key')
   .eq('owner_id',user.id).eq('platform','ios_appstore').eq('environment',requestedEnvironment) : {data:[],error:null};
  if(bindingError) throw Error('Legacy discovery unavailable');
  const ids = [...new Set([...requested,...(bindings||[]).map(r=>r.store_key).filter(Boolean),...(snapshotMode ? (known || []).map((r)=>r.original_transaction_id).filter(Boolean) : [])])];
  if (ids.length > 32) throw Error('Subscription reconciliation limit exceeded');
  const clients = appleClients(environment);
  const results = [];
  for (const original of ids) {
   const r=await currentAppleEntitlement({...clients,account:user.id,original,environment,clock,
    authorizeBinding:args=>bindVerifiedApple(db,{...args,allowNew:allowNewClaims,signal})});
   if(r.resolution==='claims_disabled') throw Error('New bindings paused');
   if(['expired','revoked'].includes(r.storeState)) signal(r.storeState);
   results.push(r);
  }
  // Unresolved sources are explicitly ineligible, never cached as purchases.
  // Every returned eligible source has been freshly and independently verified.
  const eligible=results.filter(r=>r.entitlement);
  const unresolved=results.some(r=>['legacy_ownership_unresolved','claims_disabled'].includes(r.resolution));
  const metadata={ownership_resolution:unresolved?'legacy_ownership_unresolved':eligible.length?'securely_bound':'unbound',
   entitlement_state:eligible.some(r=>['active','trial','grace'].includes(r.entitlement.status))?'entitled':
    results.some(r=>['expired','revoked','on_hold'].includes(r.storeState))?'expired_or_revoked':'free',
   verification_state:'verified'};
  // All rows must be verified before an app-wide snapshot can replace a cache.
  // A timeout, unknown state, invalid signature or ownership mismatch is never FREE.
  if (snapshotMode) {
   // Preserve existing verified referral/reward access without pretending it is
   // a StoreKit purchase. It has its own explicit expiry inside the same envelope.
   const {data: rewards,error: rewardError} = await db.from('reward_entitlements').select('tier,expires_at')
    .eq('owner_id',user.id).is('revoked_at',null).gt('expires_at',new Date(clock()).toISOString());
   if (rewardError) throw Error('Reward verification unavailable');
   const snapshot=makeSnapshot(user.id,eligible,clock(),environment);
   if((rewards||[]).some(r=>Date.parse(r.expires_at)>clock())) metadata.entitlement_state='entitled';
   signal('snapshot_success');
   return json({...snapshot,...metadata, account_sources:[], rewards:(rewards||[]).map((r)=>({tier:r.tier,expires_at:Date.parse(r.expires_at)/1000}))});
  }
  if(!eligible.length) return json({error:'purchase_account_verification_required',...metadata},403);
  const r = eligible[0], tx = r.transaction, renewal = r.renewal;
  if (body.product_id && body.product_id !== tx.productId) throw new VerificationRejected('Product mismatch');
  // Do not mutate another account's pre-existing lineage, even if a legacy
  // row conflicts with the newly verified token. That requires reconciliation.
  const {data: existing,error: ownershipError} = await db.from('subscriptions').select('owner_id')
   .eq('original_transaction_id',tx.originalTransactionId).maybeSingle();
  if (ownershipError) throw Error('Ownership lookup unavailable');
  if (existing && existing.owner_id !== user.id) throw new VerificationRejected('Existing ownership mismatch');
  // Never reach the legacy RPC's unmapped-product fallback.
  const {data: registered,error: registryError} = await db.from('subscription_products').select('feature_key')
   .eq('platform','ios_appstore').eq('store_product_id',tx.productId).limit(1);
  if (registryError || !registered?.length || !PRODUCTS.has(tx.productId)) throw Error('Product registry unavailable');
  const status = r.entitlement.status === 'trial' ? 'active' : r.entitlement.status === 'grace' ? 'in_grace_period' : r.entitlement.status;
  const {error: writeError} = await db.rpc('record_verified_subscription', {
   p_owner_id:user.id,p_platform:'ios_appstore',p_store_product_id:tx.productId,p_status:status,
   p_current_period_end:new Date(tx.expiresDate).toISOString(),p_auto_renew:renewal?.autoRenewStatus===1,
   p_is_sandbox:false,p_original_transaction_id:tx.originalTransactionId,p_latest_transaction_id:tx.transactionId,
   p_purchase_token:null,p_grace_period_end:r.entitlement.status==='grace'?new Date(r.entitlement.expires_at*1000).toISOString():null,
   p_current_period_start:tx.purchaseDate?new Date(tx.purchaseDate).toISOString():null,p_canceled_at:null,
   p_raw_payload:{transaction:tx,renewal:renewal||{},status:r.entitlement.status}
  });
  if (writeError) throw Error('Subscription persistence unavailable');
  return json({...metadata,platform:'ios',status,product_id:tx.productId,auto_renew:renewal?.autoRenewStatus===1,
   expires_at:new Date(tx.expiresDate).toISOString(),sandbox:false,entitlement_snapshot:makeSnapshot(user.id,eligible,clock(),environment)});
 } catch (error) {
  signal(error instanceof VerificationRejected && error.code==='environment_mismatch'?'environment_mismatch':'verification_failure');
  if(snapshotMode) signal('snapshot_failure');
  // Do not return Apple responses, keys, signatures, tokens or stack traces.
  return error instanceof VerificationRejected ? json({error:'subscription_identity_or_state_rejected',verification_state:'rejected'},403)
   : json({error:'apple_verification_unavailable',verification_state:'unavailable'},503);
 }
}
