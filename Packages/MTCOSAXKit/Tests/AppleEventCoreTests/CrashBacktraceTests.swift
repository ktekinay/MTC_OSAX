import Foundation
import Testing

/// The test bundles' crash handler (TestCrashBacktrace.m, in AppleScriptPreload): a crash writes a backtrace to
/// standard error, and still ends the process with its signal, so swift test reports it as before.
struct CrashBacktraceTests {
	@Test func badAccess() async throws {
		let result = try #require(await #expect(processExitsWith: .failure, observing: [\.exitStatus, \.standardErrorContent]) {
			UnsafeMutablePointer<Int>(bitPattern: 16)!.pointee = 1
		})
		let text = String(decoding: result.standardErrorContent, as: UTF8.self)
		#expect(result.exitStatus == .signal(SIGSEGV) || result.exitStatus == .signal(SIGBUS))
		#expect(text.contains("Test process crashed: signal") && text.contains("at address 0x10"), "\(text)")
		#expect(text.contains("mtc_write_backtrace"), "\(text)")
	}

	@Test func swiftTrap() async throws {
		let result = try #require(await #expect(processExitsWith: .signal(SIGTRAP), observing: [\.standardErrorContent]) {
			fatalError("A trap for the crash handler's test.")
		})
		let text = String(decoding: result.standardErrorContent, as: UTF8.self)
		#expect(text.contains("A trap for the crash handler's test.") && text.contains("Test process crashed: signal \(SIGTRAP)"), "\(text)")
	}
}
