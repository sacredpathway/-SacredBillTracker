import { cors, json, admin, getUser } from "./shared.ts";
import { verifyApple } from "./apple-verifier.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
  const user = await getUser(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  let body;
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  if (!body || typeof body !== "object" || typeof body.platform !== "string") return json({error:"invalid_platform"},400);
  const platform = body.platform.toLowerCase();
  const db = admin();
    if (platform === "ios" || platform === "apple") return await verifyApple(user, body, db);
    return json({ error: "invalid_platform", hint: "verify-store-subscription accepts only 'ios' or 'apple'; use store-verification-google for Google Play" }, 400);
  } catch (caught) {
    console.error(JSON.stringify({event:"entitlement_verification",reason:"verification_failure"}));
    return json({ error: "verification_exception" }, 500);
  }
});
