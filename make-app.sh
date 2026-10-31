#!/bin/zsh
# Build Notchly.app (release) with the macOS 26.5 SDK and ad-hoc sign it.
# usage: ./make-app.sh [--run]
set -euo pipefail
cd "${0:A:h}"
# Command Line Tools only: the macOS 27 SDK needs the @State macro plugin that ships with Xcode, so use 26.5.
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[[ -d $SDK ]] && export SDKROOT=$SDK
swift build -c release 2>&1 | grep -E 'error|warning: unre|Build complete' || true
BIN=.build/release/Notchly
[[ -x $BIN ]] || { echo "build failed"; exit 1; }
APP=build/Notchly.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/Notchly
cp Info.plist $APP/Contents/Info.plist
codesign --force --sign - --entitlements Notchly.entitlements $APP
echo "built $APP"
if [[ ${1:-} == --run ]]; then
  pkill -x Notchly || true
  # LaunchServices keeps the killed instance registered for a moment; plain open then fails with -600.
  while pgrep -xq Notchly; do sleep 0.1; done
  open -n $APP
fi
