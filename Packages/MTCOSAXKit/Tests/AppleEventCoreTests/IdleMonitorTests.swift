import Foundation
import Testing
import TestSupport
@testable import AppleEventCore

/// Waits (up to 30 seconds; it returns as soon as it holds) until `condition` holds: the timer fires late when many test
/// processes run at once, much later with AddressSanitizer, and a fixed wait failed now and then.
@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
	let deadline = ContinuousClock.now + .seconds(30)
	while !condition(), ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(10))
	}
}

@MainActor
struct IdleMonitorTests {
	@Test func firesAfterTimeout() async throws {
		var fired = 0
		let monitor = IdleMonitor(timeout: .milliseconds(50)) { fired += 1 }
		monitor.start()
		try await waitUntil { fired > 0 }
		try await Task.sleep(for: .milliseconds(100))
		#expect(fired == 1)
	}

	@Test func doesNotFireDuringActivity() async throws {
		var fired = 0
		let monitor = IdleMonitor(timeout: .milliseconds(50)) { fired += 1 }
		monitor.start()
		monitor.beginActivity()
		try await Task.sleep(for: .milliseconds(300))
		#expect(fired == 0)

		monitor.endActivity()
		try await waitUntil { fired > 0 }
		#expect(fired == 1)
	}

	@Test func activityRestartsTimeout() async throws {
		var fired = 0
		// Five times the step between activities, so a slow step isn't taken for idleness.
		let monitor = IdleMonitor(timeout: .milliseconds(1000)) { fired += 1 }
		monitor.start()
		for _ in 0 ..< 4 {
			try await Task.sleep(for: .milliseconds(200))
			monitor.beginActivity()
			monitor.endActivity()
		}
		#expect(fired == 0)
		try await waitUntil { fired > 0 }
		#expect(fired == 1)
	}

	@Test func noTimeoutNeverFires() async throws {
		var fired = 0
		let monitor = IdleMonitor(timeout: { nil }) { fired += 1 }
		monitor.start()
		monitor.beginActivity()
		monitor.endActivity()
		try await Task.sleep(for: .milliseconds(200))
		#expect(fired == 0)
	}

	/// What's waiting when the countdown ends is handled first, and if that was a command the app isn't idle: a
	/// command that arrived just then was left in the queue as the app quit, and failed with -609.
	@Test func waitingActivityKeepsTheAppRunning() async throws {
		var fired = 0
		var drains = 0
		final class Waiting { var commands = 1; var monitor: IdleMonitor? }
		let waiting = Waiting()
		let monitor = IdleMonitor(timeout: .milliseconds(50), drain: {
			drains += 1
			// One command is in the queue the first time.
			if waiting.commands > 0 {
				waiting.commands -= 1
				waiting.monitor?.beginActivity()
				waiting.monitor?.endActivity()
			}
		}) { fired += 1 }
		waiting.monitor = monitor
		monitor.start()
		try await waitUntil { drains >= 1 }
		#expect(fired == 0)
		// The command started the countdown again; with nothing waiting at its end, the app is idle.
		try await waitUntil { fired > 0 }
		#expect(fired == 1 && drains == 2)
	}

	@Test func changedTimeoutAppliesToTheNextCountdown() async throws {
		var fired = 0
		// In an object: the closure is the main actor's, and a captured variable changed afterwards is a warning.
		final class Setting { var timeout: Duration? }
		let setting = Setting()
		let monitor = IdleMonitor(timeout: { setting.timeout }) { fired += 1 }
		monitor.start()
		setting.timeout = .milliseconds(50)
		try await Task.sleep(for: .milliseconds(200))
		#expect(fired == 0)
		monitor.beginActivity()
		monitor.endActivity()
		try await waitUntil { fired > 0 }
		#expect(fired == 1)
	}

	@Test func timeoutPreference() throws {
		let defaults = MemoryDefaults.make()
		let key = "IdleTimeoutSeconds"
		#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == .seconds(3600))
		defaults.set(0, forKey: key)
		#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == nil)
		defaults.set(300, forKey: key)
		#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == .seconds(300))
		defaults.set("45", forKey: key)
		#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == .seconds(45))
		defaults.set(-5, forKey: key)
		#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == .seconds(3600))
		defaults.set("abc", forKey: key)
		#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == .seconds(3600))
		// These crashed the app at launch (Duration overflows), or meant one second.
		for value in [1e30, Double(Int32.max) + 1] as [Any] + ["1e30", true] {
			defaults.set(value, forKey: key)
			#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == .seconds(3600), "\(value)")
		}
		defaults.set(Double(Int32.max), forKey: key)
		#expect(IdleMonitor.timeout(in: defaults, key: key, default: .seconds(3600)) == .seconds(Int(Int32.max)))
	}
}
