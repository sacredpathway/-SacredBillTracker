#!/bin/bash
# submit_v1011_to_appstore.command
# Archives SacredBillTracker 1.0.11 (27) and uploads to App Store Connect.
#
# Mirrors the proven v1.0.9 flow:
#   1. xcodebuild archive (Release, Distribution, generic iOS)
#   2. xcodebuild -exportArchive -> .ipa (app-store-connect method)
#   3. If APP_STORE_CONNECT_API_KEY_* env vars are set -> uploads via altool.
#      Otherwise -> reveals the .ipa so you can deliver it in Transporter.
#
# Archive output is NOT run with -quiet, so the Release guard's
# "verify_release_no_debug_strings: ✅ clean" line is captured in the log.
#
# Optional fully-automatic upload — set before running:
#   export APP_STORE_CONNECT_API_KEY_ID="ABC123XYZ"
#   export APP_STORE_CONNECT_API_KEY_ISSUER="abcd1234-5678-90ef-..."
#   export APP_STORE_CONNECT_API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_ABC123XYZ.p8"

set -o pipefail
cd "$(dirname "$0")"

LOG="submit_v1011_to_appstore.log"
ARCHIVE_PATH="$(pwd)/build_v1011_archive.xcarchive"
EXPORT_DIR="$(pwd)/build_v1011_ipa"
EXPORT_PLIST="$(pwd)/build_v1011_export_options.plist"

echo "==> SacredBillTracker v1.0.11 (27) — App Store submission" | tee "$LOG"
date | tee -a "$LOG"
echo "" | tee -a "$LOG"

# 1. ExportOptions.plist
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

# 2. Archive (NOT quiet — keeps the guard's ✅ clean line in the log)
echo "==> Archiving (Release, generic iOS)…" | tee -a "$LOG"
rm -rf "$ARCHIVE_PATH"
xcodebuild \
    -project SacredBillTracker.xcodeproj \
    -scheme SacredBillTracker \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    clean archive 2>&1 | tee -a "$LOG"
ARCHIVE_STATUS=${PIPESTATUS[0]}

if [ "$ARCHIVE_STATUS" -ne 0 ]; then
    echo "" | tee -a "$LOG"
    echo "❌ ARCHIVE FAILED. First errors:" | tee -a "$LOG"
    grep -nE "error:|illegal byte|not permitted|RELEASE GUARD" "$LOG" | head -15 | tee -a "$LOG"
    exit 2
fi
echo "✅ Archive created at $ARCHIVE_PATH" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# 3. Export .ipa
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

# 4. Upload to App Store Connect
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
    echo "✅ UPLOAD SUCCEEDED — build appears in ASC after ~5–20 min processing." | tee -a "$LOG"
else
    echo "ℹ️ No ASC API key env vars set — upload manually in Transporter:" | tee -a "$LOG"
    echo "     1. Open Transporter, sign in with your Apple ID." | tee -a "$LOG"
    echo "     2. Drag in: $IPA" | tee -a "$LOG"
    echo "     3. Click Deliver." | tee -a "$LOG"
    open -R "$IPA"
fi

echo "" | tee -a "$LOG"
echo "==> In App Store Connect: select build 1.0.11 (27), fill What's New, Add for Review." | tee -a "$LOG"
exit 0
