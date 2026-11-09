#!/bin/bash
# Regenerates every App Store screenshot, end to end:
#   1. fastlane snapshot runs the UI tests (CollectibleScannerUITests) in demo mode
#      on a dedicated iPhone 17 Pro Max simulator  -> screenshots/raw/<device>/
#   2. compose.py adds the background, headline and phone -> screenshots/final/<device>/
# Usage: screenshots/generate.sh            (everything)
#        screenshots/generate.sh --compose  (step 2 only, after editing headlines/style)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SIM="Worthwise Shots 6.9in"   # must match `devices` in fastlane/Snapfile
DEVICE_DIR="iPhone-6.9in"

if [[ "${1:-}" != "--compose" ]]; then
  # A simulator of its own, because snapshot erases it before every run.
  xcrun simctl list devices available | grep -q "$SIM (" || xcrun simctl create "$SIM" "iPhone 17 Pro Max" >/dev/null
  fastlane snapshot
  rm -rf "screenshots/raw/$DEVICE_DIR" && mkdir -p "screenshots/raw/$DEVICE_DIR"
  for f in "screenshots/.snapshot/en-US/$SIM"-*.png; do
    cp "$f" "screenshots/raw/$DEVICE_DIR/${f##*-}"   # "<sim>-01_Value.png" -> "01_Value.png"
  done
fi

python3 screenshots/template/compose.py
echo "Done: screenshots/final/$DEVICE_DIR/"
