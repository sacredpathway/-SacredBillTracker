-- Path B rollback plan - do not execute without explicit approval.
-- Preferred rollback is binary/function rollback while leaving additive tables.
-- The destructive section is only safe before real Receipt Jar production data.

begin;

-- Stop function access first.
revoke all on function public.sbt_record_verified_receipt_jar_purchase(
  uuid, text, text, text, text, text, text, text, text, timestamptz, timestamptz, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.sbt_recalculate_effective_entitlements(uuid)
  from public, anon, authenticated, service_role;

drop function if exists public.sbt_record_verified_receipt_jar_purchase(
  uuid, text, text, text, text, text, text, text, text, timestamptz, timestamptz, text, uuid
);
drop function if exists public.sbt_recalculate_effective_entitlements(uuid);

-- Destructive cleanup. Use only before real customer Receipt Jar data exists.
drop table if exists public.sbt_effective_entitlements;
drop table if exists public.sbt_store_events;
drop table if exists public.sbt_store_purchases;

commit;
