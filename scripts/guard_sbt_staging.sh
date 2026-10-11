#!/bin/sh
#
# Fail-closed guard for Sacred Bill Tracker staging-only Supabase operations.
# This script performs read-only project identity checks before a human or
# wrapper script runs a migration/deploy command. It intentionally does not
# execute any remote mutation itself.

set -eu

EXPECTED_STAGING_REF="thwjnpofhrpxfuvwkfgd"
EXPECTED_STAGING_NAME="Sacred Bill Tracker Sandbox"
PRODUCTION_REF="zziauybwemoiqfpidiur"
TARGET_REF="${SBT_SUPABASE_TARGET_REF:-}"

if [ -z "$TARGET_REF" ]; then
  echo "refusing: SBT_SUPABASE_TARGET_REF is not set" >&2
  exit 64
fi

if [ "$TARGET_REF" = "$PRODUCTION_REF" ]; then
  echo "refusing: target is production/default project $PRODUCTION_REF" >&2
  exit 65
fi

if [ "$TARGET_REF" != "$EXPECTED_STAGING_REF" ]; then
  echo "refusing: unexpected target ref $TARGET_REF" >&2
  exit 66
fi

PROJECTS_JSON="$(supabase projects list --output json)"

python3 - "$PROJECTS_JSON" "$EXPECTED_STAGING_REF" "$EXPECTED_STAGING_NAME" "$PRODUCTION_REF" <<'PY'
import json
import sys

projects = json.loads(sys.argv[1])
expected_ref = sys.argv[2]
expected_name = sys.argv[3]
production_ref = sys.argv[4]

by_ref = {item.get("ref"): item for item in projects}
target = by_ref.get(expected_ref)
if target is None:
    raise SystemExit(f"refusing: staging ref {expected_ref} not found in Supabase project list")
if target.get("name") != expected_name:
    raise SystemExit(f"refusing: staging name mismatch for {expected_ref}")
if target.get("status") != "ACTIVE_HEALTHY":
    raise SystemExit(f"refusing: staging project status is {target.get('status')!r}")
if production_ref not in by_ref:
    raise SystemExit(f"refusing: production/default ref {production_ref} was not visible for comparison")
if target.get("database", {}).get("host") == by_ref[production_ref].get("database", {}).get("host"):
    raise SystemExit("refusing: staging and production database hosts match")

print(f"verified staging target: {expected_ref} ({expected_name})")
PY
