#!/usr/bin/env bash
# Build build/KVoice.ipa for sideloading (SideStore, AltStore) with a free
# Apple ID. The build is unsigned; the binaries are then ad-hoc signed with
# their App Group entitlement, which the sideloading tool reads to register
# the group before it re-signs. Run after Scripts/generate.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."

group="$(sed -n 's/^KVOICE_APP_GROUP *= *//p' Config/Base.xcconfig)"
[[ -n "$group" ]] || { echo "KVOICE_APP_GROUP not found in Config/Base.xcconfig" >&2; exit 1; }

xcodebuild build \
  -project KVoice.xcodeproj -scheme KVoice -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify --renderer github-actions

app="DerivedData/Build/Products/Release-iphoneos/KVoice.app"
entitlements="$(mktemp)"
cat >"$entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>${group}</string>
	</array>
</dict>
</plist>
EOF

# Inside out: frameworks, then extensions, then the app.
shopt -s nullglob
for framework in "$app"/Frameworks/*; do
  codesign --force --sign - "$framework"
done
for appex in "$app"/PlugIns/*.appex; do
  codesign --force --sign - --generate-entitlement-der --entitlements "$entitlements" "$appex"
done
codesign --force --sign - --generate-entitlement-der --entitlements "$entitlements" "$app"
codesign --display --entitlements - "$app"

rm -rf build/ipa build/KVoice.ipa
mkdir -p build/ipa/Payload
cp -R "$app" build/ipa/Payload/
(cd build/ipa && zip -qry ../KVoice.ipa Payload)
ls -lh build/KVoice.ipa
