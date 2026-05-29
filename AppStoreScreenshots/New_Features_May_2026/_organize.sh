#!/bin/bash
# One-shot mover: relocates the 10 freshly-captured Sacred Bill Tracker
# screenshots from ~/Desktop into this folder with App-Store-ready names.
#
# Run once:
#   bash ~/Documents/Claude/Projects/SACRED\ BILL\ TRACKER/AppStoreScreenshots/New_Features_May_2026/_organize.sh
#
# Idempotent: any source file already moved is silently skipped.

SRC="$HOME/Desktop"
DST="$HOME/Documents/Claude/Projects/SACRED BILL TRACKER/AppStoreScreenshots/New_Features_May_2026"

mvf () { [ -f "$1" ] && mv -n "$1" "$2" && echo "  → $(basename "$2")"; }

# iPhone 17 Pro Max  (1320 × 2868)
mvf "$SRC/Simulator Screenshot - iPhone 17 Pro Max - 2026-05-06 at 16.17.38.png" "$DST/iPhone_1_DashboardSplit.png"
mvf "$SRC/Simulator Screenshot - iPhone 17 Pro Max - 2026-05-06 at 16.15.19.png" "$DST/iPhone_2_DashboardCombined.png"
mvf "$SRC/Simulator Screenshot - iPhone 17 Pro Max - 2026-05-06 at 16.11.32.png" "$DST/iPhone_3_BillsSortMenu.png"
mvf "$SRC/Simulator Screenshot - iPhone 17 Pro Max - 2026-05-06 at 16.02.53.png" "$DST/iPhone_4_BillsSortedByAmount.png"
mvf "$SRC/Simulator Screenshot - iPhone 17 Pro Max - 2026-05-06 at 16.24.11.png" "$DST/iPhone_5_DashboardHero.png"

# iPad Pro 13-inch (M5)  (2064 × 2752)
mvf "$SRC/Simulator Screenshot - iPad Pro 13-inch (M5) - 2026-05-06 at 16.45.11.png" "$DST/iPad_1_DashboardSplit.png"
mvf "$SRC/Simulator Screenshot - iPad Pro 13-inch (M5) - 2026-05-06 at 16.46.58.png" "$DST/iPad_2_DashboardCombined.png"
mvf "$SRC/Simulator Screenshot - iPad Pro 13-inch (M5) - 2026-05-06 at 16.57.27.png" "$DST/iPad_3_BillsSortMenu.png"
mvf "$SRC/Simulator Screenshot - iPad Pro 13-inch (M5) - 2026-05-06 at 17.00.35.png" "$DST/iPad_4_BillsSortedByAmount.png"
mvf "$SRC/Simulator Screenshot - iPad Pro 13-inch (M5) - 2026-05-06 at 17.02.54.png" "$DST/iPad_5_DashboardHero.png"

# pre-renamed (handled by an earlier in-Finder rename pass)
mvf "$SRC/iPad_5_DashboardHero.png"  "$DST/iPad_5_DashboardHero.png"

echo
echo "Done. Files in $DST:"
ls -la "$DST" | grep -v "^total"
