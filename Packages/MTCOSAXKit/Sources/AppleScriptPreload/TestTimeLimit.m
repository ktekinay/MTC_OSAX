// For tests only: a time limit for each test process, so a test that runs away is stopped.
//
// A test once ran fileremove "/" against code that accepted it, which went through the whole disk, every mounted
// volume included, for ten minutes before it was stopped by hand. Swift Testing's `.timeLimit` only cancels a
// test's task, and code that doesn't check for cancellation (FileManager, libxml2, a regex) runs on regardless, so
// this ends the process itself. A process's tests take seconds (fixture replay, the slowest, about 10, a few times
// that with AddressSanitizer): the default of three minutes only stops what has gone wrong.
//
// MTC_TEST_TIME_LIMIT sets the limit in seconds (0 for none). There's none while a debugger is attached, so stopping
// at a breakpoint doesn't end the process.

#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <unistd.h>

static const double defaultLimit = 180;

static BOOL mtc_debugger_attached(void) {
	struct kinfo_proc info = {0};
	size_t size = sizeof(info);
	int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
	return sysctl(name, 4, &info, &size, NULL, 0) == 0 && (info.kp_proc.p_flag & P_TRACED) != 0;
}

__attribute__((constructor, used)) static void mtc_limit_test_time(void) {
	double limit = defaultLimit;
	const char *setting = getenv("MTC_TEST_TIME_LIMIT");
	if (setting != NULL) {
		limit = atof(setting);
	}
	if (limit <= 0 || mtc_debugger_attached()) {
		return;
	}
	// On a queue of its own, so it fires whatever the main thread (where commands run) is doing.
	dispatch_queue_t queue = dispatch_queue_create("MTCTestTimeLimit", DISPATCH_QUEUE_SERIAL);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)), queue, ^{
		if (mtc_debugger_attached()) {
			return;
		}
		char message[200];
		int length = snprintf(message, sizeof(message),
			"\nTest process stopped: it ran longer than its time limit of %.0f seconds (MTC_TEST_TIME_LIMIT).\n", limit);
		write(STDERR_FILENO, message, (size_t)length);
		_exit(124);
	});
}
