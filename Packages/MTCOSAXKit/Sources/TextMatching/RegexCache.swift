import Foundation

/// Keeps recently compiled patterns, since scripts often run the same `find text` or `change` in a loop.
@MainActor
public final class RegexCache {
	/// The pattern as the engines see it, in UTF-16 units: Strings are equal when canonically equivalent, so a
	/// pattern with é as one character found the compiled pattern for e and a combining accent (whose class
	/// `[é]` matches a bare e), from whichever script used it first.
	private struct Key: Hashable {
		let pattern: [UInt16]
		let syntax: RegexSyntax
		let flags: RegexFlags
	}

	private let capacity: Int
	private var entries: [Key: CompiledRegex] = [:]
	private var order: [Key] = []

	public init(capacity: Int = 64) {
		self.capacity = capacity
	}

	/// A compiled pattern, compiling it if needed.
	public func regex(_ pattern: String, syntax: RegexSyntax = .ruby, flags: RegexFlags = []) throws(RegexError) -> CompiledRegex {
		let key = Key(pattern: Array(pattern.utf16), syntax: syntax, flags: flags)
		if let cached = entries[key] {
			touch(key)
			return cached
		}
		let regex = try CompiledRegex(pattern, syntax: syntax, flags: flags)
		entries[key] = regex
		touch(key)
		if order.count > capacity {
			entries[order.removeFirst()] = nil
		}
		return regex
	}

	public var count: Int { entries.count }

	private func touch(_ key: Key) {
		order.removeAll { $0 == key }
		order.append(key)
	}
}
