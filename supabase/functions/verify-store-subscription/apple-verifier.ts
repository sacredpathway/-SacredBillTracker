import {operationalSignals} from './operational.mjs';
import {AppStoreServerAPIClient, SignedDataVerifier, Environment} from 'npm:@apple/app-store-server-library@3.1.0';
import {Buffer} from 'node:buffer';
import roots from './apple_roots.mjs';
import {APP} from './apple-policy.mjs';
import {verifyAppleRequest} from './apple-handler.mjs';
import {json} from './shared.ts';

function appleClients(environment: Environment) {
 const key = Deno.env.get('APPLE_PRIVATE_KEY')?.trim().replace(/\\n/g,'\n');
 const keyID = Deno.env.get('APPLE_KEY_ID')?.trim();
 const issuer = Deno.env.get('APPLE_ISSUER_ID')?.trim();
 if (!key || !keyID || !issuer || Deno.env.get('APPLE_BUNDLE_ID')?.trim() !== APP) throw Error('Apple configuration unavailable');
 // Explicit environment only: no probing/fallback. Sandbox snapshots never write production state.
 return {api:new AppStoreServerAPIClient(key,keyID,issuer,APP,environment),
  signatures:new SignedDataVerifier(roots.map(r=>Buffer.from(r,'base64')),true,environment,APP,6762890363)};
}
export async function verifyApple(user: {id:string; is_anonymous?:boolean}, body: any, db: any) {
 return verifyAppleRequest(user,body,db,{clients:appleClients,respond:json,
  allowNewClaims:Deno.env.get('SBT_APPLE_NEW_BINDINGS_ENABLED')==='true',
  signal:operationalSignals({environment:body.environment||'production'})});
}
