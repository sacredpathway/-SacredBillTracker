// Only enumerated, non-personal outcomes leave this module. Never log errors,
// bodies, account identifiers, tokens, receipts, or provider response payloads.
const reasons=new Set(['claim_success','claim_repeated','claim_failure','owner_conflict','tombstone',
 'legacy_ownership_unresolved','claims_disabled','inactive_unbound','environment_mismatch',
 'expired','revoked','verification_rejected','verification_failure','snapshot_success','snapshot_failure']);
export function operationalSignals({write=console.info,requestID=crypto.randomUUID(),environment='production'}={}) {
 return reason=>{
  if(!reasons.has(reason)) return;
  write(JSON.stringify({event:'entitlement_verification',request_id:requestID,
   environment:['production','sandbox'].includes(environment)?environment:'invalid',reason}));
 };
}
export const googleCrossPlatformEnabled=value=>value==='true';
