#!/bin/zsh
# Opens every File Additions dialog in one app and prints what each returned (dialogs.applescript), to check
# MTC_OSAX's dialogs by hand against the dictionary. (SatimageOSAX's never worked: they all reply -1708.)
#
#   Scripts/manual/dialogs.sh [MTC_OSAX|SatimageOSAX]
#
# Run it in Terminal or iTerm (it sends Apple events), and answer each dialog as its prompt says.

app=${1:-MTC_OSAX}
if [[ "$app" != "MTC_OSAX" && "$app" != "SatimageOSAX" ]]; then
	echo "usage: ${0:t} [MTC_OSAX|SatimageOSAX]" >&2
	exit 2
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed -E "s/use application \"MTC_OSAX\"/use application \"$app\"/" "${0:A:h}/dialogs.applescript" > "$work/dialogs.applescript"
echo "$app:"
osascript "$work/dialogs.applescript" | sed 's/^/  /'
