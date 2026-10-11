import {VerificationRejected} from './apple-policy.mjs';
export async function bindVerifiedApple(db,{account,original,environment,transaction,active,allowNew=false,signal=()=>{}}) {
 // This function is called only after Apple signature/identity/state validation.
 const {data,error}=await db.rpc('sbt_bind_verified_apple',{p_owner:account,p_environment:environment.toLowerCase(),
  p_original:original,p_account_token:transaction.appAccountToken??null,p_active:active,
  p_evidence_ref:`apple-signed-token:${environment.toLowerCase()}:${transaction.transactionId}`,
  p_allow_new:allowNew});
 if(error || !data || !['securely_bound','legacy_ownership_unresolved','claims_disabled','inactive_unbound',
   'owner_conflict','tombstone','verification_rejected'].includes(data.state)) {
  signal('claim_failure');throw Error('Binding service unavailable');
 }
 if(['owner_conflict','tombstone','verification_rejected'].includes(data.state)) {
  signal(data.state);throw new VerificationRejected(data.state);
 }
 signal(data.state==='securely_bound'?(data.new_claim?'claim_success':'claim_repeated'):data.state);
 return data.state;
}
