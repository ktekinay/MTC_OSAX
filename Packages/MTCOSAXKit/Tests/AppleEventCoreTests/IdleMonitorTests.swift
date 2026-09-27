import Foundation
import Testing
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
}
