#!/usr/bin/env python3
"""Re-render all 4 device variants after the tab bar safe area fix.
Overwrites files directly in AppStoreScreenshots_FINAL/."""
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

from fix_ipad_and_deploy import render_set, PROJECT  # noqa

dst = PROJECT / "AppStoreScreenshots_FINAL"

print("[iPhone 6.7] 1290x2796")
render_set((1290, 2796), dst / "iPhone_6_7", "phone")
print("[iPhone 6.9] 1320x2868")
render_set((1320, 2868), dst / "iPhone_6_9", "phone")
print("[iPad 13]    2064x2752")
render_set((2064, 2752), dst / "iPad_13", "ipad")
print("[iPad 12.9]  2048x2732")
render_set((2048, 2732), dst / "iPad_12_9", "ipad")
print("Done.")
