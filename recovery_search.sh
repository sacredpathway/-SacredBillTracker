#!/bin/bash
# Sacred Bill Tracker — Real-bill recovery search
# Read-only. Writes its findings to recovery_search_results.txt next to itself.
# Run from Terminal:   bash "/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER/recovery_search.sh"

set -u
WORKDIR="/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER"
OUT="$WORKDIR/recovery_search_results.txt"
BUNDLE_ID="com.sacredbilltracker.app"
DEFAULTS_KEY="sacred.bill.tracker.bills.v1"

{
  echo "=================================================================="
  echo "Sacred Bill Tracker — recovery search"
  echo "Run at:        $(date)"
  echo "Hostname:      $(hostname)"
  echo "Bundle ID:     $BUNDLE_ID"
  echo "Local cache:   UserDefaults key '$DEFAULTS_KEY' (JSON [Bill])"
  echo "=================================================================="
  echo

  echo "## 1. CoreSimulator app containers with SacredBillTracker installed"
  echo "----------------------------------------------------------------"
  SIM_BASE="$HOME/Library/Developer/CoreSimulator/Devices"
  if [ -d "$SIM_BASE" ]; then
    found=0
    while IFS= read -r dev; do
      DEV_PLIST="$dev/device.plist"
      DEV_NAME="(name unknown)"
      [ -f "$DEV_PLIST" ] && DEV_NAME=$(/usr/libexec/PlistBuddy -c "Print :name" "$DEV_PLIST" 2>/dev/null || echo "(name unknown)")
      DEV_OS=$(/usr/libexec/PlistBuddy -c "Print :runtime" "$DEV_PLIST" 2>/dev/null | sed 's/.*\.SimRuntime\.//')
      APPSDIR="$dev/data/Containers/Bundle/Application"
      DATADIR="$dev/data/Containers/Data/Application"
      [ -d "$APPSDIR" ] || continue
      while IFS= read -r appbundle; do
        if [ -d "$appbundle/SacredBillTracker.app" ]; then
          found=1
          echo
          echo "DEVICE:    $(basename "$dev")  ($DEV_NAME, $DEV_OS)"
          echo "BUNDLE:    $appbundle/SacredBillTracker.app"
          # find the matching DATA container by bundle id
          for dd in "$DATADIR"/*/; do
            md="$dd/.com.apple.mobile_container_manager.metadata.plist"
            if [ -f "$md" ]; then
              bid=$(/usr/libexec/PlistBuddy -c "Print :MCMMetadataIdentifier" "$md" 2>/dev/null)
              if [ "$bid" = "$BUNDLE_ID" ]; then
                echo "DATA:      $dd"
                PREF="$dd/Library/Preferences/$BUNDLE_ID.plist"
                if [ -f "$PREF" ]; then
                  echo "PLIST:     $PREF"
                  echo "MODIFIED:  $(stat -f '%Sm' "$PREF")"
                  echo "ALL KEYS:"
                  /usr/libexec/PlistBuddy -c "Print" "$PREF" 2>/dev/null | head -200
                  echo "BILLS_JSON_LENGTH (key=$DEFAULTS_KEY):"
                  /usr/libexec/PlistBuddy -c "Print :$DEFAULTS_KEY" "$PREF" 2>/dev/null | wc -c
                  echo "BILLS_DECODED (best-effort, JSON if base64 succeeds):"
                  /usr/libexec/PlistBuddy -x -c "Print :$DEFAULTS_KEY" "$PREF" 2>/dev/null \
                    | xmllint --xpath 'string(/plist/data)' - 2>/dev/null \
                    | tr -d ' \n\t' \
                    | base64 --decode 2>/dev/null \
                    | python3 -m json.tool 2>/dev/null \
                    | head -200
                else
                  echo "PLIST:     (none — UserDefaults file does not exist for this app)"
                fi
                echo "DOCUMENTS DIR:"
                ls -la "$dd/Documents/" 2>/dev/null || echo "  (no Documents folder)"
              fi
            fi
          done
        fi
      done < <(find "$APPSDIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    done < <(find "$SIM_BASE" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    if [ "$found" -eq 0 ]; then
      echo "(no SacredBillTracker installed in any simulator)"
    fi
  else
    echo "(no CoreSimulator/Devices folder)"
  fi
  echo

  echo "## 2. Real-device backups (iTunes / Finder Mobile Backups)"
  echo "----------------------------------------------------------------"
  BAK="$HOME/Library/Application Support/MobileSync/Backup"
  if [ -d "$BAK" ]; then
    ls -la "$BAK" 2>/dev/null
    echo
    echo "Searching backup Manifest.db files for $BUNDLE_ID..."
    for m in "$BAK"/*/Manifest.db; do
      [ -f "$m" ] || continue
      hits=$(sqlite3 "$m" "select count(*) from Files where domain like '%$BUNDLE_ID%';" 2>/dev/null || echo "?")
      echo "  $m -> $hits hit(s)"
    done
  else
    echo "(no MobileSync/Backup folder)"
  fi
  echo

  echo "## 3. Spotlight-indexed paths matching SacredBillTracker / Bill Tracker"
  echo "----------------------------------------------------------------"
  mdfind -name "SacredBillTracker" 2>/dev/null | head -50
  echo "---"
  mdfind -name "Sacred Bill" 2>/dev/null | head -30
  echo "---"
  mdfind "kMDItemDisplayName == 'bills.v1.json'" 2>/dev/null | head -10
  echo

  echo "## 4. Mac UserDefaults under com.sacredbilltracker.app (in case Mac target ever ran)"
  echo "----------------------------------------------------------------"
  defaults read $BUNDLE_ID 2>&1 | head -100 || true
  echo

  echo "## 5. Time Machine snapshots (local APFS only)"
  echo "----------------------------------------------------------------"
  tmutil listlocalsnapshots / 2>/dev/null || echo "(no local snapshots)"
  echo

  echo "## 6. Other Sacred-named folders on disk (skipping Photos/iCloud)"
  echo "----------------------------------------------------------------"
  find "$HOME/Documents" "$HOME/Desktop" "$HOME/Downloads" -maxdepth 6 -iname "*Sacred*" -o -iname "*Bill Tracker*" 2>/dev/null | head -50
  echo

  echo "## 7. Old DerivedData artifacts that might contain debug seeds"
  echo "----------------------------------------------------------------"
  ls -la "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | grep -i sacred || echo "(no SBT DerivedData)"
  echo

  echo "## 8. Workspace JSON/CSV/SQL exports"
  echo "----------------------------------------------------------------"
  find "$WORKDIR" -type f \( -name "*.json" -o -name "*.sqlite" -o -name "*.sqlite3" -o -name "*bills*.csv" \) 2>/dev/null | head -30
  echo

  echo "=================================================================="
  echo "Search complete. Output saved to: $OUT"
  echo "=================================================================="
} > "$OUT" 2>&1

echo "Done. Results saved to:"
echo "  $OUT"
