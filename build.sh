#!/bin/sh
# Builds the app into ~/Applications/DualSense Battery.app and restarts it.
set -e
cd "$(dirname "$0")"
A="$HOME/Applications/DualSense Battery.app"
mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources"
swiftc -O *.swift -o "$A/Contents/MacOS/DualSenseBattery"
cp Resources/* "$A/Contents/Resources/"
cp Info.plist "$A/Contents/Info.plist"
codesign -f -s - "$A"
pkill -x DualSenseBattery || true
sleep 1
launchctl kickstart -k "gui/$(id -u)/local.dualsense.battery" 2>/dev/null || open "$A"
