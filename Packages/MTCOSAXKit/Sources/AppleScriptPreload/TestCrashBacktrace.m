// For tests only: a backtrace of the thread that crashed, written to standard error, for crashes that are rare.
//
// A ListUtilitiesTests process once died with signal 11 as it started its tests, and didn't again in about a hundred
// more (October 2026). The sandbox the tests run in keeps macOS from writing a crash report, so nothing said
// where. This handler writes the signal, the address, the thread, and the innermost and outermost frames (a stack that
// ran out has tens of thousands), then lets the signal end the process as it would have, so swift test reports it as
// before. It runs on an alternate stack on the main thread, so a main thread that ran out of stack is reported too;
// other threads have none, and a stack overflow there (signal 10) ends the process without a backtrace.

#import <Foundation/Foundation.h>
#import <execinfo.h>
#import <pthread.h>
#import <signal.h>
#import <unistd.h>

static const int crashSignals[] = {SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE};
static void *frames[262144];

static void mtc_write_backtrace(int signal, siginfo_t *info, void *context) {
	char message[200];
	int length = snprintf(message, sizeof(message), "\nTest process crashed: signal %d at address %p, on the %s thread.\n",
		signal, info->si_addr, pthread_main_np() ? "main" : "a secondary");
	write(STDERR_FILENO, message, (size_t)length);
	int count = backtrace(frames, sizeof(frames) / sizeof(frames[0]));
	if (count <= 100) {
		backtrace_symbols_fd(frames, count, STDERR_FILENO);
	} else {
		length = snprintf(message, sizeof(message), "%d frames; the innermost 60 and the outermost 40:\n", count);
		write(STDERR_FILENO, message, (size_t)length);
		backtrace_symbols_fd(frames, 60, STDERR_FILENO);
		write(STDERR_FILENO, "…\n", strlen("…\n"));
		backtrace_symbols_fd(frames + count - 40, 40, STDERR_FILENO);
	}
	// The signal again, as it would have been without this handler.
	struct sigaction standard = {.sa_handler = SIG_DFL};
	sigemptyset(&standard.sa_mask);
	sigaction(signal, &standard, NULL);
	raise(signal);
}

__attribute__((constructor, used)) static void mtc_install_crash_backtrace(void) {
	static char alternate[256 * 1024];
	stack_t stack = {.ss_sp = alternate, .ss_size = sizeof(alternate), .ss_flags = 0};
	sigaltstack(&stack, NULL);
	struct sigaction action = {.sa_sigaction = mtc_write_backtrace, .sa_flags = SA_SIGINFO | SA_ONSTACK};
	sigemptyset(&action.sa_mask);
	for (size_t index = 0; index < sizeof(crashSignals) / sizeof(crashSignals[0]); index++) {
		sigaction(crashSignals[index], &action, NULL);
	}
}
