#!/bin/zsh
# Runs a shell command in the shared iTerm runner window and prints its output.
# Use this for anything that sends Apple events (osascript, fixture recording),
# since processes started from VS Code can't get Automation permission.
#
#   Scripts/iterm-run.sh [-t seconds] 'osascript -e "..."'
#
# Exits with the command's exit code, or 124 on timeout. A job that hasn't started when it times out is taken
# out of the queue; one that's running is left to finish, and its output is thrown away.
#
# Security: the queue (a folder only you can write to) runs whatever is put in it, with iTerm's Automation
# permission, while a runner window is open. Any program running as you could use that to send Apple events it
# couldn't send itself. It's a development tool: close the runner window when you're done.

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
		# Not started: dequeue it, so it doesn't run whenever a runner next appears. Running: the runner
		# deletes its results when it's done.
		if ! rm "$QUEUE/$id.job" 2>/dev/null; then
			touch "$QUEUE/$id.abandoned"
		fi
		echo "Timed out after ${TIMEOUT}s waiting for job $id." >&2
		exit 124
	fi
	sleep 0.2
done

cat "$QUEUE/$id.out"
code=$(cat "$QUEUE/$id.status")
rm -f "$QUEUE/$id.out" "$QUEUE/$id.status"
exit $code
