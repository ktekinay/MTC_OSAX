#!/bin/zsh
# Runs the same AppleScript against SatimageOSAX and MTC_OSAX and compares the output.
# The script must contain `use application "MTC_OSAX"` (or "SatimageOSAX"); only that line is switched.
# Sends Apple events, so run it through iTerm:
#
#   Scripts/iterm-run.sh Scripts/parity.sh Scripts/e2e/text.applescript
#
# Exits non-zero if the outputs differ.

if [[ $# -ne 1 || ! -f "$1" ]]; then
	echo "usage: ${0:t} script.applescript" >&2
	exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for app in SatimageOSAX MTC_OSAX; do
	sed -E "s/use application \"(MTC_OSAX|SatimageOSAX)\"/use application \"$app\"/" "$1" > "$work/$app.applescript"
	osascript "$work/$app.applescript" > "$work/$app.out" 2>&1
	echo "exit $?" >> "$work/$app.out"
done

if diff -u "$work/SatimageOSAX.out" "$work/MTC_OSAX.out" > "$work/diff"; then
	echo "✓ Same output from both apps:"
	sed 's/^/  /' "$work/MTC_OSAX.out"
else
	echo "✗ Outputs differ (- SatimageOSAX, + MTC_OSAX):"
	cat "$work/diff"
	exit 1
fi
