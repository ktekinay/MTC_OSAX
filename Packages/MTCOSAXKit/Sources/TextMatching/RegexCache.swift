import Foundation

/// Keeps recently compiled patterns, since scripts often run the same `find text` or `change` in a loop.
public final class RegexCache {
	private struct Key: Hashable {
		let pattern: String
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
		let key = Key(pattern: pattern, syntax: syntax, flags: flags)
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
