// MTC_OSAX: a deadline for searches, checked by the MTC_OSAX patch in regexec.c's match_at, where it backtracks. Not part of Onigmo.
//
// Onigmo's own limit (of the memory its backtracking may take) doesn't bound a search's
// time: a pattern that backtracks exponentially, or a lot at every position of a long text, held up every script for
// minutes. MTC_OSAX sets a deadline for a command's searches (RegexDeadline in TextMatching); past it, the search
// stops with the engine's limit error, and mtc_onig_took_too_long says why. Per thread, as searches are.

#include <stdint.h>
#include <time.h>

static _Thread_local uint64_t deadline; // CLOCK_UPTIME_RAW nanoseconds, or 0 for none
static _Thread_local int timedOut;

void mtc_onig_set_deadline(uint64_t nanoseconds) {
	deadline = nanoseconds;
	timedOut = 0;
}

int mtc_onig_deadline_passed(void) {
	if (deadline != 0 && clock_gettime_nsec_np(CLOCK_UPTIME_RAW) >= deadline) {
		timedOut = 1;
		return 1;
	}
	return 0;
}

int mtc_onig_took_too_long(void) {
	int result = timedOut;
	timedOut = 0;
	return result;
}
