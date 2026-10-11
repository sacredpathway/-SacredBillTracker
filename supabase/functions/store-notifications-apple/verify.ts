import * as jose from "jose";
import { X509 } from "jsrsasign";
import { assertValidityWindow, validateJwsHeader } from "./validation.ts";

const APP_STORE_RECEIPT_SIGNING_OID = "1.2.840.113635.100.6.11.1";
const APPLE_WWDR_INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";
const ACCEPTED_SIGNATURE_ALGORITHMS = new Set([
  "SHA256withECDSA",
  "SHA384withECDSA",
]);
const KNOWN_CRITICAL_EXTENSIONS = new Set([
  "basicConstraints",
  "keyUsage",
  APP_STORE_RECEIPT_SIGNING_OID,
  APPLE_WWDR_INTERMEDIATE_OID,
]);

export type VerificationOptions = {
  trustedRoots?: Uint8Array[];
  requireAppleProfileOids?: boolean;
};

export function b64(value: string) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const bin = atob(padded);
  return Uint8Array.from(bin, (char) => char.charCodeAt(0));
}

function toPem(base64Der: string) {
  const body = base64Der.match(/.{1,64}/g)?.join("\n") ?? base64Der;
  return `-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----`;
}

function bytesEqual(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

function parseCertificate(der: Uint8Array) {
  try {
    const certificate = new X509();
    certificate.readCertHex(Array.from(der, (byte) => byte.toString(16).padStart(2, "0")).join(""));
    return certificate;
  } catch {
    throw new Error("malformed_certificate");
  }
}

function extensionNames(certificate: X509) {
  return certificate.getParam().ext ?? [];
}

function assertNoUnsupportedCriticalExtensions(certificate: X509) {
  for (const extension of extensionNames(certificate)) {
    if (extension.critical === true && !KNOWN_CRITICAL_EXTENSIONS.has(extension.extname)) {
      throw new Error("unsupported_critical_certificate_extension");
    }
  }
}

function assertAcceptedCertificateAlgorithms(certificate: X509) {
  const key = certificate.getPublicKey();
  if (key?.type !== "EC" || key.curveName !== "secp256r1") {
    throw new Error("unsupported_certificate_public_key");
  }
  if (!ACCEPTED_SIGNATURE_ALGORITHMS.has(certificate.getSignatureAlgorithmField())) {
    throw new Error("unsupported_certificate_signature_algorithm");
  }
}

function assertLeafPolicy(certificate: X509, requireAppleProfileOids: boolean) {
  const constraints = certificate.getExtBasicConstraints();
  if (!constraints || constraints.cA === true) throw new Error("leaf_must_not_be_ca");
  const usage = certificate.getExtKeyUsage();
  if (!usage?.names?.includes("digitalSignature")) throw new Error("leaf_missing_digital_signature");
  const extendedUsage = certificate.getExtExtKeyUsage();
  if (extendedUsage?.critical === true) {
    throw new Error("unsupported_critical_extended_key_usage");
  }
  if (requireAppleProfileOids &&
      certificate.getExtInfo(APP_STORE_RECEIPT_SIGNING_OID) === undefined) {
    throw new Error("leaf_missing_app_store_signing_purpose");
  }
}

function assertCaPolicy(
  certificate: X509,
  role: "intermediate" | "root",
  requireAppleProfileOids: boolean,
) {
  const constraints = certificate.getExtBasicConstraints();
  if (!constraints || constraints.cA !== true) throw new Error(`${role}_must_be_ca`);
  const usage = certificate.getExtKeyUsage();
  if (!usage?.names?.includes("keyCertSign")) throw new Error(`${role}_missing_key_cert_sign`);
  if (role === "intermediate" && constraints.pathLen !== undefined && constraints.pathLen < 0) {
    throw new Error("invalid_intermediate_path_length");
  }
  if (role === "root" && constraints.pathLen !== undefined && constraints.pathLen < 1) {
    throw new Error("invalid_root_path_length");
  }
  if (role === "intermediate" && requireAppleProfileOids &&
      certificate.getExtInfo(APPLE_WWDR_INTERMEDIATE_OID) === undefined) {
    throw new Error("intermediate_missing_wwdr_purpose");
  }
}

function assertCertificatePolicies(
  leafDer: Uint8Array,
  intermediateDer: Uint8Array,
  rootDer: Uint8Array,
  requireAppleProfileOids: boolean,
) {
  const leaf = parseCertificate(leafDer);
  const intermediate = parseCertificate(intermediateDer);
  const root = parseCertificate(rootDer);
  for (const certificate of [leaf, intermediate, root]) {
    assertNoUnsupportedCriticalExtensions(certificate);
    assertAcceptedCertificateAlgorithms(certificate);
  }
  assertLeafPolicy(leaf, requireAppleProfileOids);
  assertCaPolicy(intermediate, "intermediate", requireAppleProfileOids);
  assertCaPolicy(root, "root", false);
  if (leaf.getIssuerString() !== intermediate.getSubjectString()) {
    throw new Error("leaf_issuer_subject_mismatch");
  }
  if (intermediate.getIssuerString() !== root.getSubjectString()) {
    throw new Error("intermediate_issuer_subject_mismatch");
  }
  if (root.getIssuerString() !== root.getSubjectString()) {
    throw new Error("root_not_self_issued");
  }
}

function readTlv(buffer: Uint8Array, offset: number) {
  if (offset + 2 > buffer.length) throw new Error("malformed_certificate");
  const tag = buffer[offset];
  let length = buffer[offset + 1];
  let headerLength = 2;
  if (length & 0x80) {
    const byteCount = length & 0x7f;
    if (byteCount === 0 || byteCount > 4 || offset + 2 + byteCount > buffer.length) {
      throw new Error("malformed_certificate");
    }
    length = 0;
    for (let i = 0; i < byteCount; i++) length = (length << 8) | buffer[offset + 2 + i];
    headerLength += byteCount;
  }
  const valueStart = offset + headerLength;
  const end = valueStart + length;
  if (end > buffer.length) throw new Error("malformed_certificate");
  return { tag, start: offset, valueStart, end };
}

function certificateParts(der: Uint8Array) {
  const outer = readTlv(der, 0);
  const tbs = readTlv(der, outer.valueStart);
  const signatureAlgorithm = readTlv(der, tbs.end);
  const signatureBitString = readTlv(der, signatureAlgorithm.end);
  return {
    tbs,
    tbsBytes: der.slice(tbs.start, tbs.end),
    signature: der.slice(signatureBitString.valueStart + 1, signatureBitString.end),
  };
}

function derEcdsaToRaw(der: Uint8Array) {
  const sequence = readTlv(der, 0);
  const r = readTlv(der, sequence.valueStart);
  const s = readTlv(der, r.end);
  const normalize = (input: Uint8Array) => {
    let bytes = input;
    while (bytes.length > 32 && bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > 32) throw new Error("invalid_ecdsa_signature");
    const result = new Uint8Array(32);
    result.set(bytes, 32 - bytes.length);
    return result;
  };
  const raw = new Uint8Array(64);
  raw.set(normalize(der.slice(r.valueStart, r.end)), 0);
  raw.set(normalize(der.slice(s.valueStart, s.end)), 32);
  return raw;
}

function parseAsn1Time(bytes: Uint8Array, tag: number) {
  const value = new TextDecoder().decode(bytes);
  const match = tag === 0x17
    ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(value)
    : /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(value);
  if (!match) throw new Error("malformed_certificate_time");
  const shortYear = tag === 0x17;
  const year = shortYear
    ? (Number(match[1]) >= 50 ? 1900 : 2000) + Number(match[1])
    : Number(match[1]);
  return Date.UTC(
    year,
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4]),
    Number(match[5]),
    Number(match[6]),
  );
}

function certificateValidity(der: Uint8Array) {
  const { tbs } = certificateParts(der);
  let cursor = tbs.valueStart;
  let node = readTlv(der, cursor);
  if (node.tag === 0xa0) {
    cursor = node.end;
    node = readTlv(der, cursor);
  }
  cursor = node.end; // serial
  cursor = readTlv(der, cursor).end; // signature
  cursor = readTlv(der, cursor).end; // issuer
  const validity = readTlv(der, cursor);
  const notBefore = readTlv(der, validity.valueStart);
  const notAfter = readTlv(der, notBefore.end);
  return {
    notBefore: parseAsn1Time(der.slice(notBefore.valueStart, notBefore.end), notBefore.tag),
    notAfter: parseAsn1Time(der.slice(notAfter.valueStart, notAfter.end), notAfter.tag),
  };
}

function assertCertificateCurrent(der: Uint8Array, now: number) {
  const validity = certificateValidity(der);
  assertValidityWindow(validity.notBefore, validity.notAfter, now);
}

function certificateVerifiedBy(childDer: Uint8Array, issuerDer: Uint8Array) {
  const child = parseCertificate(childDer);
  const issuer = parseCertificate(issuerDer);
  try {
    return child.verifySignature(issuer.getPublicKey());
  } catch {
    return false;
  }
}

let appleRoots: Uint8Array[] | null = null;
async function bundledAppleRoots() {
  if (appleRoots) return appleRoots;
  const rootUrl = new URL("./certs/AppleRootCA-G3.cer", import.meta.url);
  appleRoots = [await Deno.readFile(rootUrl)];
  return appleRoots;
}

export async function verifyAppleJws(
  jws: string,
  now = Date.now(),
  options: VerificationOptions = {},
) {
  const segments = jws.split(".");
  if (segments.length !== 3 || segments.some((segment) => !segment)) throw new Error("malformed_jws");
  let header: jose.ProtectedHeaderParameters;
  try { header = JSON.parse(new TextDecoder().decode(b64(segments[0]))); }
  catch { throw new Error("malformed_jws_header"); }
  validateJwsHeader(header as Record<string, unknown>);

  const leafDer = b64(header.x5c[0]);
  const intermediateDer = b64(header.x5c[1]);
  const rootDer = b64(header.x5c[2]);
  // Tests may inject a local-only root. Production has no environment override
  // and trusts only the reviewed certificate bundled with this function.
  const trustedRoots = options.trustedRoots ?? await bundledAppleRoots();
  if (!trustedRoots.some((root) => bytesEqual(rootDer, root))) throw new Error("untrusted_root");
  const requireAppleProfileOids = options.requireAppleProfileOids ?? true;
  assertCertificatePolicies(leafDer, intermediateDer, rootDer, requireAppleProfileOids);
  assertCertificateCurrent(leafDer, now);
  assertCertificateCurrent(intermediateDer, now);
  assertCertificateCurrent(rootDer, now);
  if (!certificateVerifiedBy(leafDer, intermediateDer)) throw new Error("leaf_chain_invalid");
  if (!certificateVerifiedBy(intermediateDer, rootDer)) {
    throw new Error("intermediate_chain_invalid");
  }
  if (!certificateVerifiedBy(rootDer, rootDer)) {
    throw new Error("root_self_signature_invalid");
  }

  const leafKey = await jose.importX509(toPem(header.x5c[0]), "ES256");
  const { payload } = await jose.compactVerify(jws, leafKey, { algorithms: ["ES256"] });
  try { return JSON.parse(new TextDecoder().decode(payload)); }
  catch { throw new Error("malformed_jws_payload"); }
}
