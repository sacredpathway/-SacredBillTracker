export function b64url(bytes: Uint8Array) {
  let s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlFromStr(s: string) { return b64url(new TextEncoder().encode(s)); }

export function decodeJwsPayload(jws: string) {
  const mid = jws.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(mid));
}

function pemToDer(pem: string) {
  const b64 = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function appleJwt(opts: {privateKeyPem: string; keyId: string; issuerId: string; bundleId: string}) {
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(opts.privateKeyPem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: opts.keyId, typ: "JWT" };
  const payload = { iss: opts.issuerId, iat: now, exp: now + 600, aud: "appstoreconnect-v1", bid: opts.bundleId };
  const signingInput = `${b64urlFromStr(JSON.stringify(header))}.${b64urlFromStr(JSON.stringify(payload))}`;
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)));
  return `${signingInput}.${b64url(sig)}`;
}
