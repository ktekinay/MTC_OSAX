import Foundation

/// Calls `onIdle` once no activity has happened for the timeout. Never fires while an activity is in progress.
/// The timeout is asked for each time the countdown starts, so a changed setting applies from the next countdown;
/// nil means never.
@MainActor
public final class IdleMonitor {
	private let timeout: @MainActor () -> Duration?
	private let onIdle: @MainActor () -> Void
	private var activeCount = 0
	private var pending: Task<Void, Never>?

	public init(timeout: @escaping @MainActor () -> Duration?, onIdle: @escaping @MainActor () -> Void) {
		self.timeout = timeout
		self.onIdle = onIdle
	}

	public convenience init(timeout: Duration, onIdle: @escaping @MainActor () -> Void) {
		self.init(timeout: { timeout }, onIdle: onIdle)
	}

	/// The timeout set in `defaults` under `key`, in seconds: 0 means never; missing, negative or not a number
	/// means `defaultTimeout`.
	public static func timeout(in defaults: UserDefaults, key: String, default defaultTimeout: Duration) -> Duration? {
		guard let seconds = (defaults.object(forKey: key) as? NSNumber)?.doubleValue ?? (defaults.string(forKey: key)).flatMap(Double.init),
		      seconds.isFinite, seconds >= 0
		else {
			return defaultTimeout
		}
		return seconds == 0 ? nil : .seconds(seconds)
	}

	/// Starts the countdown.
	public func start() {
		schedule()
	}

	public func beginActivity() {
		activeCount += 1
		pending?.cancel()
		pending = nil
	}

	public func endActivity() {
		activeCount = max(activeCount - 1, 0)
		if activeCount == 0 {
			schedule()
		}
	}

	private func schedule() {
		pending?.cancel()
		pending = nil
		guard let timeout = timeout() else {
			return
		}
		pending = Task { [weak self] in
			try? await Task.sleep(for: timeout)
			guard !Task.isCancelled, let self, activeCount == 0 else {
				return
			}
			onIdle()
		}
	}
}
