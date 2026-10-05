import AppleEventCore
import Foundation
import Testing
@testable import ListUtilities

/// `sortlist` against a plain implementation of its rules (the comparison it used before sort keys were made once
/// per item), over random lists.
@MainActor
struct SortEquivalenceTests {
	private static let pieces = ["a", "A", "b", "B", "é", "É", "e", "z", "0", "1", "2", "9", "10", "007", " ", "-", "ß", "😀", "Ω", "ω"]

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
					let sorted = (0 ..< (reply.result?.numberOfItems ?? 0)).map { reply.result!.atIndex($0 + 1)!.stringValue! }
					let expected = Reference.sort(texts, flags: flags, ascending: ascending, unique: unique)
					#expect(sorted == expected, "flags \(flags), ascending \(ascending), unique \(unique)")
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

	static func compareText(_ a: String, _ b: String, flags: Int) -> ComparisonResult {
		let numeric = flags & 2 != 0
		let result = compareScalars(a, b, ignoringCase: flags & (1 | 4) != 0, numeric: numeric)
		if result == .orderedSame, flags & 4 != 0 {
			return compareScalars(a, b, ignoringCase: false, numeric: numeric)
		}
		return result
	}

	static func compareScalars(_ a: String, _ b: String, ignoringCase: Bool, numeric: Bool) -> ComparisonResult {
		let x = Array((ignoringCase ? a.lowercased() : a).unicodeScalars)
		let y = Array((ignoringCase ? b.lowercased() : b).unicodeScalars)
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

/// Repeatable random numbers (SplitMix64).
private struct SeededGenerator: RandomNumberGenerator {
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
