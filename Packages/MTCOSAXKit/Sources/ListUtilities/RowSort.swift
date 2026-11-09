/// How two rows compare: less than 0 if `a` comes first, 0 if they're equal, more than 0 if `b` comes first. A
/// generic parameter rather than a closure, so each sort is built for its kind of key.
protocol RowOrder {
	func compare(_ a: Int, _ b: Int) -> Int
}

/// Stable sorts of row numbers, for `sortlist`: a radix sort by number keys, and a merge sort by any order.
enum RowSort {
	/// A number as a key whose unsigned order is the number's order (reversed if descending). -0 is 0, and NaN
	/// (`missing value`) is `UInt64.max`, after every number in both directions: no number's key is `UInt64.max`.
	static func numberKey(_ value: Double, ascending: Bool) -> UInt64 {
		if value.isNaN {
			return .max
		}
		let bits = (value == 0 ? 0 : value).bitPattern
		// Negatives have every bit flipped (the larger the magnitude, the smaller the key); positives only the sign.
		let key = bits >> 63 == 1 ? ~bits : bits | 1 << 63
		return ascending ? key : ~key
	}

	/// Sorts `rows` by `keys` (one for each row, in the same order), and `keys` with them: an LSD radix sort, a
	/// byte at a time, skipping each byte that's the same in every key. Stable, so sorting by a less important key
	/// first and then by a more important one sorts by both.
	static func radixSort<Row: FixedWidthInteger>(keys: inout [UInt64], rows: inout [Row]) {
		let count = keys.count
		precondition(rows.count == count)
		guard count > 1 else {
			return
		}
		// Every byte's counts in one pass.
		var counts = [Int](repeating: 0, count: 8 * 256)
		keys.withUnsafeBufferPointer { keys in
			counts.withUnsafeMutableBufferPointer { counts in
				for key in keys {
					for byte in 0 ..< 8 {
						counts[byte << 8 | Int(truncatingIfNeeded: key >> (byte * 8)) & 0xFF] += 1
					}
				}
			}
		}
		let passes = (0 ..< 8).filter { byte in !counts[byte << 8 ..< (byte + 1) << 8].contains(count) }
		guard !passes.isEmpty else {
			return
		}
		var otherKeys = [UInt64](repeating: 0, count: count)
		var otherRows = [Row](repeating: 0, count: count)
		var offsets = [Int](repeating: 0, count: 256)
		for (index, byte) in passes.enumerated() {
			var offset = 0
			for value in 0 ..< 256 {
				offsets[value] = offset
				offset += counts[byte << 8 | value]
			}
			let shift = UInt64(byte * 8)
			// Each pass moves from one pair of buffers to the other.
			func scatter(from keys: [UInt64], _ rows: [Row], into otherKeys: inout [UInt64], _ otherRows: inout [Row]) {
				keys.withUnsafeBufferPointer { keys in
					rows.withUnsafeBufferPointer { rows in
						otherKeys.withUnsafeMutableBufferPointer { otherKeys in
							otherRows.withUnsafeMutableBufferPointer { otherRows in
								offsets.withUnsafeMutableBufferPointer { offsets in
									for position in 0 ..< count {
										let key = keys[position]
										let value = Int(truncatingIfNeeded: key >> shift) & 0xFF
										let destination = offsets[value]
										offsets[value] = destination + 1
										otherKeys[destination] = key
										otherRows[destination] = rows[position]
									}
								}
							}
						}
					}
				}
			}
			if index % 2 == 0 {
				scatter(from: keys, rows, into: &otherKeys, &otherRows)
			} else {
				scatter(from: otherKeys, otherRows, into: &keys, &rows)
			}
		}
		if passes.count % 2 == 1 {
			swap(&keys, &otherKeys)
			swap(&rows, &otherRows)
		}
	}

	/// Runs this long are sorted by inserting before they're merged.
	static let insertionRun = 16

	/// Sorts `rows` (or those in `range`) by `order`: a bottom-up merge sort, stable, that sorts short runs by
	/// inserting, and doesn't merge two runs that are already in order (so a sorted list takes one comparison per run).
	static func mergeSort<Row: FixedWidthInteger, Order: RowOrder>(_ rows: inout [Row], in range: Range<Int>? = nil, by order: Order) {
		let range = range ?? rows.indices
		let count = range.count
		guard count > 1 else {
			return
		}
		rows.withUnsafeMutableBufferPointer { all in
			let rows = UnsafeMutableBufferPointer(rebasing: all[range])
			var start = 0
			while start < count {
				insertionSort(rows, start ..< min(start + insertionRun, count), by: order)
				start += insertionRun
			}
			guard count > insertionRun else {
				return
			}
			// Each merge copies its first run here (up to all but one row, when the last run is short), and merges it
			// with the second into their place.
			let scratch = UnsafeMutableBufferPointer<Row>.allocate(capacity: count)
			defer { scratch.deallocate() }
			var width = insertionRun
			while width < count {
				var low = 0
				while low < count - width {
					let middle = low + width, high = min(low + 2 * width, count)
					if order.compare(Int(rows[middle]), Int(rows[middle - 1])) < 0 {
						merge(rows, low, middle, high, scratch: scratch, by: order)
					}
					low = high
				}
				width *= 2
			}
		}
	}

	private static func insertionSort<Row: FixedWidthInteger, Order: RowOrder>(_ rows: UnsafeMutableBufferPointer<Row>, _ range: Range<Int>, by order: Order) {
		for index in range.dropFirst() {
			let row = rows[index]
			var position = index
			while position > range.lowerBound, order.compare(Int(row), Int(rows[position - 1])) < 0 {
				rows[position] = rows[position - 1]
				position -= 1
			}
			rows[position] = row
		}
	}

	/// Merges the sorted runs `low ..< middle` and `middle ..< high`, taking from the first when they're equal.
	private static func merge<Row: FixedWidthInteger, Order: RowOrder>(_ rows: UnsafeMutableBufferPointer<Row>, _ low: Int, _ middle: Int, _ high: Int, scratch: UnsafeMutableBufferPointer<Row>, by order: Order) {
		let firstCount = middle - low
		_ = scratch.initialize(fromContentsOf: rows[low ..< middle])
		var first = 0, second = middle, destination = low
		while first < firstCount, second < high {
			if order.compare(Int(rows[second]), Int(scratch[first])) < 0 {
				rows[destination] = rows[second]
				second += 1
			} else {
				rows[destination] = scratch[first]
				first += 1
			}
			destination += 1
		}
		// What's left of the second run is already in place.
		while first < firstCount {
			rows[destination] = scratch[first]
			first += 1
			destination += 1
		}
	}
}
