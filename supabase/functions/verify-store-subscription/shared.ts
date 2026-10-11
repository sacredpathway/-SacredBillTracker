import { createClient } from "jsr:@supabase/supabase-js@2";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANON = Deno.env.get("SUPABASE_ANON_KEY");

export function admin() {
  if (!SUPABASE_URL || !SERVICE_ROLE) throw new Error("Server configuration unavailable");
  return createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } });
}

export function userClient(req: Request) {
  if (!SUPABASE_URL || !ANON) throw new Error("Client configuration unavailable");
  const authHeader = req.headers.get("Authorization") ?? "";
  return createClient(SUPABASE_URL, ANON, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function getUser(req: Request) {
  const { data, error } = await userClient(req).auth.getUser();
  if (error || !data?.user) return null;
  return data.user;
}
