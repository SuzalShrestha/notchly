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
