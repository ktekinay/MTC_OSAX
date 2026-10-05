import COnigmo
import CPCRE2
import Foundation

/// A time limit for a command's regex searches together. Neither engine limits time: Onigmo only its stack, and
/// PCRE2 its backtracking at each starting position, so `(a*)*b` on a line of `a`s, or `(?:a|b)*c` on a long text,
/// held up every script for minutes. Past the deadline a search stops with the engine's limit error (-15, or
/// -3047), saying it took too long; the engines check it through MTC_OSAX's patches (see their mtc_deadline.c).
public enum RegexDeadline {
	/// The time, in seconds, a command's searches get unless it says otherwise: well within AppleScript's two-minute
	/// timeout, and far more than ordinary searches need.
	public static let budget: TimeInterval = 60

	private static let key = "MTCRegexDeadline"

	/// Runs `body` (a command) with its searches limited to `seconds` in all. Per thread; an inner budget keeps the
	/// outer one.
	public static func withBudget<T>(_ seconds: TimeInterval = budget, _ body: () throws -> T) rethrows -> T {
		guard Thread.current.threadDictionary[key] == nil else { return try body() }
		let deadline = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + UInt64(max(seconds, 0) * 1_000_000_000)
		Thread.current.threadDictionary[key] = true
		mtc_onig_set_deadline(deadline)
		mtc_pcre2_set_deadline(deadline)
		defer {
			Thread.current.threadDictionary[key] = nil
			mtc_onig_set_deadline(0)
			mtc_pcre2_set_deadline(0)
		}
		return try body()
	}

	/// The error for a search stopped at the deadline, with the engine's limit number.
	static func tookTooLong(code: Int) -> RegexError {
		RegexError(code: code, message: "The search took too long and was stopped: the pattern backtracks a great deal on this "
			+ "text (such as nested repetition, like (a*)*b).", isExtension: true)
	}
}
