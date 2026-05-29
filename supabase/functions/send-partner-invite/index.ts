// Supabase Edge Function: send-partner-invite
//
// Triggered by a Postgres webhook on `partner_invites` (INSERT).
// Sends an email to the invited partner via Resend.
//
// ENV REQUIRED (set with `supabase secrets set`):
//   RESEND_API_KEY    - Resend API key (re_...)
//   FROM_EMAIL        - e.g. "SacredBillTracker <invites@yourdomain.com>"
//   APP_DEEPLINK_BASE - e.g. "https://sacredbilltracker.app/invite"
//
// Deploy:
//   supabase functions deploy send-partner-invite --no-verify-jwt
//
// Wire up the trigger (run once in Supabase SQL editor):
//   create extension if not exists pg_net;
//   create or replace function notify_partner_invite()
//   returns trigger language plpgsql security definer as $$
//   begin
//     perform net.http_post(
//       url     := 'https://zziauybwemoiqfpidiur.supabase.co/functions/v1/send-partner-invite',
//       headers := jsonb_build_object('Content-Type','application/json'),
//       body    := jsonb_build_object('id', new.id, 'invited_email', new.invited_email,
//                                     'inviter_id', new.inviter_id)
//     );
//     return new;
//   end $$;
//   drop trigger if exists trg_notify_partner_invite on public.partner_invites;
//   create trigger trg_notify_partner_invite
//     after insert on public.partner_invites
//     for each row execute function notify_partner_invite();

// deno-lint-ignore-file no-explicit-any
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const RESEND_API_KEY    = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL        = Deno.env.get("FROM_EMAIL") ?? "SacredBillTracker <invites@sacredbilltracker.app>";
const APP_DEEPLINK_BASE = Deno.env.get("APP_DEEPLINK_BASE") ?? "https://sacredbilltracker.app/invite";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let payload: { id: string; invited_email: string; inviter_id: string };
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400 });
  }

  if (!payload?.id || !payload?.invited_email) {
    return new Response(JSON.stringify({ error: "missing_fields" }), { status: 400 });
  }

  const acceptUrl = `${APP_DEEPLINK_BASE}?id=${encodeURIComponent(payload.id)}`;

  const html = `
    <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#111">
      <h2 style="margin:0 0 12px 0">You've been invited to budget together</h2>
      <p>Your partner is using <strong>SacredBillTracker</strong> and wants to share bills with you.</p>
      <p style="margin:24px 0">
        <a href="${acceptUrl}" style="background:#0A84FF;color:#fff;text-decoration:none;padding:12px 20px;border-radius:8px;display:inline-block;font-weight:600">
          Accept invite
        </a>
      </p>
      <p style="font-size:12px;color:#666">If you don't have the app yet, install SacredBillTracker from the App Store, sign in with this email (${payload.invited_email}), then tap the link again.</p>
    </div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from:    FROM_EMAIL,
      to:      [payload.invited_email],
      subject: "You've been invited to SacredBillTracker",
      html,
    }),
  });

  const body = await res.text();
  return new Response(body, {
    status: res.status,
    headers: { "Content-Type": "application/json" },
  });
});
