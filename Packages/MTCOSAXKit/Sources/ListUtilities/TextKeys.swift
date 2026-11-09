import Foundation

/// A list's texts as they're compared: each one's UTF-8 in a single buffer. UTF-8's byte order is character-code
/// order, so the bytes compare as the characters did. (An array of character codes for each text was an allocation
/// each, and a pointer to follow at every comparison.)
///
/// Texts are compared in Unicode's composed form (NFC), so an accent typed as a character of its own ("e" and
/// U+0301) is the same as the accented letter ("é"). Ignoring case (flags 1 and 4) compares their full case folding
/// (ß is ss, ς is σ, ﬀ is ff). With flag 4, texts that are equal ignoring case are then ordered by the case of each
/// character in turn (uppercase first, then title case, then the rest: "Ÿ" before "ÿ"), and then by the composed text.
package struct TextKeys {
	/// Where a text is in `bytes`; a count of -1 is `missing value`.
	struct Span {
		var start: Int
		var count: Int

		static let missing = Span(start: 0, count: -1)
	}

	/// Starts with a 0 that's no text's, so the buffer is never empty.
	private(set) var bytes: [UInt8] = [0]
	/// The texts as compared first: composed, and folded if case is ignored.
	private(set) var spans: [Span] = []
	/// With flag 4, each character's case (0 uppercase, 1 title case, 2 the rest), and the composed texts.
	private(set) var cases: [Span]?
	private(set) var exact: [Span]?
	private let folds: Bool

	package var count: Int {
		spans.count
	}

	/// No texts yet: `append` adds them.
	init(capacity: Int, flags: Int) {
		folds = flags & (1 | 4) != 0
		spans.reserveCapacity(capacity)
		if flags & 4 != 0 {
			cases = []
			exact = []
			cases?.reserveCapacity(capacity)
			exact?.reserveCapacity(capacity)
		}
	}

	mutating func appendMissing() {
		spans.append(.missing)
		cases?.append(.missing)
		exact?.append(.missing)
	}

	mutating func append(_ text: String) {
		var text = text
		// ASCII is composed already, and folds to lowercase.
		if text.withUTF8({ $0.allSatisfy { $0 < 0x80 } }) {
			spans.append(append(text, folded: folds))
			if exact != nil {
				let caseSpan = appendCases(text.utf8.lazy.map { Unicode.Scalar($0) })
				let exactSpan = append(text, folded: false)
				cases?.append(caseSpan)
				exact?.append(exactSpan)
			}
			return
		}
		// Latin is composed already, and folds character by character.
		if text.unicodeScalars.allSatisfy({ $0.value < Latin.end }) {
			let start = bytes.count
			if folds {
				for scalar in text.unicodeScalars {
					bytes.append(contentsOf: Latin.folded[Int(scalar.value)])
				}
			} else {
				bytes.append(contentsOf: text.utf8)
			}
			spans.append(Span(start: start, count: bytes.count - start))
			if exact != nil {
				let caseSpan = appendCases(text.unicodeScalars)
				let exactSpan = append(text, folded: false)
				cases?.append(caseSpan)
				exact?.append(exactSpan)
			}
			return
		}
		let composed = text.precomposedStringWithCanonicalMapping
		spans.append(append(folds ? Self.folded(text) : composed, folded: false))
		if exact != nil {
			let caseSpan = appendCases(composed.unicodeScalars)
			let exactSpan = append(composed, folded: false)
			cases?.append(caseSpan)
			exact?.append(exactSpan)
		}
	}

	/// A text as UTF-16 (an Apple event's `utxt`), without a String if it's ASCII or Latin, as `append` does.
	mutating func append(utf16 units: UnsafeBufferPointer<UInt16>) {
		guard units.allSatisfy({ $0 < UInt16(Latin.end) }) else {
			append(String(decoding: units, as: UTF16.self))
			return
		}
		let start = bytes.count
		if folds {
			for unit in units {
				if unit < 0x80 {
					bytes.append(UInt8(unit &- 0x41 < 26 ? unit | 0x20 : unit)) // A-Z to a-z
				} else {
					bytes.append(contentsOf: Latin.folded[Int(unit)])
				}
			}
		} else {
			appendUTF8(units)
		}
		spans.append(Span(start: start, count: bytes.count - start))
		if exact != nil {
			let caseStart = bytes.count
			bytes.append(contentsOf: units.lazy.map { Latin.caseRanks[Int($0)] })
			cases?.append(Span(start: caseStart, count: bytes.count - caseStart))
			let exactStart = bytes.count
			appendUTF8(units)
			exact?.append(Span(start: exactStart, count: bytes.count - exactStart))
		}
	}

	/// Latin UTF-16 (below U+0300) as UTF-8: one or two bytes a character.
	private mutating func appendUTF8(_ units: UnsafeBufferPointer<UInt16>) {
		for unit in units {
			if unit < 0x80 {
				bytes.append(UInt8(unit))
			} else {
				bytes.append(UInt8(0xC0 | unit >> 6))
				bytes.append(UInt8(0x80 | unit & 0x3F))
			}
		}
	}

	/// Unicode's canonical caseless form: decomposed, case folded, and composed again.
	static func folded(_ text: String) -> String {
		text.decomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping
	}

	/// The characters below U+0300 (Latin), with their case folding and case made once: Foundation's normalizing and
	/// folding for each text took most of the time to sort a list. A text of only these characters is composed (none
	/// is a combining mark), and folds character by character: each folds to text that doesn't start with a combining
	/// mark, so nothing before it composes with it. (Four fold to characters above U+0300: µ to μ, Ⱥ and Ⱦ to ⱥ and ⱦ,
	/// and İ to i and a combining dot, which doesn't compose with i.)
	private enum Latin {
		static let end: UInt32 = 0x300
		static let folded: [[UInt8]] = (0 ..< end).map { value in
			Array(TextKeys.folded(String(Unicode.Scalar(value)!)).utf8)
		}
		static let caseRanks: [UInt8] = (0 ..< end).map { TextKeys.caseRank(Unicode.Scalar($0)!) }
	}

	/// A character's case, for flag 4: 0 uppercase, 1 title case ("ǅ"), 2 lowercase or none.
	static func caseRank(_ scalar: Unicode.Scalar) -> UInt8 {
		if scalar.properties.generalCategory == .titlecaseLetter {
			return 1
		}
		return scalar.properties.isUppercase ? 0 : 2
	}

	/// Appends a text's UTF-8, with A-Z made lowercase if `folded` (for ASCII).
	private mutating func append(_ text: String, folded: Bool) -> Span {
		let start = bytes.count
		var text = text
		// A native string's UTF-8 is copied at once; a bridged one is made native first.
		text.withUTF8 { utf8 in
			if folded {
				bytes.append(contentsOf: utf8.lazy.map { $0 &- 0x41 < 26 ? $0 | 0x20 : $0 }) // A-Z to a-z
			} else {
				bytes.append(contentsOf: utf8)
			}
		}
		return Span(start: start, count: bytes.count - start)
	}

	private mutating func appendCases(_ scalars: some Sequence<Unicode.Scalar>) -> Span {
		let start = bytes.count
		bytes.append(contentsOf: scalars.lazy.map { $0.value < Latin.end ? Latin.caseRanks[Int($0.value)] : Self.caseRank($0) })
		return Span(start: start, count: bytes.count - start)
	}

	/// 8 bytes of each text as a number (big-endian, padded with zeros), in order for a radix sort: a text whose key
	/// is less than another's comes first (reversed if descending), and texts with equal keys need comparing. The
	/// bytes are those after the start every text shares (as paths in one folder do), which can't change the order.
	/// `missing value` is `UInt64.max` (no UTF-8 byte is 0xFF); a text whose key is that too, descending, compares.
	/// Not for flag 2, whose digits don't compare by byte.
	func prefixKeys(ascending: Bool) -> [UInt64] {
		bytes.withUnsafeBufferPointer { bytes in
			let present = spans.lazy.filter { $0.count >= 0 }
			var shared = present.first?.count ?? 0
			if let first = present.first {
				for span in present.dropFirst() where shared > 0 {
					shared = min(shared, span.count)
					var index = 0
					while index < shared, bytes[first.start + index] == bytes[span.start + index] { index += 1 }
					shared = index
				}
			}
			return spans.map { span in
				guard span.count >= 0 else {
					return .max
				}
				var key: UInt64 = 0
				for index in shared ..< shared + 8 {
					key = key << 8 | UInt64(index < span.count ? bytes[span.start + index] : 0)
				}
				return ascending ? key : ~key
			}
		}
	}

	/// Calls `body` with an order of the texts, which is valid only there.
	func withOrder<Result>(ascending: Bool, numeric: Bool, _ body: (TextOrder) throws -> Result) rethrows -> Result {
		try bytes.withUnsafeBufferPointer { bytes in
			try spans.withUnsafeBufferPointer { spans in
				guard let cases, let exact else {
					return try body(TextOrder(bytes: bytes.baseAddress!, spans: spans, cases: nil, exact: nil, ascending: ascending, numeric: numeric))
				}
				return try cases.withUnsafeBufferPointer { cases in
					try exact.withUnsafeBufferPointer { exact in
						try body(TextOrder(bytes: bytes.baseAddress!, spans: spans, cases: cases, exact: exact, ascending: ascending, numeric: numeric))
					}
				}
			}
		}
	}
}

/// Rows by their texts (`missing value` last in both directions): by byte, and by length when one starts the other;
/// with flag 4, then by the characters' case and the composed texts (see `TextKeys`).
/// Flag 2 (`numeric`) compares runs of digits by value ("a2" before "a10"): digits are ASCII, and no byte of a longer
/// character is a digit, so this works on UTF-8 as it did on characters.
struct TextOrder: RowOrder {
	let bytes: UnsafePointer<UInt8>
	let spans: UnsafeBufferPointer<TextKeys.Span>
	let cases: UnsafeBufferPointer<TextKeys.Span>?
	let exact: UnsafeBufferPointer<TextKeys.Span>?
	let ascending: Bool
	let numeric: Bool

	func compare(_ a: Int, _ b: Int) -> Int {
		let x = spans[a], y = spans[b]
		if x.count < 0 || y.count < 0 {
			return x.count < 0 ? (y.count < 0 ? 0 : 1) : -1
		}
		var result = compare(x, y)
		if result == 0, let cases, let exact {
			result = compareBytes(cases[a], cases[b])
			if result == 0 {
				result = compare(exact[a], exact[b])
			}
		}
		return ascending ? result : -result
	}

	private func compare(_ x: TextKeys.Span, _ y: TextKeys.Span) -> Int {
		if numeric {
			return Self.compareNumerically(bytes + x.start, x.count, bytes + y.start, y.count)
		}
		return compareBytes(x, y)
	}

	private func compareBytes(_ x: TextKeys.Span, _ y: TextKeys.Span) -> Int {
		let result = memcmp(bytes + x.start, bytes + y.start, min(x.count, y.count))
		return result != 0 ? Int(result) : x.count - y.count
	}

	static func compareNumerically(_ x: UnsafePointer<UInt8>, _ xCount: Int, _ y: UnsafePointer<UInt8>, _ yCount: Int) -> Int {
		var i = 0, j = 0
		while i < xCount, j < yCount {
			if isDigit(x[i]), isDigit(y[j]) {
				var xEnd = i, yEnd = j
				while xEnd < xCount, isDigit(x[xEnd]) { xEnd += 1 }
				while yEnd < yCount, isDigit(y[yEnd]) { yEnd += 1 }
				// Leading zeros don't count; then the longer number is larger, or the first digit that differs decides.
				while i < xEnd, x[i] == 0x30 { i += 1 }
				while j < yEnd, y[j] == 0x30 { j += 1 }
				if xEnd - i != yEnd - j {
					return (xEnd - i) - (yEnd - j)
				}
				while i < xEnd {
					if x[i] != y[j] {
						return Int(x[i]) - Int(y[j])
					}
					i += 1
					j += 1
				}
				(i, j) = (xEnd, yEnd)
				continue
			}
			if x[i] != y[j] {
				return Int(x[i]) - Int(y[j])
			}
			i += 1
			j += 1
		}
		return (xCount - i) - (yCount - j)
	}

	private static func isDigit(_ byte: UInt8) -> Bool {
		byte &- 0x30 < 10 // 0-9
	}
}

/// Rows by number keys (see `RowSort.numberKey`), already in their direction.
struct NumberOrder: RowOrder {
	let keys: UnsafeBufferPointer<UInt64>

	func compare(_ a: Int, _ b: Int) -> Int {
		let x = keys[a], y = keys[b]
		return x < y ? -1 : (x > y ? 1 : 0)
	}
}

/// Rows by one column of either kind.
enum ColumnOrder: RowOrder {
	case numbers(NumberOrder)
	case texts(TextOrder)

	func compare(_ a: Int, _ b: Int) -> Int {
		switch self {
		case let .numbers(order): order.compare(a, b)
		case let .texts(order): order.compare(a, b)
		}
	}
}

/// Rows by several columns of number keys (see `RowSort.numberKey`; text as ranks), the first that differs deciding.
struct KeysOrder: RowOrder {
	let columns: [[UInt64]]

	func compare(_ a: Int, _ b: Int) -> Int {
		for keys in columns {
			let x = keys[a], y = keys[b]
			if x != y {
				return x < y ? -1 : 1
			}
		}
		return 0
	}
}
