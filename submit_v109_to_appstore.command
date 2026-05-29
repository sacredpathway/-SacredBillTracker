#!/bin/bash
# submit_v109_to_appstore.command
# Archives SacredBillTracker 1.0.9 (25) and uploads to App Store Connect.
#
# What this script DOES:
#   1. xcodebuild archive (Release, Distribution)
#   2. xcodebuild -exportArchive → .ipa (App Store method)
#   3. If APP_STORE_CONNECT_API_KEY env vars are set → uploads via altool.
#      Otherwise → opens the .ipa in Transporter so you can click Deliver.
#
# What this script DOES NOT DO:
#   • Click "Submit for Review" in App Store Connect — that final step
#     requires you to log into https://appstoreconnect.apple.com
#     and select the new build under SacredBillTracker → 1.0.9 → Build,
#     fill in "What's New in This Version", then click "Add for Review".
#
# Credentials for fully-automatic upload (optional):
#   export APP_STORE_CONNECT_API_KEY_ID="ABC123XYZ"
#   export APP_STORE_CONNECT_API_KEY_ISSUER="abcd1234-5678-90ef-..."
#   export APP_STORE_CONNECT_API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_ABC123XYZ.p8"
#   bash "submit_v109_to_appstore.command"

set -o pipefail
cd "$(dirname "$0")"

LOG="submit_v109_to_appstore.log"
ARCHIVE_PATH="$(pwd)/build_v109_archive.xcarchive"
EXPORT_DIR="$(pwd)/build_v109_ipa"
EXPORT_PLIST="$(pwd)/build_v109_export_options.plist"

echo "==> SacredBillTracker v1.0.9 (25) — App Store submission" | tee "$LOG"
date | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 1. Write ExportOptions.plist ─────────────────────────────
cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>DCCSGYD5A4</string>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST
echo "    Wrote $EXPORT_PLIST" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 2. Archive ──────────────────────────────────────────────
echo "==> Archiving (Release, generic iOS)…" | tee -a "$LOG"
rm -rf "$ARCHIVE_PATH"
xcodebuild \
    -project SacredBillTracker.xcodeproj \
    -scheme SacredBillTracker \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -quiet \
    clean archive 2>&1 | tee -a "$LOG"
ARCHIVE_STATUS=${PIPESTATUS[0]}

if [ "$ARCHIVE_STATUS" -ne 0 ]; then
    echo "" | tee -a "$LOG"
    echo "❌ ARCHIVE FAILED. First errors:" | tee -a "$LOG"
    grep -nE "error:" "$LOG" | head -10 | tee -a "$LOG"
    exit 2
fi
echo "✅ Archive created at $ARCHIVE_PATH" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 3. Export .ipa ──────────────────────────────────────────
echo "==> Exporting .ipa…" | tee -a "$LOG"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates 2>&1 | tee -a "$LOG"
EXPORT_STATUS=${PIPESTATUS[0]}

if [ "$EXPORT_STATUS" -ne 0 ]; then
    echo "❌ EXPORT FAILED" | tee -a "$LOG"
    exit 3
fi

IPA=$(find "$EXPORT_DIR" -name "*.ipa" -maxdepth 2 | head -1)
if [ -z "$IPA" ]; then
    echo "❌ Couldn't locate the exported .ipa under $EXPORT_DIR" | tee -a "$LOG"
    exit 4
fi
echo "✅ .ipa: $IPA" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 4. Upload to App Store Connect ──────────────────────────
if [ -n "$APP_STORE_CONNECT_API_KEY_ID" ] && \
   [ -n "$APP_STORE_CONNECT_API_KEY_ISSUER" ] && \
   [ -n "$APP_STORE_CONNECT_API_KEY_PATH" ]; then
    echo "==> Uploading via xcrun altool (ASC API key)…" | tee -a "$LOG"
    xcrun altool --upload-app \
        --type ios \
        --file "$IPA" \
        --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
        --apiIssuer "$APP_STORE_CONNECT_API_KEY_ISSUER" 2>&1 | tee -a "$LOG"
    UPLOAD_STATUS=${PIPESTATUS[0]}
    if [ "$UPLOAD_STATUS" -ne 0 ]; then
        echo "❌ UPLOAD FAILED" | tee -a "$LOG"
        exit 5
    fi
    echo "✅ UPLOAD SUCCEEDED — build will appear in App Store Connect after ~5–20 min processing." | tee -a "$LOG"
else
    echo "ℹ️ No App Store Connect API key env vars set." | tee -a "$LOG"
    echo "   To upload manually:" | tee -a "$LOG"
    echo "     1. Open Apple's Transporter app (free in Mac App Store)." | tee -a "$LOG"
    echo "     2. Sign in with your Apple ID." | tee -a "$LOG"
    echo "     3. Drag this file into the Transporter window:" | tee -a "$LOG"
    echo "        $IPA" | tee -a "$LOG"
    echo "     4. Click Deliver." | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    open -R "$IPA"   # Reveal the .ipa in Finder
fi

echo "" | tee -a "$LOG"
echo "==> NEXT STEPS in App Store Connect:" | tee -a "$LOG"
echo "  • Wait 5–20 minutes for processing to finish." | tee -a "$LOG"
echo "  • Sign in: https://appstoreconnect.apple.com" | tee -a "$LOG"
echo "  • SacredBillTracker → + Version or Platform → iOS → 1.0.9" | tee -a "$LOG"
echo "    (or open the existing 1.0.9 if you've already created it)" | tee -a "$LOG"
echo "  • Under \"Build\" → select 1.0.9 (25)." | tee -a "$LOG"
echo "  • Fill in \"What's New in This Version\" (suggested copy below)." | tee -a "$LOG"
echo "  • Click \"Add for Review\" → \"Submit to App Review\"." | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "==> Suggested What's New copy:" | tee -a "$LOG"
cat <<'NOTES' | tee -a "$LOG"
Daily Focus, the Sacred Focus add-on, is here.

• Plan your day: schedule items with start, end, notes, repeat rules, and reminders.
• To-do list: add tasks with priority, repeat options, and notes.
• Schedule Buddy: gentle suggestions based on what's due in your bills.
• Save favorite focus quotes.
• Cleaner dashboard with a combined Financial Overview.
• Tap the Bill Health card to see exactly what needs your attention.
• One-tap bill editing — no more extra navigation screens.
• Light, Dark, and System appearance settings.
NOTES

exit 0
