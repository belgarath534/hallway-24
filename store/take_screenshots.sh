#!/usr/bin/env bash
# Builds Hallway 24 for the simulator and takes the App Store screenshots on the biggest iPhone (6.9-inch)
# and the 13-inch iPad, into shots/iphone and shots/ipad. Used by the "App Store" GitHub workflow.
# The app's hidden screenshot mode opens each screen directly: see App/ScreenshotMode.swift.
set -e
xcodegen generate
xcodebuild -project Hallway24.xcodeproj -scheme Hallway24 -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | tail -5

# shoot KIND PATTERN: the newest iOS with a device whose name contains PATTERN.
shoot() {
  KIND=$1; PATTERN=$2
  read RUNTIME TYPE <<< "$(PATTERN="$PATTERN" xcrun simctl list runtimes -j | PATTERN="$PATTERN" python3 -c '
import json, os, re, sys
want = os.environ["PATTERN"]
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
def num(t):
    return [int(x) for x in re.findall(r"\d+", t["name"])]
for rt in reversed(rts):
    found = [t for t in rt.get("supportedDeviceTypes", []) if want in t["name"]]
    if found:
        print(rt["identifier"], max(found, key=num)["identifier"]); break')"
  echo "=== $KIND: device $TYPE on $RUNTIME"
  UDID=$(xcrun simctl create "Screenshots $KIND" "$TYPE" "$RUNTIME")
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl ui "$UDID" appearance dark || true
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/Hallway24.app
  mkdir -p "shots/$KIND"
  n=1
  for SCREEN in menu creature hosts practice howto; do
    xcrun simctl launch --terminate-running-process "$UDID" com.hallway24.Hallway24 -screenshot $SCREEN -language en
    # The creature screen waits for the Host to explain the Drip first.
    if [ "$SCREEN" = "creature" ]; then sleep 30; else sleep 6; fi
    xcrun simctl io "$UDID" screenshot "shots/$KIND/${n}_${SCREEN}.png"
    sips -g pixelWidth -g pixelHeight "shots/$KIND/${n}_${SCREEN}.png" | tail -2
    n=$((n+1))
  done
  xcrun simctl shutdown "$UDID" || true
}
shoot iphone "Pro Max"
shoot ipad "iPad Pro 13"
for r in ~/Library/Logs/DiagnosticReports/Hallway24*; do
  [ -f "$r" ] || continue
  echo "=== Crash report $r"; head -c 6000 "$r"; cp "$r" shots/ || true
done
