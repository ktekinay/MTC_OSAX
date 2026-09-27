import Foundation

/// Text as UTF-16 code units, the unit Satimage (and `NSString`) uses for positions and lengths.
public struct UTF16Text: Equatable, Sendable {
	public let units: [UInt16]

	public init(_ string: String) {
		units = Array(string.utf16)
	}

	public init(units: [UInt16]) {
		self.units = units
	}

	public var count: Int { units.count }

	public var string: String {
		String(decoding: units, as: UTF16.self)
	}

	public subscript(range: Range<Int>) -> String {
		String(decoding: units[range], as: UTF16.self)
	}

	/// The offset after the character at `offset`: skips both halves of a surrogate pair.
	public func index(after offset: Int) -> Int {
		guard offset < count else { return count }
		if UTF16.isLeadSurrogate(units[offset]), offset + 1 < count, UTF16.isTrailSurrogate(units[offset + 1]) {
			return offset + 2
		}
		return offset + 1
	}
}
