#!/bin/zsh
# Runs jobs queued by iterm-run.sh inside this iTerm window, so Apple events
# are sent with iTerm's Automation permission. Only one instance runs at a time.
# Whatever is queued runs, so any program running as you can use this window's
# permission while it's open (see iterm-run.sh); close it when you're done.

QUEUE="$HOME/Library/Caches/mtc-osax-runner"
PIDFILE="$QUEUE/runner.pid"

mkdir -p "$QUEUE"
chmod 700 "$QUEUE"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
	echo "Runner already active (pid $(cat "$PIDFILE"))."
	exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"; exit' INT TERM EXIT

printf '\e]0;MTC_OSAX runner\a'
echo "MTC_OSAX runner (pid $$) watching $QUEUE"
echo "Close this window or press Ctrl-C to stop."

setopt null_glob
while true; do
	for job in "$QUEUE"/*.job; do
		id="${job:t:r}"
		mv "$job" "$QUEUE/$id.running" || continue
		echo
		echo "[$(date +%H:%M:%S)] $id: $(head -c 200 "$QUEUE/$id.running")"
		/bin/zsh "$QUEUE/$id.running" > "$QUEUE/$id.out" 2>&1
		code=$?
		rm -f "$QUEUE/$id.running"
		# The status file is written last; its presence means the job is done.
		echo $code > "$QUEUE/$id.status.tmp" && mv "$QUEUE/$id.status.tmp" "$QUEUE/$id.status"
		echo "[$(date +%H:%M:%S)] $id: exit $code"
		# Nobody is waiting for a job that timed out while it ran.
		if [[ -f "$QUEUE/$id.abandoned" ]]; then
			rm -f "$QUEUE/$id.out" "$QUEUE/$id.status" "$QUEUE/$id.abandoned"
		fi
	done
	sleep 0.3
done
