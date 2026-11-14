#!/bin/zsh
# Puts your SpaceXAI key into Grok on the watch, so you never type it.
#
#   1. Copy the key on this Mac (console.x.ai, or your password manager).
#   2. ./install-key.sh
#
# The key is never shown and never stays on disk: it goes from the clipboard into a private
# temporary folder (deleted on exit), is checked with SpaceXAI (listing models is free), then
# copied into Grok's own folder on the watch, where the app moves it into the watch's Keychain
# and deletes the file. `./install-key.sh < file` reads the key from a file instead.
set -euo pipefail
cd "${0:A:h}"

if [[ -t 0 ]]; then
  key=$(pbpaste | tr -d '[:space:]')
else
  key=$(tr -d '[:space:]')
fi
if [[ ! "$key" =~ ^xai-[A-Za-z0-9_-]{20,}$ ]]; then
  echo "No SpaceXAI key found (it starts with xai-). Copy the key on this Mac, then run this again."
  exit 1
fi

work=$(mktemp -d -t grokwatch-key)
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
print -rn -- "$key" > "$work/import-key.txt"
print -r -- "Authorization: Bearer $key" > "$work/auth"
unset key

# The header comes from a file, so the key never shows in the process list.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H @"$work/auth" https://api.x.ai/v1/models || true)
case "$code" in
  200) echo "SpaceXAI accepts the key." ;;
  400|401) echo "SpaceXAI refuses this key. Check that you copied all of it, then run this again."; exit 1 ;;
  403) echo "This key is not allowed to list models; sending it anyway, the first question will tell." ;;
  *) echo "Could not reach SpaceXAI to check the key (HTTP ${code:-none}); sending it anyway." ;;
esac

xcrun devicectl list devices --json-output "$work/devices.json" >/dev/null 2>&1 || true
watch=$(/usr/bin/python3 -I - "$work/devices.json" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for device in devices:
    hardware = device.get("hardwareProperties", {})
    if hardware.get("platform") == "watchOS" and hardware.get("reality") == "physical":
        print(device.get("identifier", ""), device.get("deviceProperties", {}).get("name", "Apple Watch"), sep="\t")
        break
EOF
)
if [[ -z "$watch" ]]; then
  echo "No Apple Watch found. Keep the iPhone connected to this Mac and the watch on your wrist, unlocked, then run this again."
  exit 1
fi
identifier=${watch%%$'\t'*}
name=${watch#*$'\t'}

echo "Sending the key to Grok on $name..."
if ! xcrun devicectl device copy to --device "$identifier" --domain-type appDataContainer \
    --domain-identifier com.myrhex.GrokWatch.watchkitapp --source "$work/import-key.txt" \
    --destination Library/Caches/import-key.txt --timeout 90 > "$work/copy.log" 2>&1; then
  echo "The watch could not be reached. Turn Bluetooth off on the iPhone (Settings > Bluetooth) for a minute so the watch joins Wi-Fi, then run this again."
  exit 1
fi

# Opening Grok makes it take the key at once.
xcrun devicectl device process launch --device "$identifier" --terminate-existing com.myrhex.GrokWatch.watchkitapp >/dev/null 2>&1 || true
sleep 3
if xcrun devicectl device info files --device "$identifier" --domain-type appDataContainer \
    --domain-identifier com.myrhex.GrokWatch.watchkitapp --subdirectory Library/Caches 2>/dev/null | /usr/bin/grep -q 'import-key.txt'; then
  echo "The key is on the watch. Open Grok on the watch to finish."
else
  echo "Done: Grok on the watch has your key."
fi
