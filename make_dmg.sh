#!/bin/sh
# Builds dist/DualDeck-<version>.dmg from the installed app (run ./build.sh first).
set -e
cd "$(dirname "$0")"
A="$HOME/Applications/DualDeck.app"
V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
ST=$(mktemp -d)
ditto "$A" "$ST/DualDeck.app"
xattr -cr "$ST"
ln -s /Applications "$ST/Aplicativos"
mkdir -p dist
hdiutil create -quiet -volname "DualDeck" -srcfolder "$ST" -ov -format UDZO "dist/DualDeck-$V.dmg"
rm -rf "$ST"
echo "dist/DualDeck-$V.dmg"
