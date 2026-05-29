#!/usr/bin/env python3
"""Render only the iPad 12.9 (2048x2732) variant."""
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

from fix_ipad_and_deploy import render_set, PROJECT  # noqa

dst = PROJECT / "AppStoreScreenshots_FINAL"
print("[iPad 12.9] 2048x2732")
render_set((2048, 2732), dst / "iPad_12_9", "ipad")
print("Done.")
