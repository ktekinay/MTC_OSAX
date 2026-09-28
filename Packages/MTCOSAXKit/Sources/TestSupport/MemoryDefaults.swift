import Foundation

/// Defaults for a test, kept in memory: tests get settings of their own without writing anything. (A suite of its
/// own left a file in ~/Library/Preferences for every test run, which cfprefsd writes back even after it's
/// deleted.) Foundation's getters (`string(forKey:)`, `bool(forKey:)`, …) all read through `object(forKey:)`.
public final class MemoryDefaults: UserDefaults, @unchecked Sendable {
	private let lock = NSLock()
	private var values: [String: Any] = [:]

	private init?(memory: Void) {
		super.init(suiteName: nil)
	}

	public static func make() -> MemoryDefaults {
		MemoryDefaults(memory: ())!
	}

	override public func object(forKey key: String) -> Any? {
		lock.withLock { values[key] }
	}

	override public func set(_ value: Any?, forKey key: String) {
		lock.withLock { values[key] = value }
	}

	override public func removeObject(forKey key: String) {
		lock.withLock { values[key] = nil }
	}
}
