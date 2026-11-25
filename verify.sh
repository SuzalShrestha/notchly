#!/bin/zsh
# Build the app, run the feature self-tests, and render notch snapshots to build/snapshots.
set -euo pipefail
cd "${0:A:h}"
./make-app.sh
# Self-tests use assert, which -O strips: run them on a debug build.
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d $SDK ]] && export SDKROOT=$SDK
swift build 2>&1 | grep -E "error|Build complete"
.build/debug/Notchly --selftest
build/Notchly.app/Contents/MacOS/Notchly --snapshot build/snapshots | tail -1
# Mascot storyboard: every mascot through each mood and act, frame by frame, encoded for review.
build/Notchly.app/Contents/MacOS/Notchly --pet-reel build/snapshots/reel | tail -1
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -y -framerate 30 -i build/snapshots/reel/f%04d.png -c:v libx264 -pix_fmt yuv420p -crf 20 build/snapshots/pet-reel.mp4
  echo "wrote pet-reel.mp4"
fi
