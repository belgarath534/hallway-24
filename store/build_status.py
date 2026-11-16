"""Shows Hallway 24's newest builds in App Store Connect and whether Apple accepted them.
A build that never shows up in TestFlight is usually INVALID here: Apple found a problem while processing it."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import setup_game_center_helpers as h  # noqa: E402

app = h.call("GET", "/apps", params={"filter[bundleId]": h.BUNDLE})["data"][0]["id"]
builds = h.call("GET", "/builds", params={"filter[app]": app, "sort": "-uploadedDate", "limit": 6,
                                          "fields[builds]": "version,processingState,uploadedDate,expired"})["data"]
for b in builds:
    a = b["attributes"]
    print(f"Build {a['version']:>3}  {a['processingState']:<11} uploaded {a['uploadedDate']}{'  (expired)' if a.get('expired') else ''}")
if not builds:
    print("No builds found.")
