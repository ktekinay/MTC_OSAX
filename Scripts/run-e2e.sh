#!/bin/zsh
# Runs the end-to-end AppleScript checks in Scripts/e2e against the running MTC_OSAX.
# They send real Apple events, so this must run from iTerm or Terminal, not VS Code:
#
#   Scripts/iterm-run.sh Scripts/run-e2e.sh [name ...]
#
# With names (e.g. "diagnostics"), runs only those scripts. Exits non-zero if any fail.

cd "${0:A:h}/e2e" || exit 1
scripts=( ${@:-*.applescript} )
failed=0
for script in $scripts; do
	script="${script%.applescript}.applescript"
	if output=$(osascript "$script" 2>&1); then
		echo "✓ ${script%.applescript}: $output"
	else
		echo "✗ ${script%.applescript}: $output"
		failed=1
	fi
done
exit $failed
