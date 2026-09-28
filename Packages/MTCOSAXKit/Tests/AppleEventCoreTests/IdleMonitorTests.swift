import Foundation
import Testing
import TestSupport
@testable import AppleEventCore

@MainActor
struct IdleMonitorTests {
	@Test func firesAfterTimeout() async throws {
		var fired = 0
		let monitor = IdleMonitor(timeout: .milliseconds(50)) { fired += 1 }
		monitor.start()
		try await Task.sleep(for: .milliseconds(300))
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
		try await Task.sleep(for: .milliseconds(300))
		#expect(fired == 1)
	}

	@Test func activityRestartsTimeout() async throws {
		var fired = 0
		let monitor = IdleMonitor(timeout: .milliseconds(400)) { fired += 1 }
		monitor.start()
		for _ in 0 ..< 4 {
			try await Task.sleep(for: .milliseconds(200))
			monitor.beginActivity()
			monitor.endActivity()
		}
		#expect(fired == 0)
		try await Task.sleep(for: .milliseconds(800))
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

	@Test func changedTimeoutAppliesToTheNextCountdown() async throws {
		var fired = 0
		var timeout: Duration? = nil
		let monitor = IdleMonitor(timeout: { timeout }) { fired += 1 }
		monitor.start()
		timeout = .milliseconds(50)
		try await Task.sleep(for: .milliseconds(200))
		#expect(fired == 0)
		monitor.beginActivity()
		monitor.endActivity()
		try await Task.sleep(for: .milliseconds(300))
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
