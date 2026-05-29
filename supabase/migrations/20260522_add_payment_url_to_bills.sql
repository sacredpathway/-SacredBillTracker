-- v1.5 — Payment Link feature.
--
-- Adds an optional text column to public.bills so each bill can store a
-- user-provided payment URL (e.g. their biller / bank-pay page). The app
-- only opens the URL in Safari via UIApplication.shared.open(_:); it
-- never auto-pays.
--
-- Backward-compatible: existing rows keep payment_url = NULL. The Swift
-- model's Codable decoder also tolerates the column being absent for
-- offline-only / pre-migration installs.

begin;

alter table public.bills
  add column if not exists payment_url text;

-- Light-weight server-side guard. We accept anything starting with
-- http:// or https://, or NULL. The client trims and normalizes before
-- it sends, so anything stricter would risk legitimate biller URLs.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'bills_payment_url_format'
  ) then
    alter table public.bills
      add constraint bills_payment_url_format
      check (
        payment_url is null
        or payment_url ~* '^https?://.+'
      );
  end if;
end$$;

comment on column public.bills.payment_url is
  'Optional URL to the user''s biller / bank-pay page. App opens it in '
  'Safari; never auto-pays.';

commit;
