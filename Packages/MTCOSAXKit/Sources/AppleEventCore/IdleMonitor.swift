import Foundation

/// Calls `onIdle` once no activity has happened for the timeout. Never fires while an activity is in progress.
/// Every activity starts the countdown again. The timeout is asked for each time the countdown starts, so a changed
/// setting applies from the next countdown; nil means never.
///
/// When the countdown ends, `drain` runs first: it handles whatever is waiting (the app's is the commands already in
/// its event queue). If that was any activity, the app isn't idle after all, and the countdown has started again.
/// Without it, a command that arrived just as the countdown ended was still in the queue when the app quit, and its
/// script got error -609. (It narrows that; it can't close it: a command sent as the process goes still fails.)
@MainActor
public final class IdleMonitor {
	private let timeout: @MainActor () -> Duration?
	private let drain: (@MainActor () -> Void)?
	private let onIdle: @MainActor () -> Void
	private var activeCount = 0
	/// How many activities have begun, to tell whether `drain` handled any.
	private var activitiesBegun = 0
	private var pending: Task<Void, Never>?

	public init(timeout: @escaping @MainActor () -> Duration?, drain: (@MainActor () -> Void)? = nil, onIdle: @escaping @MainActor () -> Void) {
		self.timeout = timeout
		self.drain = drain
		self.onIdle = onIdle
	}

	public convenience init(timeout: Duration, drain: (@MainActor () -> Void)? = nil, onIdle: @escaping @MainActor () -> Void) {
		self.init(timeout: { timeout }, drain: drain, onIdle: onIdle)
	}

	/// The timeout set in `defaults` under `key`, in seconds: 0 means never; anything `seconds(in:key:)` doesn't
	/// accept means `defaultTimeout`.
	public nonisolated static func timeout(in defaults: UserDefaults, key: String, default defaultTimeout: Duration) -> Duration? {
		guard let seconds = seconds(in: defaults, key: key) else {
			return defaultTimeout
		}
		return seconds == 0 ? nil : .seconds(seconds)
	}

	/// The seconds stored under `key`: a number, or numeric text, from 0 to `Int32.max` (what `mtc_set` allows);
	/// nil otherwise. `defaults write` can store anything: 1e30 overflowed `Duration` and crashed the app at every
	/// launch, and `-bool YES` is a number 1.
	public nonisolated static func seconds(in defaults: UserDefaults, key: String) -> Double? {
		let object = defaults.object(forKey: key)
		let seconds: Double? = switch object {
		case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): number.doubleValue
		case let text as String: Double(text)
		default: nil
		}
		guard let seconds, seconds.isFinite, seconds >= 0, seconds <= Double(Int32.max) else {
			return nil
		}
		return seconds
	}

	/// Starts the countdown.
	public func start() {
		schedule()
	}

	public func beginActivity() {
		activeCount += 1
		activitiesBegun &+= 1
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
			// Whatever is waiting is handled first. An activity among it started a new countdown (in place of this
			// one, which is done either way).
			let begun = activitiesBegun
			drain?()
			guard activitiesBegun == begun, activeCount == 0 else {
				return
			}
			onIdle()
		}
	}
}
