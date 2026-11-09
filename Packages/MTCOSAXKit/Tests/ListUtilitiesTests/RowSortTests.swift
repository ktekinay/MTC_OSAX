import AppleEventCore
import Foundation
import Testing
@testable import ListUtilities

/// The sorts `sortlist` uses, on their own.
struct RowSortTests {
	/// In order, with each value's neighbors: every kind of Double from -∞ to +∞.
	private static let increasing: [Double] = [
		-.infinity, -.greatestFiniteMagnitude, -1e300, -2, -1, -.leastNormalMagnitude, -.leastNonzeroMagnitude,
		0, .leastNonzeroMagnitude, .leastNormalMagnitude, 1e-300, 1, 1.5, 2, 1e300, .greatestFiniteMagnitude, .infinity,
	]

	@Test func numberKeysKeepTheNumbersOrder() {
		for ascending in [true, false] {
			let keys = Self.increasing.map { RowSort.numberKey($0, ascending: ascending) }
			for (a, b) in zip(keys, keys.dropFirst()) {
				#expect(ascending ? a < b : a > b)
			}
			#expect(keys.allSatisfy { $0 != .max })
		}
	}

	@Test func negativeZeroIsZero() {
		for ascending in [true, false] {
			#expect(RowSort.numberKey(-0.0, ascending: ascending) == RowSort.numberKey(0, ascending: ascending))
		}
	}

	@Test func notANumberIsLastBothWays() {
		for nan in [Double.nan, -.nan, .signalingNaN, Double(bitPattern: 0x7FFF_FFFF_FFFF_FFFF), Double(bitPattern: ~0)] {
			for ascending in [true, false] {
				#expect(RowSort.numberKey(nan, ascending: ascending) == .max)
			}
		}
	}

	/// Against the standard library's sort with ties in row order, for every length around where passes are skipped,
	/// and keys that differ in few bytes or in all of them.
	@Test func radixSortIsAStableSort() {
		var generator = SeededGenerator(seed: 3)
		let kinds: [(inout SeededGenerator) -> UInt64] = [
			{ UInt64.random(in: 0 ... 3, using: &$0) },
			{ UInt64.random(in: 0 ... 1000, using: &$0) << 40 },
			{ $0.next() },
			{ _ in 7 },
		]
		for count in Array(0 ... 70) + [255, 256, 257, 5000] {
			for kind in kinds {
				let original = (0 ..< count).map { _ in kind(&generator) }
				var keys = original
				var rows = (0 ..< UInt32(count)).map { $0 }
				RowSort.radixSort(keys: &keys, rows: &rows)
				let expected = original.indices.sorted { original[$0] == original[$1] ? $0 < $1 : original[$0] < original[$1] }
				#expect(rows.map { Int($0) } == expected, "\(count) keys")
				#expect(keys == expected.map { original[$0] })
			}
		}
	}

	/// Rows by a key each, for the merge sort.
	private struct KeyOrder: RowOrder {
		let keys: [Int]
		func compare(_ a: Int, _ b: Int) -> Int { keys[a] - keys[b] }
	}

	/// Against the standard library's sort with ties in row order: every length up to a few merges, lengths whose
	/// last run is short (a merge then copies most of the rows), and lists already sorted, reversed, or all equal.
	@Test func mergeSortIsAStableSort() {
		var generator = SeededGenerator(seed: 6)
		for count in Array(0 ... 70) + [100, 255, 257, 1000, 4097] {
			let random = (0 ..< count).map { _ in Int.random(in: 0 ..< max(1, count / 3), using: &generator) }
			for keys in [random, random.sorted(), random.sorted(by: >), Array(repeating: 1, count: count)] {
				var rows = (0 ..< UInt32(count)).map { $0 }
				RowSort.mergeSort(&rows, by: KeyOrder(keys: keys))
				let expected = keys.indices.sorted { keys[$0] == keys[$1] ? $0 < $1 : keys[$0] < keys[$1] }
				#expect(rows.map { Int($0) } == expected, "\(count) keys")
			}
		}
	}

	/// UTF-8 compared byte by byte with flag 2, in character-code order: characters of 1 to 4 bytes next to digits.
	@Test func numericComparisonOfUTF8() {
		func compare(_ a: String, _ b: String) -> Int {
			var (a, b) = (a + "\0", b + "\0") // never an empty buffer
			return a.withUTF8 { x in
				b.withUTF8 { y in TextOrder.compareNumerically(x.baseAddress!, x.count - 1, y.baseAddress!, y.count - 1) }
			}
		}
		let increasing = ["", "0", "1", "2", "9", "10", "a", "a1", "a2", "a10", "a10b", "a10é", "a10€", "a10😀", "a11", "é", "é9", "é10", "€", "€2", "€10", "😀", "😀1"]
		for (a, b) in zip(increasing, increasing.dropFirst()) {
			#expect(compare(a, b) < 0, "\(a) < \(b)")
			#expect(compare(b, a) > 0, "\(b) > \(a)")
		}
		#expect(compare("a007b", "a7b") == 0)
		#expect(compare("00", "0") == 0)
		#expect(compare("é", "é") == 0)
	}
}

@MainActor
struct SortNumberEdgeTests {
	private func sorted(_ values: [Double], ascending: Bool = true, unique: Bool = false) -> [UInt64] {
		let reply = send("SATISort", ["----": ArrayOfReal(values), "Asce": ascending, "Uniq": unique])
		return (reply.result.flatMap(ArrayOfReal.values(of:)) ?? []).map(\.bitPattern)
	}

	/// -0 and 0 are equal, so they keep their order (as they did when compared), at every length.
	@Test func signedZerosKeepTheirOrder() {
		for count in [4, 100] {
			let values = (0 ..< count).map { $0 % 2 == 0 ? 0.0 : -0.0 }
			#expect(sorted(values) == values.map(\.bitPattern))
			#expect(sorted(values, ascending: false) == values.map(\.bitPattern))
			#expect(sorted(values, unique: true) == [Double(0).bitPattern])
		}
	}

	@Test func infinitiesAndNotANumber() {
		for count in [1, 30] {
			let values = Array(repeating: [Double.nan, .infinity, 1, -.infinity, -0.0], count: count).flatMap { $0 }
			let ascending = sorted(values).map(Double.init(bitPattern:))
			#expect(ascending.prefix(count).allSatisfy { $0 == -.infinity })
			#expect(ascending[count ..< 4 * count] == ArraySlice(Array(repeating: -0.0, count: count) + Array(repeating: 1, count: count) + Array(repeating: .infinity, count: count)))
			#expect(ascending.suffix(count).allSatisfy { $0.isNaN })
			let descending = sorted(values, ascending: false).map(Double.init(bitPattern:))
			#expect(descending.prefix(count).allSatisfy { $0 == .infinity })
			#expect(descending.suffix(count).allSatisfy { $0.isNaN })
			#expect(sorted(values, unique: true).map(Double.init(bitPattern:)).dropLast().elementsEqual([-.infinity, -0.0, 1, .infinity]))
		}
	}
}
