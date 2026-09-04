#!/bin/bash
# Builds a signed, notarized Peek.zip for a GitHub release, so users can just
# download and drag it to Applications — no Terminal, no security warning.
#
# One-time setup for notarization:
#   xcrun notarytool store-credentials "notarytool" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
set -e
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh 1.0.0}"
SIGN_IDENTITY="${PEEK_SIGN_IDENTITY:-Developer ID Application: Nick Algner (WYMGXK6UJW)}"
APP="build/Peek.app"
ZIP="build/Peek.zip"

# Keep Info.plist in sync with the release version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Info.plist

swift build -c release
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Peek "$APP/Contents/MacOS/Peek"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

if xcrun notarytool history --keychain-profile "notarytool" >/dev/null 2>&1; then
    echo "Submitting to Apple for notarization (this takes a few minutes)..."
    xcrun notarytool submit "$ZIP" --keychain-profile "notarytool" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Notarized: $ZIP"
else
    echo
    echo "WARNING: no 'notarytool' keychain profile found — this build is NOT notarized."
    echo "Users downloading it will see a Gatekeeper warning. See the header of this"
    echo "script for the one-time setup command."
fi

echo "Release artifact ready: $ZIP"
echo "Attach it with: gh release create v$VERSION \"$ZIP\" --title \"v$VERSION\" --notes \"...\""
