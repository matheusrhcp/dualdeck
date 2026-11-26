#!/bin/sh
# Builds the app into ~/Applications/DualDeck.app and restarts it.
set -e
cd "$(dirname "$0")"
A="$HOME/Applications/DualDeck.app"
mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
swiftc -O *.swift -o "$A/Contents/MacOS/DualDeck"
cp Resources/* "$A/Contents/Resources/"
install -m 755 Vendor/dsmactools "$A/Contents/Resources/dsmactools"
cp Vendor/DSMACTOOLS-LICENSE.txt "$A/Contents/Resources/"
cp Info.plist "$A/Contents/Info.plist"
codesign -f -s - "$A"
pkill -x DualSenseBattery || true
pkill -x DualDeck || true
sleep 1
launchctl kickstart -k "gui/$(id -u)/local.dualsense.battery" 2>/dev/null || open "$A"
