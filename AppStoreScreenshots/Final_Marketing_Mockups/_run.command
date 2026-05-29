#!/bin/bash
# Double-clickable launcher.
# After saving this file, run once:  chmod +x _run.command
set -e
cd "$(dirname "$0")"
echo "▸ Sacred Bill Tracker — marketing mockup builder"
echo

# Make sure Pillow is available on the system Python.
if ! python3 -c "from PIL import Image" 2>/dev/null; then
    echo "▸ Installing Pillow (required for image compositing)…"
    python3 -m pip install --user --quiet --break-system-packages Pillow || \
        python3 -m pip install --user --quiet Pillow
fi

python3 _make_mockups.py
echo
echo "Press any key to close…"
read -n 1 -s
