import Foundation

/// Calls `onIdle` once no activity has happened for `timeout`. Never fires while an activity is in progress.
@MainActor
public final class IdleMonitor {
	public let timeout: Duration
	private let onIdle: @MainActor () -> Void
	private var activeCount = 0
	private var pending: Task<Void, Never>?

	public init(timeout: Duration, onIdle: @escaping @MainActor () -> Void) {
		self.timeout = timeout
		self.onIdle = onIdle
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
		pending = Task { [weak self, timeout] in
			try? await Task.sleep(for: timeout)
			guard !Task.isCancelled, let self, activeCount == 0 else {
				return
			}
			onIdle()
		}
	}
}
