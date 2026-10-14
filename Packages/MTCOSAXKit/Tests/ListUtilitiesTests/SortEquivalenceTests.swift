import AppleEventCore
import Foundation
import Testing
@testable import ListUtilities

/// `sortlist` against a plain implementation of its rules (a comparison of two texts at a time, as it first was),
/// over random lists. Texts are compared by their characters' codes, so "é" and "e" + U+0301 count as different here
/// (Swift's `==` says they're equal), which shows which one `remove duplicates` kept.
@MainActor
struct SortEquivalenceTests {
	/// Characters of every UTF-8 length (1 to 4 bytes), next to digits; and characters whose case folding isn't
	/// their lowercase, or that are uppercase with a higher code than their lowercase, or title case, or that compose
	/// with the one before (a lone U+0301 accent); Latin ones (below U+0300, folded from a table) that fold to more
	/// than one character (ǰ, İ, ŉ) or to one above U+0300 (µ, Ⱥ), and the last below it.
	private static let pieces = [
		"a", "A", "b", "B", "é", "É", "e", "z", "0", "1", "2", "9", "10", "007", " ", "-", "ß", "😀", "Ω", "ω", "€", "中",
		"\u{7F}", "\u{80}", "\u{0}", "ς", "σ", "Σ", "ẞ", "SS", "s", "ﬀ", "FF", "f", "Ÿ", "ÿ", "ǅ", "Ǆ", "ǆ", "\u{301}",
		"E\u{301}", "\u{212A}", "k", "İ", "ı", "i", "I", "ǰ", "J", "j", "\u{30C}", "µ", "μ", "ŉ", "ſ", "Ⱥ", "ⱥ", "ɐ", "\u{2FF}",
	]

	private static func randomText(_ generator: inout some RandomNumberGenerator) -> String {
		(0 ..< Int.random(in: 0 ... 5, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
	}

	@Test func textMatchesReference() {
		var generator = SeededGenerator(seed: 1)
		let texts = (0 ..< 2_000).map { _ in Self.randomText(&generator) }
		for flags in 0 ... 7 {
			for ascending in [true, false] {
				for unique in [false, true] {
					let reply = send("SATISort", ["----": texts, "Cfla": flags, "Asce": ascending, "Uniq": unique])
					let expected = Reference.sort(texts, flags: flags, ascending: ascending, unique: unique)
					#expect(codes(reply) == codes(expected), "flags \(flags), ascending \(ascending), unique \(unique)")
				}
			}
		}
	}

	/// Short lists too: sorted by inserting, merged once, and merged with a short last run.
	@Test func textMatchesReferenceAtEveryLength() {
		var generator = SeededGenerator(seed: 4)
		for count in Array(0 ... 40) + [63, 64, 65, 200] {
			let texts = (0 ..< count).map { _ in Self.randomText(&generator) }
			for flags in [0, 1, 2, 4, 6] {
				for ascending in [true, false] {
					for unique in [false, true] {
						let reply = send("SATISort", ["----": texts, "Cfla": flags, "Asce": ascending, "Uniq": unique])
						#expect(codes(reply) == codes(Reference.sort(texts, flags: flags, ascending: ascending, unique: unique)), "\(count) texts, flags \(flags), ascending \(ascending), unique \(unique)")
					}
				}
			}
		}
	}

	/// Texts that share their first 8 bytes or more (ordered by a radix sort of those bytes, then by comparing).
	@Test func textsWithACommonStartMatchReference() {
		var generator = SeededGenerator(seed: 7)
		for start in ["", "common/", "common/x", "a longer common start/"] {
			let texts = (0 ..< 300).map { _ in start + Self.randomText(&generator) }
			for flags in [0, 1, 4] {
				for ascending in [true, false] {
					for unique in [false, true] {
						let reply = send("SATISort", ["----": texts, "Cfla": flags, "Asce": ascending, "Uniq": unique])
						#expect(codes(reply) == codes(Reference.sort(texts, flags: flags, ascending: ascending, unique: unique)), "start \(start), flags \(flags), ascending \(ascending), unique \(unique)")
					}
				}
			}
		}
	}

	/// Lists sorted together by a text and a number, in both orders (with missing values in both), each in its own
	/// direction: the text becomes ranks, sorted with the number by the radix sort.
	@Test func textAndNumberKeysMatchReference() {
		var generator = SeededGenerator(seed: 5)
		let count = 1_500
		let texts: [String?] = (0 ..< count).map { _ in Int.random(in: 0 ..< 30, using: &generator) == 0 ? nil : String(Self.randomText(&generator).prefix(2)) }
		let numbers: [Double?] = (0 ..< count).map { _ in Int.random(in: 0 ..< 30, using: &generator) == 0 ? nil : Double(Int.random(in: 0 ..< 5, using: &generator)) }
		let lists = AppleEventList([
			AppleEventList(texts.map { $0.map(NSAppleEventDescriptor.init(string:)) ?? .missingValue }),
			AppleEventList(numbers.map { $0.map(NSAppleEventDescriptor.init(double:)) ?? .missingValue }),
			Array(0 ..< count),
		])
		func compareTexts(_ a: Int, _ b: Int, flags: Int, ascending: Bool) -> Int {
			switch (texts[a], texts[b]) {
			case (nil, nil): return 0
			case (nil, _): return 1
			case (_, nil): return -1
			case let (x?, y?):
				let result = Reference.compareText(x, y, flags: flags).rawValue
				return ascending ? result : -result
			}
		}
		func compareNumbers(_ a: Int, _ b: Int, ascending: Bool) -> Int {
			switch (numbers[a], numbers[b]) {
			case (nil, nil): return 0
			case (nil, _): return 1
			case (_, nil): return -1
			case let (x?, y?): return x == y ? 0 : ((x < y) == ascending ? -1 : 1)
			}
		}
		for keys in [[1, 2], [2, 1]] {
			for flags in [0, 2, 4, 5] {
				for directions in [[true, true], [false, true], [true, false]] {
					for unique in [false, true] {
						let reply = send("SATISort", ["----": lists, "from": keys, "Cfla": flags, "Asce": directions, "Uniq": unique])
						let rows = (reply.result?.atIndex(3)).map { list in (1 ... list.numberOfItems).map { Int(list.atIndex($0)!.int32Value) } } ?? []
						func compare(_ a: Int, _ b: Int) -> Int {
							for (key, ascending) in zip(keys, directions) {
								let result = key == 1 ? compareTexts(a, b, flags: flags, ascending: ascending) : compareNumbers(a, b, ascending: ascending)
								if result != 0 { return result }
							}
							return 0
						}
						var expected = (0 ..< count).sorted { a, b in
							let result = compare(a, b)
							return result == 0 ? a < b : result < 0
						}
						if unique {
							expected = expected.reduce(into: []) { unique, row in
								if unique.last.map({ compare($0, row) != 0 }) ?? true { unique.append(row) }
							}
						}
						#expect(rows == expected, "keys \(keys), flags \(flags), directions \(directions), unique \(unique)")
					}
				}
			}
		}
	}

	@Test func numbersAndMissingValuesMatchReference() {
		var generator = SeededGenerator(seed: 2)
		let numbers: [Double?] = (0 ..< 2_000).map { _ in Int.random(in: 0 ..< 20, using: &generator) == 0 ? nil : Double(Int.random(in: -50 ... 50, using: &generator)) / 4 }
		let list = AppleEventList(numbers.map { $0.map(NSAppleEventDescriptor.init(double:)) ?? .missingValue })
		for ascending in [true, false] {
			for unique in [false, true] {
				let reply = send("SATISort", ["----": list, "Asce": ascending, "Uniq": unique])
				let sorted = (0 ..< (reply.result?.numberOfItems ?? 0)).map { index -> Double? in
					let item = reply.result!.atIndex(index + 1)!
					return item.descriptorType == typeType ? nil : item.doubleValue
				}
				var expected = numbers.compactMap { $0 }.enumerated().sorted { a, b in
					a.element == b.element ? a.offset < b.offset : (a.element < b.element) == ascending
				}.map { Optional($0.element) }
				if unique {
					expected = expected.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
				}
				expected += numbers.filter { $0 == nil }.prefix(unique ? 1 : .max)
				#expect(sorted == expected, "ascending \(ascending), unique \(unique)")
			}
		}
	}
}

/// Results checked directly, without a sort to compare with: every pair of neighbors is in order (by the comparison
/// of two texts at a time, or by the numbers), `missing value` is last, and the result has the items given and no
/// others (with `remove duplicates`, an item equal to each one given, and no two equal neighbors). Lists of 20,000
/// items take every path the sort has: the radix sorts from 64 items, the merge sort's runs and merges, and ranks;
/// numbers and texts also come mostly sorted and mostly duplicates.
@MainActor
struct SortedResultTests {
	private static let count = 20_000

	private func items(_ reply: AppleEventReply) -> [NSAppleEventDescriptor] {
		guard let result = reply.result else {
			return []
		}
		return (0 ..< result.numberOfItems).map { result.atIndex($0 + 1)! }
	}

	/// Whether `sorted` is in order by `compare` (nil is `missing value`, last), strictly with `unique`.
	private func inOrder<Key>(_ sorted: [Key?], unique: Bool, _ compare: (Key, Key) -> Int) -> Bool {
		zip(sorted, sorted.dropFirst()).allSatisfy { a, b in
			switch (a, b) {
			case (nil, nil): !unique
			case (nil, _): false
			case (_, nil): true
			case let (x?, y?): unique ? compare(x, y) < 0 : compare(x, y) <= 0
			}
		}
	}

	/// Whether every item given has an equal item in `sorted` (in order, by binary search).
	private func hasEveryItem<Key>(_ sorted: [Key?], of given: [Key?], _ compare: (Key, Key) -> Int) -> Bool {
		let present = sorted.compactMap { $0 }
		return given.allSatisfy { item in
			guard let item else {
				return sorted.contains { $0 == nil }
			}
			var (low, high) = (0, present.count)
			while low < high {
				let middle = (low + high) / 2
				if compare(present[middle], item) < 0 { low = middle + 1 } else { high = middle }
			}
			return low < present.count && compare(present[low], item) == 0
		}
	}

	/// How a list's items are arranged: at random; in order but for 5% of them (2.5% of places swapped in pairs); or
	/// 95% duplicates (drawn from a twentieth as many distinct items).
	enum Arrangement: CaseIterable {
		case random, mostlySorted, mostlyDuplicates
	}

	private func arranged<Value>(_ arrangement: Arrangement, _ generator: inout SeededGenerator, count: Int = Self.count, by areInIncreasingOrder: (Value, Value) -> Bool, _ make: (inout SeededGenerator) -> Value) -> [Value] {
		switch arrangement {
		case .random:
			return (0 ..< count).map { _ in make(&generator) }
		case .mostlySorted:
			var values = (0 ..< count).map { _ in make(&generator) }.sorted(by: areInIncreasingOrder)
			for _ in 0 ..< count / 80 {
				values.swapAt(Int.random(in: 0 ..< count, using: &generator), Int.random(in: 0 ..< count, using: &generator))
			}
			return values
		case .mostlyDuplicates:
			let distinct = (0 ..< count / 20).map { _ in make(&generator) }
			return (0 ..< count).map { _ in distinct.randomElement(using: &generator)! }
		}
	}

	@Test(arguments: Arrangement.allCases) func numbersOfEveryMagnitude(_ arrangement: Arrangement) {
		var generator = SeededGenerator(seed: 10)
		// Random bits (every magnitude, subnormals, infinities and NaN, which sorts as missing value), ordinary reals,
		// few distinct ones (many ties), -0 and 0, and missing values.
		func key(_ value: Double?) -> Double? { value.flatMap { $0.isNaN ? nil : $0 } }
		let values: [Double?] = arranged(arrangement, &generator, by: { a, b in key(b) == nil ? key(a) != nil : key(a).map { $0 < key(b)! } ?? false }) { generator in
			switch Int.random(in: 0 ..< 5, using: &generator) {
			case 0: Double(bitPattern: generator.next())
			case 1: Double.random(in: -1e6 ... 1e6, using: &generator)
			case 2: Double(Int.random(in: -3 ... 3, using: &generator))
			case 3: [0.0, -0.0, .infinity, -.infinity][Int.random(in: 0 ..< 4, using: &generator)]
			default: Int.random(in: 0 ..< 4, using: &generator) == 0 ? nil : Double.random(in: -1 ... 1, using: &generator)
			}
		}
		let list = AppleEventList(values.map { $0.map(NSAppleEventDescriptor.init(double:)) ?? .missingValue }).appleEventDescriptor
		for ascending in [true, false] {
			for unique in [false, true] {
				let sorted = items(send("SATISort", ["----": list, "Asce": ascending, "Uniq": unique])).map { $0.descriptorType == typeType ? nil : $0.doubleValue }
				let compare: (Double, Double) -> Int = { x, y in x == y ? 0 : ((x < y) == ascending ? -1 : 1) }
				#expect(inOrder(sorted.map(key), unique: unique, compare), "ascending \(ascending), unique \(unique)")
				if unique {
					#expect(hasEveryItem(sorted.map(key), of: values.map(key), compare))
				} else {
					#expect(sorted.map { $0?.bitPattern ?? 0 }.sorted() == values.map { $0?.bitPattern ?? 0 }.sorted())
				}
			}
		}
		// The same numbers in an array of real.
		let array = ArrayOfReal(values.map { $0 ?? .nan })
		for ascending in [true, false] {
			let sorted = ArrayOfReal.values(of: send("SATISort", ["----": array, "Asce": ascending]).result!)!
			#expect(inOrder(sorted.map { $0.isNaN ? nil : $0 }, unique: false) { x, y in x == y ? 0 : ((x < y) == ascending ? -1 : 1) })
			#expect(sorted.map(\.bitPattern).sorted() == array.values.map(\.bitPattern).sorted())
		}
	}

	@Test func integersOfEverySize() {
		var generator = SeededGenerator(seed: 11)
		func descriptor<Value>(_ type: String, _ value: Value) -> NSAppleEventDescriptor {
			withUnsafeBytes(of: value) { NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: type), bytes: $0.baseAddress, length: $0.count)! }
		}
		let values: [Int64] = (0 ..< Self.count).map { index in
			switch index % 3 {
			case 0: Int64(Int16.random(in: .min ... .max, using: &generator))
			case 1: Int64(Int32.random(in: .min ... .max, using: &generator))
			default: Int64.random(in: -(1 << 52) ... (1 << 52), using: &generator)
			}
		}
		let list = AppleEventList(values.enumerated().map { index, value in
			switch index % 3 {
			case 0: descriptor("shor", Int16(value))
			case 1: descriptor("long", Int32(value))
			default: descriptor("comp", value)
			}
		}).appleEventDescriptor
		for ascending in [true, false] {
			let sorted = items(send("SATISort", ["----": list, "Asce": ascending])).map { item -> Int64 in
				item.data.withUnsafeBytes { bytes in
					switch bytes.count {
					case 2: Int64(bytes.loadUnaligned(as: Int16.self))
					case 4: Int64(bytes.loadUnaligned(as: Int32.self))
					default: bytes.loadUnaligned(as: Int64.self)
					}
				}
			}
			#expect(inOrder(sorted, unique: false) { x, y in x == y ? 0 : ((x < y) == ascending ? -1 : 1) })
			#expect(sorted.sorted() == values.sorted())
		}
	}

	/// Dates are compared with the dates the list holds: a date is local time in an Apple event, so a `Date` can come
	/// back different (at a change to or from daylight saving time).
	@Test func dates() {
		var generator = SeededGenerator(seed: 12)
		let list = AppleEventList((0 ..< Self.count).map { _ in
			Int.random(in: 0 ..< 50, using: &generator) == 0 ? .missingValue : NSAppleEventDescriptor(date: Date(timeIntervalSinceReferenceDate: Double.random(in: -3e9 ... 3e9, using: &generator).rounded()))
		}).appleEventDescriptor
		let given = items(AppleEventReply(result: list)).map { $0.descriptorType == typeType ? nil : $0.dateValue }
		for ascending in [true, false] {
			for unique in [false, true] {
				let sorted = items(send("SATISort", ["----": list, "Asce": ascending, "Uniq": unique])).map { $0.descriptorType == typeType ? nil : $0.dateValue }
				let compare: (Date, Date) -> Int = { x, y in x == y ? 0 : ((x < y) == ascending ? -1 : 1) }
				#expect(inOrder(sorted, unique: unique, compare), "ascending \(ascending), unique \(unique)")
				if unique {
					#expect(hasEveryItem(sorted, of: given, compare))
				} else {
					#expect(sorted.map { $0?.timeIntervalSinceReferenceDate ?? .infinity }.sorted() == given.map { $0?.timeIntervalSinceReferenceDate ?? .infinity }.sorted())
				}
			}
		}
	}

	/// Texts with characters of every kind the comparison treats specially, and missing values, under every flag
	/// (5,000 of them: the reference comparison is slow in a debug build). Mostly sorted is by character code. Each
	/// distinct text is ranked once for each flag by the reference comparison (equal texts have equal ranks), and the
	/// checks compare ranks: comparing texts for each check took most of a minute.
	@Test(arguments: Arrangement.allCases) func textsUnderEveryFlag(_ arrangement: Arrangement) {
		var generator = SeededGenerator(seed: 13)
		let pieces = ["a", "B", "é", "E\u{301}", "ß", "SS", "ς", "Σ", "ﬀ", "Ÿ", "ÿ", "ǅ", "İ", "中", "😀", "0", "7", "10", "007", " ", "-", "\u{0}"]
		func codes(_ text: String?) -> [UInt32] { text.map { $0.unicodeScalars.map(\.value) } ?? [0x11_0000] }
		let texts: [String?] = arranged(arrangement, &generator, count: 5_000, by: { codes($0).lexicographicallyPrecedes(codes($1)) }) { generator in
			Int.random(in: 0 ..< 40, using: &generator) == 0 ? nil : (0 ..< Int.random(in: 0 ... 6, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
		}
		let list = AppleEventList(texts.map { $0.map(NSAppleEventDescriptor.init(string:)) ?? .missingValue }).appleEventDescriptor
		// How many times each text is given, by its character codes (a String's hash normalizes it, which is slow).
		let given = texts.reduce(into: [:]) { counts, text in counts[codes(text), default: 0] += 1 }
		func isGiven(_ sorted: [String?]) -> Bool {
			var counts = given
			for text in sorted {
				counts[codes(text), default: 0] -= 1
			}
			return counts.values.allSatisfy { $0 == 0 }
		}
		// Each distinct text's keys: one for flags that keep case, one for those that ignore it.
		let distinct = Dictionary(texts.compactMap { $0.map { (codes($0), $0) } }) { first, _ in first }
		let keysByCase = [0, 1].map { flags in distinct.map { codes, text in (codes, Reference.Key(text, flags: flags)) } }
		for flags in 0 ... 7 {
			let keyed = keysByCase[flags & (1 | 4) == 0 ? 0 : 1].sorted { Reference.compare($0.1, $1.1, flags: flags) == .orderedAscending }
			var ranks: [[UInt32]: Int] = [:]
			var rank = 0
			for (index, (codes, key)) in keyed.enumerated() {
				if index > 0, Reference.compare(keyed[index - 1].1, key, flags: flags) != .orderedSame {
					rank += 1
				}
				ranks[codes] = rank
			}
			let givenRanks = Set(texts.map { $0.map { ranks[codes($0)]! } })
			for ascending in [true, false] {
				for unique in [false, true] {
					let sorted = items(send("SATISort", ["----": list, "Cfla": flags, "Asce": ascending, "Uniq": unique])).map { $0.descriptorType == typeType ? nil : $0.stringValue! }
					let label = "flags \(flags), ascending \(ascending), unique \(unique)"
					#expect(sorted.allSatisfy { $0.map { ranks[codes($0)] != nil } ?? true }, "\(label): a text that wasn't given")
					let sortedRanks = sorted.map { $0.flatMap { ranks[codes($0)] } }
					#expect(inOrder(sortedRanks, unique: unique) { x, y in ascending ? x - y : y - x }, "\(label)")
					if unique {
						#expect(Set(sortedRanks) == givenRanks, "\(label)")
					} else {
						#expect(isGiven(sorted), "\(label)")
					}
				}
			}
		}
	}

	/// Lists sorted together keep their rows together: an array of real by itself, and a number and a text (ranks).
	@Test func listsSortedTogetherKeepTheirRows() {
		var generator = SeededGenerator(seed: 14)
		let numbers = (0 ..< Self.count).map { _ in Double(Int.random(in: 0 ..< 50, using: &generator)) }
		let texts = (0 ..< Self.count).map { _ in String((0 ..< 3).map { _ in "aAbBé".randomElement(using: &generator)! }) }
		let rows = AppleEventList((0 ..< Self.count).map { NSAppleEventDescriptor(int32: Int32($0)) })
		let reply = items(send("SATISort", ["----": AppleEventList([ArrayOfReal(numbers), AppleEventList(texts), rows]), "from": [1, 2], "Cfla": 1, "Asce": [false, true]]))
		let sortedNumbers = ArrayOfReal.values(of: reply[0])!
		let sortedTexts = (1 ... reply[1].numberOfItems).map { reply[1].atIndex($0)!.stringValue! }
		let sortedRows = (1 ... reply[2].numberOfItems).map { Int(reply[2].atIndex($0)!.int32Value) }
		#expect(sortedRows.sorted() == Array(0 ..< Self.count))
		#expect(sortedRows.indices.allSatisfy { sortedNumbers[$0] == numbers[sortedRows[$0]] && sortedTexts[$0] == texts[sortedRows[$0]] })
		let keys = sortedRows.map { (numbers[$0], texts[$0]) }
		#expect(zip(keys, keys.dropFirst()).allSatisfy { a, b in
			a.0 != b.0 ? a.0 > b.0 : Reference.compareText(a.1, b.1, flags: 1) != .orderedDescending
		})
	}
}

/// The comparison `sortlist` used before (per pair, from the texts).
private enum Reference {
	static func sort(_ texts: [String], flags: Int, ascending: Bool, unique: Bool) -> [String] {
		func compare(_ a: String, _ b: String) -> ComparisonResult {
			let result = compareText(a, b, flags: flags)
			return ascending ? result : ComparisonResult(rawValue: -result.rawValue)!
		}
		let sorted = texts.enumerated().sorted { a, b in
			let result = compare(a.element, b.element)
			return result == .orderedSame ? a.offset < b.offset : result == .orderedAscending
		}.map(\.element)
		guard unique else {
			return sorted
		}
		var result: [String] = []
		for text in sorted where result.last.map({ compare($0, text) != .orderedSame }) ?? true {
			result.append(text)
		}
		return result
	}

	/// A text as it's compared: composed (NFC), and if case is ignored, decomposed, case folded and composed again;
	/// with flag 4, equal texts are ordered by their characters' case (uppercase, title case, the rest) and then as
	/// they're composed. It depends only on the composed text, so texts Swift calls equal have equal keys.
	struct Key {
		let primary: [Unicode.Scalar]
		let cases: [Int]
		let composed: [Unicode.Scalar]

		init(_ text: String, flags: Int) {
			let composed = text.precomposedStringWithCanonicalMapping
			self.composed = Array(composed.unicodeScalars)
			primary = flags & (1 | 4) == 0 ? self.composed : Array(composed.decomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping.unicodeScalars)
			cases = composed.unicodeScalars.map { scalar in
				scalar.properties.generalCategory == .titlecaseLetter ? 1 : (scalar.properties.isUppercase ? 0 : 2)
			}
		}
	}

	static func compare(_ a: Key, _ b: Key, flags: Int) -> ComparisonResult {
		let numeric = flags & 2 != 0
		let result = compareScalars(a.primary, b.primary, numeric: numeric)
		guard result == .orderedSame, flags & 4 != 0 else {
			return result
		}
		if a.cases != b.cases {
			return a.cases.lexicographicallyPrecedes(b.cases) ? .orderedAscending : .orderedDescending
		}
		return compareScalars(a.composed, b.composed, numeric: numeric)
	}

	static func compareText(_ a: String, _ b: String, flags: Int) -> ComparisonResult {
		compare(Key(a, flags: flags), Key(b, flags: flags), flags: flags)
	}

	static func compareScalars(_ x: [Unicode.Scalar], _ y: [Unicode.Scalar], numeric: Bool) -> ComparisonResult {
		func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0" ... "9").contains(scalar) }
		func digitsEnd(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
			var end = start
			while end < scalars.count, isDigit(scalars[end]) { end += 1 }
			return end
		}
		var i = 0, j = 0
		while i < x.count, j < y.count {
			if numeric, isDigit(x[i]), isDigit(y[j]) {
				let (xEnd, yEnd) = (digitsEnd(x, from: i), digitsEnd(y, from: j))
				let xDigits = x[i ..< xEnd].drop { $0 == "0" }, yDigits = y[j ..< yEnd].drop { $0 == "0" }
				if xDigits.count != yDigits.count {
					return xDigits.count < yDigits.count ? .orderedAscending : .orderedDescending
				}
				for (p, q) in zip(xDigits, yDigits) where p != q {
					return p.value < q.value ? .orderedAscending : .orderedDescending
				}
				(i, j) = (xEnd, yEnd)
				continue
			}
			if x[i] != y[j] {
				return x[i].value < y[j].value ? .orderedAscending : .orderedDescending
			}
			i += 1
			j += 1
		}
		let (xLeft, yLeft) = (x.count - i, y.count - j)
		return xLeft == yLeft ? .orderedSame : (xLeft < yLeft ? .orderedAscending : .orderedDescending)
	}
}

/// Each text's character codes.
private func codes(_ texts: [String]) -> [[UInt32]] {
	texts.map { $0.unicodeScalars.map(\.value) }
}

/// The character codes of each text in a reply's list.
private func codes(_ reply: AppleEventReply) -> [[UInt32]] {
	codes((0 ..< (reply.result?.numberOfItems ?? 0)).map { reply.result!.atIndex($0 + 1)!.stringValue! })
}

/// Repeatable random numbers (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
	var state: UInt64
	init(seed: UInt64) { state = seed }
	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var z = state
		z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
		z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
		return z ^ (z >> 31)
	}
}
