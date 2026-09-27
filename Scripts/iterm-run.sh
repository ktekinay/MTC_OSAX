#!/bin/zsh
# Runs a shell command in the shared iTerm runner window and prints its output.
# Use this for anything that sends Apple events (osascript, fixture recording),
# since processes started from VS Code can't get Automation permission.
#
#   Scripts/iterm-run.sh [-t seconds] 'osascript -e "..."'
#
# Exits with the command's exit code, or 124 on timeout.

TIMEOUT=120
if [[ "$1" == "-t" ]]; then
	TIMEOUT="$2"
	shift 2
fi
if [[ $# -eq 0 ]]; then
	echo "usage: ${0:t} [-t seconds] command..." >&2
	exit 2
fi

QUEUE="$HOME/Library/Caches/mtc-osax-runner"
PIDFILE="$QUEUE/runner.pid"
mkdir -p "$QUEUE"
chmod 700 "$QUEUE"

if ! { [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }; then
	open -a iTerm "${0:A:h}/iterm-runner.command"
	for i in {1..50}; do
		[[ -f "$PIDFILE" ]] && break
		sleep 0.2
	done
fi

id="$(date +%Y%m%d-%H%M%S)-$$"
print -r -- "cd ${(q)PWD}" > "$QUEUE/$id.tmp"
print -r -- "$*" >> "$QUEUE/$id.tmp"
mv "$QUEUE/$id.tmp" "$QUEUE/$id.job"

deadline=$(( SECONDS + TIMEOUT ))
while [[ ! -f "$QUEUE/$id.status" ]]; do
	if (( SECONDS >= deadline )); then
		echo "Timed out after ${TIMEOUT}s waiting for job $id." >&2
		exit 124
	fi
	sleep 0.2
done

cat "$QUEUE/$id.out"
code=$(cat "$QUEUE/$id.status")
rm -f "$QUEUE/$id.out" "$QUEUE/$id.status"
exit $code
