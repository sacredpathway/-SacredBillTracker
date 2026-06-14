#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$ROOT_DIR/supabase/migrations/20260611090000_managed_financial_profiles.sql"
ENTITLEMENTS="$ROOT_DIR/SacredBillTracker/Services/StoreKit/Entitlements.swift"
STORE="$ROOT_DIR/SacredBillTracker/Services/ManagedProfileStore.swift"
PROFILES_VIEW="$ROOT_DIR/SacredBillTracker/Views/Profiles/ManagedProfilesView.swift"
PAYWALL="$ROOT_DIR/SacredBillTracker/Views/Paywall/PaywallView.swift"
ADD_BILL="$ROOT_DIR/SacredBillTracker/Views/Bills/AddEditBillView.swift"
QUICK_ADD="$ROOT_DIR/SacredBillTracker/Views/Bills/QuickAddView.swift"
ADD_INCOME="$ROOT_DIR/SacredBillTracker/Views/Income/AddEditIncomeView.swift"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "Missing file: $1"
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  grep -Eq "$pattern" "$file" || fail "$label"
}

reject_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq "$pattern" "$file"; then
    fail "$label"
  fi
}

require_file "$MIGRATION"
require_file "$ENTITLEMENTS"
require_file "$STORE"
require_file "$PROFILES_VIEW"
require_file "$PAYWALL"
require_file "$ADD_BILL"
require_file "$QUICK_ADD"
require_file "$ADD_INCOME"

require_pattern "$MIGRATION" 'create table if not exists public\.financial_profiles' "financial_profiles table is not created"
require_pattern "$MIGRATION" 'archived_at[[:space:]]+timestamptz' "financial_profiles.archived_at is missing"
require_pattern "$MIGRATION" 'add column if not exists profile_id uuid' "bills.profile_id migration is missing"
require_pattern "$MIGRATION" 'create table if not exists public\.income_entries' "income_entries table is not created"
require_pattern "$MIGRATION" 'foreign key \(profile_id\) references public\.financial_profiles\(id\) on delete restrict' "bills.profile_id FK must be ON DELETE RESTRICT"
require_pattern "$MIGRATION" 'profile_id[[:space:]]+uuid not null references public\.financial_profiles\(id\) on delete restrict' "income_entries.profile_id FK must be ON DELETE RESTRICT"
require_pattern "$MIGRATION" 'alter table public\.financial_profiles enable row level security' "financial_profiles RLS is not enabled"
require_pattern "$MIGRATION" 'alter table public\.bills enable row level security' "bills RLS is not enabled"
require_pattern "$MIGRATION" 'alter table public\.income_entries enable row level security' "income_entries RLS is not enabled"
require_pattern "$MIGRATION" 'using \(auth\.uid\(\) = owner_id\)' "owner-only RLS predicates are missing"
require_pattern "$MIGRATION" 'profile_id does not belong to owner_id' "profile/owner trigger guard is missing"
reject_pattern "$MIGRATION" 'create policy "Owners can delete profiles"' "financial_profiles must not expose an owner delete policy; archive instead"

require_pattern "$ENTITLEMENTS" 'allowManagedProfiles = false' "Free tier must not allow Managed Profiles"
require_pattern "$ENTITLEMENTS" 'Managed Financial Profiles is a Premium feature' "Managed Profiles paywall message is missing"
require_pattern "$PAYWALL" '\$19\.99 / month' 'Monthly fallback price must be $19.99'

require_pattern "$STORE" 'applyPremiumAccess' "ManagedProfileStore must consume premium access"
require_pattern "$STORE" 'rejectPremiumOnlyAction' "ManagedProfileStore must reject locked actions"
require_pattern "$STORE" 'func selectAllProfiles\(\)' "selectAllProfiles method is missing"
require_pattern "$STORE" 'func createProfile\(name: String, kind: ManagedProfileKind\).*' "createProfile method is missing"
require_pattern "$STORE" 'guard canUseManagedProfiles else' "ManagedProfileStore must guard premium-only mutations"
require_pattern "$STORE" 'enforceFreeSelection' "Free users must be normalized back to default profile"

require_pattern "$PROFILES_VIEW" 'PremiumMessaging\.managedProfiles' "Profile UI must show Managed Profiles paywall"
require_pattern "$PROFILES_VIEW" 'if subs\.isPro' "Profile switcher/manage UI must branch on Pro entitlement"
require_pattern "$ADD_BILL" 'profiles\.canUseManagedProfiles && profiles\.profiles\.count > 1' "Add/Edit Bill profile picker must be premium-gated"
require_pattern "$QUICK_ADD" 'profiles\.canUseManagedProfiles && profiles\.profiles\.count > 1' "Quick Add profile picker must be premium-gated"
require_pattern "$ADD_INCOME" 'profiles\.canUseManagedProfiles && profiles\.profiles\.count > 1' "Add/Edit Income profile picker must be premium-gated"

echo "PASS: Managed Profiles migration and premium-gating static checks passed."
