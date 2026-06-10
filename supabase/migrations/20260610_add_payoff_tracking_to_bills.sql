-- Adds optional payoff balance tracking to normal bills.
-- This is the user's own bill paydown ledger, not Sacred Duo/partner debt.

alter table public.bills
    add column if not exists payoff_tracking_enabled boolean not null default false,
    add column if not exists payoff_original_balance numeric(14,2),
    add column if not exists payoff_remaining_balance numeric(14,2),
    add column if not exists payoff_payment_amount numeric(14,2),
    add column if not exists payoff_interest_rate numeric(8,4),
    add column if not exists payoff_goal_date timestamptz,
    add column if not exists payoff_category text,
    add column if not exists payoff_history jsonb not null default '[]'::jsonb;

alter table public.bills
    add constraint bills_payoff_category_check
    check (
        payoff_category is null
        or payoff_category in (
            'mortgage',
            'auto_loan',
            'credit_card',
            'personal_loan',
            'student_loan',
            'other'
        )
    ) not valid;

alter table public.bills
    validate constraint bills_payoff_category_check;
