#!/bin/sh
#
#  verify_release_no_debug_strings.sh
#  SacredBillTracker
#
#  BELT-AND-SUSPENDERS RELEASE GUARD.
#
#  Runs as a Run Script build phase on the SacredBillTracker app target.
#  It is a no-op for every configuration EXCEPT Release. On Release (and
#  therefore every Archive / TestFlight / App Store build) it scans the
#  fully-built .app bundle — the linked Mach-O binary AND bundled text
#  resources — for developer / QA / sample / e-book strings that must
#  never reach a real user. If any are found, the build FAILS with a
#  clear error so the artifact can never be uploaded.
#
#  This is a second line of defense behind `#if DEBUG`. If a future
#  change ever forgets to gate a debug affordance, this catches it at
#  build time instead of in the App Store.
#
#  Does NOT modify the app, its features, or its branding — read-only.
#
set -eu
case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} ${OTHER_SWIFT_FLAGS:-} " in
  *SBT_STAGING_ACCEPTANCE*)
    if [ "${CONFIGURATION:-}" != "Debug" ] || [ "${ACTION:-}" != "build" ] || [ "${DEPLOYMENT_POSTPROCESSING:-NO}" = "YES" ]; then
      echo "error: Staging acceptance forbids Release/archive/install builds."
      exit 1
    fi
    ;;
esac

# The committed template permits simulator-only structural validation without
# production analytics credentials. Never let that temporary configuration
# participate in an install/archive or device build.
if [ "${SBT_LOCAL_VALIDATION_ONLY:-NO}" = "YES" ]; then
    if [ "${ACTION:-}" != "build" ] || [ "${PLATFORM_NAME:-}" != "iphonesimulator" ] || [ "${DEPLOYMENT_POSTPROCESSING:-NO}" = "YES" ]; then
        echo "error: Local validation configuration is simulator-build-only; archive/install/device builds are prohibited."
        exit 1
    fi
fi

# Force a byte-safe locale. `strings -a` on a Mach-O binary emits bytes
# that are not valid UTF-8; under a UTF-8 locale BSD sed/grep abort with
# "RE error: illegal byte sequence". The C locale treats input as raw
# bytes so the scan never crashes. Our patterns are all ASCII, so
# case-insensitive matching is unaffected.
export LC_ALL=C
export LANG=C

# ----------------------------------------------------------------------
# 1. Release-only. Skip entirely for Debug (and any other config).
# ----------------------------------------------------------------------
if [ "${CONFIGURATION:-}" != "Release" ]; then
    echo "verify_release_no_debug_strings: skipped (CONFIGURATION=${CONFIGURATION:-unset}, Release-only guard)"
    exit 0
fi

# ----------------------------------------------------------------------
# 2. Locate the built app bundle / binary.
# ----------------------------------------------------------------------
APP_DIR="${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}"
BIN="${TARGET_BUILD_DIR:-}/${EXECUTABLE_PATH:-}"

if [ ! -e "$BIN" ]; then
    echo "warning: verify_release_no_debug_strings: binary not found at '$BIN' — skipping scan"
    exit 0
fi

# ----------------------------------------------------------------------
# 3. Banned production-facing strings (case-insensitive).
#    These are exact UI strings that only exist in DEBUG-gated code.
# ----------------------------------------------------------------------
# Patterns are matched case-insensitively (grep -i).
PATTERNS='Continue as Dev Tester
Seed Screenshots
Reset with sample
(DEBUG)
[QA]
e-book
ebook
sample data
mock data'

# ----------------------------------------------------------------------
# 4. DOCUMENTED BENIGN EXCEPTIONS (explicit allow-list).
#    "facebook" legitimately contains the substring "ebook" (Facebook
#    sign-in / marketing strings). It is the ONLY allowed false positive.
#    We strip the word "facebook" from the haystack before matching so a
#    genuine "ebook" still trips the guard.
# ----------------------------------------------------------------------
strip_benign() {
    # Remove the standalone word "facebook" (any case) so its embedded
    # "ebook" cannot cause a false failure.
    sed 's/[Ff][Aa][Cc][Ee][Bb][Oo][Oo][Kk]//g'
}

FAILED=0

scan() {
    # $1 = human label, $2 = text stream already on stdin
    label="$1"
    while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        # Fixed-string, case-insensitive match against the cleaned stream.
        if printf '%s' "$HAYSTACK" | grep -iF -- "$pat" >/dev/null 2>&1; then
            echo "error: RELEASE GUARD — banned string \"$pat\" found in $label"
            FAILED=1
        fi
    done <<EOF
$PATTERNS
EOF
}

# --- Scan the Mach-O binary's string table ---
HAYSTACK="$(strings -a "$BIN" 2>/dev/null | strip_benign)"
scan "app binary ($EXECUTABLE_PATH)"

# --- Scan bundled text resources (plist/json/strings/txt/html/md/csv) ---
if [ -d "$APP_DIR" ]; then
    RES_TEXT="$(find "$APP_DIR" -type f \
        \( -iname '*.plist' -o -iname '*.json' -o -iname '*.strings' \
           -o -iname '*.txt' -o -iname '*.html' -o -iname '*.md' \
           -o -iname '*.csv' \) -exec cat {} + 2>/dev/null)"
    HAYSTACK="$(printf '%s' "$RES_TEXT" | strip_benign)"
    scan "bundled resources"
fi

# ----------------------------------------------------------------------
# 5. Verdict.
# ----------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    echo "error: ❌ Release build BLOCKED — debug/QA/sample/e-book content detected in the shipping app."
    echo "error:    Gate the offending UI behind '#if DEBUG' and rebuild. See scripts/verify_release_no_debug_strings.sh."
    exit 1
fi

echo "verify_release_no_debug_strings: ✅ clean — no banned strings in Release build."
exit 0
