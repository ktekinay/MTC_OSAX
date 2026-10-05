import Foundation

/// Text as UTF-16 code units, the unit Satimage (and `NSString`) uses for positions and lengths.
public struct UTF16Text: Equatable, Sendable {
	public let units: [UInt16]
	/// Whether every surrogate is half of a pair. Text from a String always is; units given as such are checked
	/// once here, so a search needn't check the text again at every match.
	public let isValidUTF16: Bool

	/// A string's UTF-16, a lone surrogate becoming U+FFFD (as its `utf16` view gives it), so it's always valid.
	/// Copied in one step through NSString: text from an Apple event is an NSString underneath, and going through
	/// the `utf16` view unit by unit took 7 ms a megabyte, most of the time of a search that finds one match.
	public init(_ string: String) {
		let text = string as NSString
		let length = text.length
		var units = [UInt16](unsafeUninitializedCapacity: length) { buffer, count in
			if length > 0 { text.getCharacters(buffer.baseAddress!, range: NSRange(location: 0, length: length)) }
			count = length
		}
		var index = 0
		while index < length {
			let unit = units[index]
			if unit & 0xF800 != 0xD800 {
				index += 1
			} else if UTF16.isLeadSurrogate(unit), index + 1 < length, UTF16.isTrailSurrogate(units[index + 1]) {
				index += 2
			} else {
				units[index] = 0xFFFD
				index += 1
			}
		}
		self.units = units
		isValidUTF16 = true
	}

	public init(units: [UInt16]) {
		self.units = units
		var index = 0
		var valid = true
		while index < units.count {
			let unit = units[index]
			if UTF16.isLeadSurrogate(unit), index + 1 < units.count, UTF16.isTrailSurrogate(units[index + 1]) {
				index += 2
			} else if unit & 0xF800 == 0xD800 {
				valid = false
				break
			} else {
				index += 1
			}
		}
		isValidUTF16 = valid
	}

	/// Whether `offset` falls between the two halves of a surrogate pair.
	public func splitsPair(at offset: Int) -> Bool {
		offset > 0 && offset < count && UTF16.isLeadSurrogate(units[offset - 1]) && UTF16.isTrailSurrogate(units[offset])
	}

	public var count: Int { units.count }

	public var string: String {
		Self.string(units)
	}

	public subscript(range: Range<Int>) -> String {
		Self.string(units[range])
	}

	/// UTF-16 as a string, a lone surrogate becoming U+FFFD, as `String(decoding:as:)` makes it. That goes through
	/// Swift's generic decoding one character at a time, which was 44 to 62% of `change` and `splittext`; this
	/// writes the UTF-8 directly, about 15 times as fast.
	public static func string(_ units: some Collection<UInt16>) -> String {
		units.withContiguousStorageIfAvailable(string(buffer:)) ?? Array(units).withUnsafeBufferPointer(string(buffer:))
	}

	private static func string(buffer units: UnsafeBufferPointer<UInt16>) -> String {
		// Each unit makes at most 3 bytes (a surrogate pair's 4 bytes come from 2 units).
		String(unsafeUninitializedCapacity: units.count * 3) { bytes in
			var written = 0
			var index = 0
			func put(_ byte: UInt32) {
				bytes[written] = UInt8(truncatingIfNeeded: byte)
				written += 1
			}
			while index < units.count {
				var scalar = UInt32(units[index])
				index += 1
				if UTF16.isLeadSurrogate(UInt16(scalar)), index < units.count, UTF16.isTrailSurrogate(units[index]) {
					scalar = 0x10000 + ((scalar - 0xD800) << 10) + (UInt32(units[index]) - 0xDC00)
					index += 1
				} else if scalar & 0xF800 == 0xD800 {
					scalar = 0xFFFD
				}
				switch scalar {
				case ..<0x80:
					put(scalar)
				case ..<0x800:
					put(0xC0 | scalar >> 6)
					put(0x80 | scalar & 0x3F)
				case ..<0x10000:
					put(0xE0 | scalar >> 12)
					put(0x80 | scalar >> 6 & 0x3F)
					put(0x80 | scalar & 0x3F)
				default:
					put(0xF0 | scalar >> 18)
					put(0x80 | scalar >> 12 & 0x3F)
					put(0x80 | scalar >> 6 & 0x3F)
					put(0x80 | scalar & 0x3F)
				}
			}
			return written
		}
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
