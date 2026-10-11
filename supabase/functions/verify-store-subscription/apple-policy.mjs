// Pure interpretation of SDK-verified CURRENT Apple server state. No decoding of
// client JWS, client tier, client timestamps, or auto-renew intent grants access.
export const APP = 'com.sacredbilltracker.app';
export const PRODUCTS = new Set(['essential_monthly_499','business_monthly_999','unlimited_monthly_1499',
 'com.sacredbilltracker.app.pro.monthly','com.sacredbilltracker.app.pro.yearly','sacred_focus_plus_monthly',
 'com.sacredbilltracker.app.autotrack.monthly','com.sacredbilltracker.app.autotrack.annual']);
export class VerificationRejected extends Error { constructor(code='verification_rejected') { super(code); this.code=code; } }
const reject = () => { throw new VerificationRejected('Apple subscription identity or state rejected'); };
export function resolveApple({account, original, status, transaction: tx, renewal, now, environment = 'Production', legacyOwner}) {
 if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(account) || !/^\d{1,64}$/.test(original)) reject();
 if (!['Production','Sandbox'].includes(environment) || !Number.isFinite(now) || now <= 0 || !tx || tx.bundleId !== APP || tx.environment !== environment ||
     (tx.appAccountToken?.toLowerCase() !== account.toLowerCase() && !(tx.appAccountToken == null && legacyOwner === account)) || tx.originalTransactionId !== original ||
     !/^\d{1,64}$/.test(tx.transactionId || '') || !PRODUCTS.has(tx.productId) ||
     tx.inAppOwnershipType !== 'PURCHASED' || ![1,2,3,4,5].includes(status)) reject();
 if (!Number.isFinite(tx.signedDate) || tx.signedDate <= 0 || tx.signedDate > now + 300_000) reject();
 let expires = tx.expiresDate;
 if (!Number.isFinite(expires) || expires <= 0) reject();
 const revoked = status === 5 || tx.revocationDate != null;
 let state = revoked ? 'revoked' : 'expired';
 if (!revoked && !tx.isUpgraded) {
  if (status === 1 && expires > now) state = tx.offerType === 1 && tx.price === 0 ? 'trial' : 'active';
  if (status === 3) state = 'on_hold';
  if (status === 4) {
   if (!renewal || renewal.originalTransactionId !== original || renewal.productId !== tx.productId ||
       renewal.environment !== environment || !Number.isFinite(renewal.gracePeriodExpiresDate) ||
       renewal.gracePeriodExpiresDate <= 0) reject();
   expires = renewal.gracePeriodExpiresDate;
   if (expires > now) state = 'grace';
  }
 }
 return {product_id:tx.productId,original_transaction_id:original,transaction_id:tx.transactionId,
         status:state,expires_at:expires / 1000,revoked,source_platform:'ios_appstore',binding_state:legacyOwner?'reviewed':'signed_account_token'};
}
export async function currentAppleEntitlement({api, signatures, account, original, clock = Date.now, environment = 'Production', authorizeLegacy, checkBinding, authorizeBinding}) {
 const response = await api.getAllSubscriptionStatuses(original);
 if (response.environment !== environment) throw new VerificationRejected('environment_mismatch');
 if (response.bundleId !== APP) reject();
 const matches = [];
 for (const group of response.data || []) for (const item of group.lastTransactions || []) {
  const tx = await signatures.verifyAndDecodeSignedTransaction(item.signedTransactionInfo);
  if (tx.originalTransactionId === original) matches.push({item, tx});
 }
 if (matches.length !== 1) reject();
 const {item, tx} = matches[0];
 const renewal = item.signedRenewalInfo ? await signatures.verifyAndDecodeRenewalInfo(item.signedRenewalInfo) : undefined;
 const now = clock();
 if(tx.environment !== environment) throw new VerificationRejected('environment_mismatch');
 if(authorizeBinding) {
  const entitlement=resolveApple({account,original,status:item.status,transaction:tx,renewal,now,environment,
   legacyOwner:tx.appAccountToken==null?account:undefined});
  const binding=await authorizeBinding({account,original,environment,transaction:tx,
   active:['active','trial','grace'].includes(entitlement.status)&&!entitlement.revoked});
  if(binding!=='securely_bound') return {entitlement:null,resolution:binding,storeState:entitlement.status,verifiedAt:now/1000};
  entitlement.binding_state=tx.appAccountToken==null?'reviewed':'signed_account_token';
  return {entitlement,transaction:tx,renewal,resolution:binding,storeState:entitlement.status,verifiedAt:now/1000};
 }
 if(checkBinding) await checkBinding();
 let legacyOwner;
 if(tx.appAccountToken == null && authorizeLegacy) {
  const checked=resolveApple({account,original,status:item.status,transaction:tx,renewal,now,environment,legacyOwner:account});
  await authorizeLegacy({account,original,environment,active:['active','trial','grace'].includes(checked.status)&&!checked.revoked});
  legacyOwner=account;
 }
 return {entitlement:resolveApple({account,original,status:item.status,transaction:tx,renewal,now,environment,legacyOwner}),
         transaction:tx,renewal,verifiedAt:now / 1000};
}
export function makeSnapshot(account, results, now, environment = 'Production') {
 if (!Number.isFinite(now) || now <= 0 || results.some(r=>!Number.isFinite(r.verifiedAt)||r.verifiedAt<=0||r.verifiedAt>now/1000)) reject();
 const verifiedAt = Math.min(now/1000,...results.map(r=>r.verifiedAt));
 return {version:1,account_id:account.toLowerCase(),bundle_id:APP,environment:environment.toLowerCase(),
         verified_at:verifiedAt,entitlements:results.map(r => r.entitlement)};
}
