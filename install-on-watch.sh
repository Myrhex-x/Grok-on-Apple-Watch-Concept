#!/bin/zsh
# Builds Grok and installs it on your Apple Watch, then says until when it will run.
#
# Before running: the iPhone unlocked and connected to this Mac (cable, or the same Wi-Fi once it
# has been used from Xcode), the watch on your wrist and unlocked, and Developer Mode on the watch
# (Settings > Privacy & Security > Developer Mode; it shows up once Xcode has seen the watch).
#
#   ./install-on-watch.sh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build

devices=$(mktemp -t grokwatch-devices)
trap 'rm -f "$devices"' EXIT
xcrun devicectl list devices --json-output "$devices" >/dev/null 2>&1 || true
watch=$(/usr/bin/python3 -I - "$devices" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for device in devices:
    hardware = device.get("hardwareProperties", {})
    if hardware.get("platform") == "watchOS" and hardware.get("reality") == "physical":
        name = device.get("deviceProperties", {}).get("name", "Apple Watch")
        print(device.get("identifier", ""), hardware.get("udid", ""), name, sep="\t")
        break
EOF
)
if [[ -z "$watch" ]]; then
  echo "No Apple Watch found. Unlock the iPhone, connect it to this Mac, keep the watch on your wrist, then run this again."
  exit 1
fi
identifier=${watch%%$'\t'*}
rest=${watch#*$'\t'}
udid=${rest%%$'\t'*}
name=${rest#*$'\t'}
echo "Building for $name..."

if ! xcodebuild -project GrokWatch.xcodeproj -scheme GrokWatch -configuration Release \
    -destination "platform=watchOS,id=$udid" -derivedDataPath build/dd \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    build > build/install.log 2>&1; then
  /usr/bin/grep -E 'error:' build/install.log | sort -u | head -20
  echo "Build failed (full log: build/install.log)."
  exit 1
fi

app=build/dd/Build/Products/Release-watchos/GrokWatch.app
echo "Installing on $name..."
if ! xcrun devicectl device install app --device "$identifier" "$app"; then
  echo "The install did not go through. Open GrokWatch.xcodeproj in Xcode, pick the watch as the destination and press Cmd-R."
  exit 1
fi

# The install runs until the profile or its development certificate ends, whichever comes first.
security cms -D -i "$app/embedded.mobileprovision" > build/profile.plist 2>/dev/null
/usr/bin/python3 -I - build/profile.plist <<'EOF'
import plistlib, subprocess, sys
from datetime import datetime, timezone
profile = plistlib.load(open(sys.argv[1], "rb"))
ends = [profile["ExpirationDate"].replace(tzinfo=timezone.utc)]
for der in profile.get("DeveloperCertificates", []):
    out = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-enddate"], input=der, capture_output=True).stdout.decode()
    if out.startswith("notAfter="):
        ends.append(datetime.strptime(out.strip()[9:], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc))
end = min(ends).astimezone()
print(f"Installed. It runs until {end:%d %B %Y, %H:%M}; the watch reminds you a week before.")
EOF
