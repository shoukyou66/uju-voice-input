#!/usr/bin/env bash
# Print an xcodebuild destination for an available iPhone on the newest iOS runtime.
set -euo pipefail
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
def version(runtime):
    # iOS-27-0, or with a device suffix such as iOS-27-0-iPhone19
    return [int(x) for x in re.findall(r"\d+", runtime.rsplit("iOS-", 1)[1])[:2]]
runtimes = sorted((r for r in data if "iOS" in r), key=version)
for r in reversed(runtimes):
    phones = [d for d in data[r] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[-1]["udid"]); break
')
[[ -n "$udid" ]] || { echo "no iPhone simulator found" >&2; exit 1; }
echo "platform=iOS Simulator,id=$udid"
