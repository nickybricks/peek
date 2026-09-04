#!/bin/bash
# Builds Peek, installs it into /Applications and restarts it.
set -e
cd "$(dirname "$0")"

SIGN_IDENTITY="${PEEK_SIGN_IDENTITY:-Developer ID Application: Nick Algner (WYMGXK6UJW)}"
INSTALLED="/Applications/Peek.app"

swift build -c release

APP="build/Peek.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Peek "$APP/Contents/MacOS/Peek"
cp Info.plist "$APP/Contents/Info.plist"
cp Peek.icns "$APP/Contents/Resources/Peek.icns"

# A stable signature keeps the granted permissions (Accessibility, Screen Recording)
# valid across rebuilds. Falls back to ad-hoc signing when no certificate is available —
# in that case macOS treats every build as a new app and asks again.
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
    echo "Note: no Developer ID certificate found, signing ad-hoc."
    echo "      macOS will ask for permissions again after each rebuild."
    codesign --force --sign - "$APP"
fi

# Quit the running instance, install, relaunch
pkill -f "Peek.app/Contents/MacOS/Peek" 2>/dev/null || true
sleep 0.5
rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"
open "$INSTALLED"

echo "Installed and launched: $INSTALLED"
