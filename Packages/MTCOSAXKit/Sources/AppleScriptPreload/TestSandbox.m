// For tests only: the tests run in a sandbox, or not at all.
//
// Many tests create, change and delete files, and a test that goes wrong acts with the code under test: one ran
// fileremove "/" against code that accepted it. Scripts/test.sh runs the tests in a sandbox that lets them write only
// where they must, but nothing made them start there: bare `swift test`, `xcodebuild test` and Xcode's Test action
// (with the debugger attached, so without the time limit either) ran every file-command test and fixture replay
// with nothing in the way. A test bundle now ends its process as it's loaded, before any test runs, unless the
// process is sandboxed.
//
// MTC_ALLOW_UNSANDBOXED_TESTS (set to anything) runs them without one, for debugging a test in Xcode.

#import <Foundation/Foundation.h>
#import <unistd.h>

// libsystem_sandbox's check, which has no public header. With no operation, it only says whether the process is in
// a sandbox: 1 if so.
extern int sandbox_check(pid_t pid, const char *operation, int type, ...);

// Before the other constructors (AppleScript's load, the time limit), which have no priority.
__attribute__((constructor(101), used)) static void mtc_require_test_sandbox(void) {
	if (sandbox_check(getpid(), NULL, 0) == 1 || getenv("MTC_ALLOW_UNSANDBOXED_TESTS") != NULL) {
		return;
	}
	static const char message[] =
		"\nThese tests create, change and delete files, so they only run in a sandbox: run them with Scripts/test.sh.\n"
		"(MTC_ALLOW_UNSANDBOXED_TESTS=1 runs them without one.)\n";
	write(STDERR_FILENO, message, sizeof(message) - 1);
	_exit(78);
}
