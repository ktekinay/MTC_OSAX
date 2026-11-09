import AppleEventCore
import Foundation
import Numerics

/// `sortlist`: a stable sort of numbers, text or dates.
///
/// - A list with text (or booleans) sorts as text, and numbers in it become text, as in SatimageOSAX. Numbers stay
///   integers unless one is a real. Dates can't be mixed with anything else.
/// - Text compares by character code ("ABC" before "abc", "é" after "z"), however its accents are typed (see
///   `TextKeys`); `comparison` adds 1 case-insensitive (by full case folding: "ß" is "ss"), 2 numbers by value ("a2"
///   before "a10"), 4 case-insensitive with uppercase first when equal ("A" < "a" < "B", "Ÿ" < "ÿ").
/// - `missing value` comes last in both directions (SatimageOSAX made it NaN, and put it in the middle when
///   sorting descending).
/// - A list of lists (or arrays) is sorted list by list, or all together by the lists `with respect to` names.
package enum Sorting {
	/// A list's sort keys, made once for each item (made for each comparison instead, lowercasing and copying the
	/// text each time, text sorts took 3 to 6 times as long as SatimageOSAX's). NaN and nil are `missing value`.
	package enum Column {
		/// Numbers, or dates as seconds.
		case numbers([Double])
		case texts(TextKeys)
	}

	static func sortList(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let options = Options(
			flags: try request.parameter("Cfla", default: 0),
			removeDuplicates: try request.parameter("Uniq", default: false)
		)
		let directions = directions(request)
		let ascending = directions[0]

		if let values = ArrayOfReal.values(of: descriptor) {
			return try sortedNumbers(values, ascending: ascending, options: options)
		}
		// A single value is a list of one (SatimageOSAX returned an empty list).
		let list = RawList(descriptor) ?? RawList(single: descriptor)
		guard let sublists = sublists(list) else {
			return try sortedList(list, ascending: ascending, options: options)
		}
		if let respect = request.descriptor(for: "from") {
			let criteria = try criteria(respect)
			return try sortTogether(sublists, by: criteria, ascending: directions, options: options)
		}
		return try sublists.map { sublist in
			switch sublist {
			case let .reals(values): try sortedNumbers(values, ascending: ascending, options: options)
			case let .list(list): try sortedList(list, ascending: ascending, options: options)
			}
		}.appleEventDescriptor
	}

	/// A list of lists' (or `array of real`s') lists, each read once; nil if there are none, or an item isn't one.
	private static func sublists(_ list: RawList) -> [ListUtilities.Items]? {
		guard list.count > 0 else {
			return nil
		}
		var sublists: [ListUtilities.Items] = []
		for index in 0 ..< list.count {
			// The type first, so other items aren't read.
			let type = list.info(index).type
			guard type == typeAEList || type == ArrayOfReal.descriptorType, let sublist = ListUtilities.Items(list.descriptor(index)) else {
				return nil
			}
			sublists.append(sublist)
		}
		return sublists
	}

	/// `ascending`: a boolean for each criterion, the first for those past its end (and true without one).
	struct Directions {
		let count: Int
		let at: (Int) -> Bool

		subscript(criterion: Int) -> Bool {
			criterion < count ? at(criterion) : count > 0 ? at(0) : true
		}
	}

	/// Each boolean read only when it's used: one for each criterion left once repeats are dropped (an array of
	/// 10,000,000 made a descriptor for each of its numbers, 12 s and 1.6 GB, and still did with as many criteria).
	private static func directions(_ request: AppleEventRequest) -> Directions {
		guard let descriptor = request.descriptor(for: "Asce") else {
			return Directions(count: 0) { _ in true }
		}
		if let values = ArrayOfReal.values(of: descriptor) {
			return Directions(count: values.count) { NSAppleEventDescriptor(double: values[$0]).booleanValue }
		}
		guard let list = RawList(descriptor) else {
			let value = descriptor.booleanValue
			return Directions(count: 1) { _ in value }
		}
		return Directions(count: list.count) { list.descriptor($0).booleanValue }
	}

	/// `with respect to`'s list numbers, read without a descriptor for each. Whole numbers only (1.5 used to become 1,
	/// and 1.0E+19 trapped); SatimageOSAX gave -1700 for 1.0E+19.
	private static func criteria(_ descriptor: NSAppleEventDescriptor) throws -> [Int] {
		var numbers: [Double] = []
		if let values = ArrayOfReal.values(of: descriptor) {
			numbers = values
		} else if let list = RawList(descriptor) {
			numbers.reserveCapacity(list.count)
			try list.forEachItem { item in
				numbers.append(try item.number ?? Numbers.number(list.descriptor(item.index)))
			}
		} else {
			numbers = [try Numbers.number(descriptor)]
		}
		return try numbers.map { value in
			guard value.rounded() == value, abs(value) <= Double(Int32.max) else {
				throw OSAXError.coercionFailed
			}
			return Int(value)
		}
	}

	package struct Options {
		package var flags: Int
		package var removeDuplicates: Bool

		package init(flags: Int, removeDuplicates: Bool) {
			self.flags = flags
			self.removeDuplicates = removeDuplicates
		}
	}

	/// An `array of real`, the numbers written straight into it (through an array of them, and another for the
	/// descriptor, a hundred million were 1.6 GB more).
	static func sortedNumbers(_ values: [Double], ascending: Bool, options: Options) throws -> NSAppleEventDescriptor {
		let rows = order(count: values.count, keys: [.numbers(values)], ascending: [ascending], options: options)
		return try ArrayOfReal.descriptor(count: rows.count) { buffer in
			for (index, row) in rows.enumerated() {
				buffer[index] = values[row]
			}
		}
	}

	static func sortedList(_ list: RawList, ascending: Bool, options: Options) throws -> NSAppleEventDescriptor {
		let column = try classify(list, flags: options.flags)
		let rows = order(count: list.count, keys: [column.keys], ascending: [ascending], options: options)
		return try list.list(of: rows, replacing: column.replacement)
	}

	/// Sorts the lists together, by the lists at `criteria` in priority order. Every list must have the same length
	/// and the criteria must name lists (error -1 otherwise, as in SatimageOSAX).
	static func sortTogether(_ columns: [ListUtilities.Items], by criteria: [Int], ascending: Directions, options: Options) throws -> NSAppleEventDescriptor {
		let count = columns.first?.count ?? 0
		guard columns.allSatisfy({ $0.count == count }), !criteria.isEmpty,
		      criteria.allSatisfy({ columns.indices.contains($0 - 1) })
		else {
			throw OSAXError(-1)
		}
		// A criterion that repeats an earlier one can't change the order: rows equal by every criterion before it are
		// equal by it too, whatever its direction (1,000 of them on 100,000 rows took 10 s and 1.7 GB).
		var seen = Set<Int>()
		let unique = criteria.indices.filter { seen.insert(criteria[$0]).inserted }
		// The lists sorted by have their items replaced, as a list sorted alone does (recorded: numbers in a list with
		// text come back as text, integers in a list with reals as reals); they came back as they were.
		var replacements: [Int: (Int) -> RawList.Replacement?] = [:]
		let keys = try unique.map { index -> Column in
			switch columns[criteria[index] - 1] {
			case let .reals(values):
				return Column.numbers(values)
			case let .list(list):
				let classified = try classify(list, flags: options.flags)
				replacements[criteria[index] - 1] = classified.replacement
				return classified.keys
			}
		}
		let rows = order(count: count, keys: keys, ascending: unique.map { ascending[$0] }, options: options)
		return try columns.indices.map { try columns[$0].selecting(rows, replacing: replacements[$0] ?? { _ in nil }) }.appleEventDescriptor
	}

	/// A list's sort keys, and what replaces its items in the sorted list.
	package struct Classified {
		package let keys: Column
		let replacement: (Int) -> RawList.Replacement?
	}

	/// The sort keys for a list, read from its items' data, and the items that change in the sorted list: numbers and
	/// booleans become text in a list with text, and integers reals in a list with reals.
	package static func classify(_ list: RawList, flags: Int) throws -> Classified {
		enum Kind { case number, real, text, date, missing }
		// Each item's type, size and (for a number) data, read in one pass.
		var kinds: [Kind] = []
		var items: [RawList.Item] = []
		kinds.reserveCapacity(list.count)
		items.reserveCapacity(list.count)
		try list.forEachItem { item in
			items.append(item)
			switch item.type {
			case typeSInt16, typeSInt32, typeSInt64: kinds.append(.number)
			case typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint: kinds.append(.real)
			case _ where NSAppleEventDescriptor.textTypes.contains(item.type), typeTrue, typeFalse, typeBoolean: kinds.append(.text)
			case typeLongDateTime: kinds.append(.date)
			case typeType where item.size == 4 && item.isMissingValue: kinds.append(.missing)
			default: throw OSAXError.coercionFailed
			}
		}
		let present = Set(kinds).subtracting([.missing])
		if present.contains(.date) && present.count > 1 {
			throw OSAXError.coercionFailed
		}
		if present.contains(.text) {
			var keys = TextKeys(capacity: list.count, flags: flags)
			// The text of the items that aren't `utxt` (numbers, booleans, other encodings), which replaces them.
			var texts = [String?](repeating: nil, count: list.count)
			var buffer = [UInt16](repeating: 0, count: 256)
			for index in 0 ..< list.count {
				if kinds[index] == .missing {
					keys.appendMissing()
					continue
				}
				if items[index].type == typeUnicodeText {
					let count = list.utf16(index, size: items[index].size, into: &buffer)
					// A byte-order mark is left to the descriptor's text, as it was.
					if count == 0 || (buffer[0] != 0xFEFF && buffer[0] != 0xFFFE) {
						buffer.withUnsafeBufferPointer { keys.append(utf16: UnsafeBufferPointer(rebasing: $0[..<count])) }
						continue
					}
				}
				// Text that can't be read sorts as missing value, and stays as it is.
				if let text = Self.text(list, items[index]) {
					keys.append(text)
					texts[index] = text
				} else {
					keys.appendMissing()
				}
			}
			return Classified(keys: .texts(keys)) { row in texts[row].map(RawList.Replacement.text) }
		}
		if present.contains(.date) {
			// A date's data is its seconds since 1904 in local time, which order dates as converting each to an
			// absolute time did (365 ms for a million, with a descriptor for each; 56 this way), but for local times
			// that don't exist (the hour skipped when clocks go forward), which only a script can make.
			let seconds = (0 ..< list.count).map { index in
				kinds[index] == .missing || items[index].size != 8 ? .nan : Double(list.value(index, type: typeLongDateTime, as: Int64.self))
			}
			return Classified(keys: .numbers(seconds)) { _ in nil }
		}
		// NaN (not a number: from `ln -1`, say, in an array) sorts as missing value, as it does alone: as a number it
		// compared equal to every number, so rows weren't sorted, and `remove duplicates` dropped real ones.
		let values = (0 ..< list.count).map { index in
			kinds[index] == .missing ? .nan : items[index].number!
		}
		guard present.contains(.real) else {
			return Classified(keys: .numbers(values)) { _ in nil }
		}
		// With a real, every number is a real.
		return Classified(keys: .numbers(values)) { row in
			kinds[row] != .missing && items[row].type != typeIEEE64BitFloatingPoint ? .real(values[row]) : nil
		}
	}

	/// An item that isn't `utxt` as text (see `ListUtilities.text`): numbers and booleans from their data.
	private static func text(_ list: RawList, _ item: RawList.Item) -> String? {
		switch item.type {
		case typeSInt16: NumberText.text(Int64(Int16(truncatingIfNeeded: item.bits)))
		case typeSInt32: NumberText.text(Int64(Int32(truncatingIfNeeded: item.bits)))
		case typeSInt64: NumberText.text(Int64(bitPattern: item.bits))
		case typeIEEE64BitFloatingPoint: NumberText.text(Double(bitPattern: item.bits))
		case typeTrue: "true"
		case typeFalse: "false"
		default: ListUtilities.text(list.descriptor(item.index))
		}
	}

	/// The rows in sorted order: stable, `missing value` last, duplicates (equal in every key) removed if asked.
	package static func order(count: Int, keys: [Column], ascending: [Bool], options: Options) -> [Int] {
		let columns = zip(keys, ascending).map { Prepared($0, ascending: $1) }
		// Row numbers are 32 bits, unless there are too many rows.
		if count <= Int(UInt32.max) {
			return order(UInt32.self, count: count, columns: columns, options: options)
		}
		return order(UInt64.self, count: count, columns: columns, options: options)
	}

	private static func order<Row: FixedWidthInteger & UnsignedInteger>(_: Row.Type, count: Int, columns: [Prepared], options: Options) -> [Int] {
		if columns.count > 1 {
			// With several keys, each text key becomes its texts' ranks, so that every key is a number: the radix sort
			// orders by all of them (rows were compared by every key when the first ones were equal: 242 ms for a
			// million by a number and a text), and one order compares them (an order for each column, made by
			// recursing, ran out of stack for 20,000 lists sorted together).
			let keys = columns.map { column -> [UInt64] in
				switch column {
				case let .numbers(keys): keys
				case .texts: ranks(Row.self, count: count, of: column, options: options)
				}
			}
			var rows = (0 ..< Row(count)).map { $0 }
			let order = KeysOrder(columns: keys)
			if count >= radixThreshold {
				radixSort(&rows, by: keys)
			} else {
				RowSort.mergeSort(&rows, by: order)
			}
			return finished(rows, by: order, options: options)
		}
		let numeric = options.flags & 2 != 0
		return withOrder(columns[0], numeric: numeric) { order in
			// Each order is a different type, so the sort is built for each.
			func sorted(by order: some RowOrder) -> [Int] {
				var rows = (0 ..< Row(count)).map { $0 }
				if count >= radixThreshold, var keys = columns[0].radixKeys(numeric: numeric) {
					// By the keys, and then rows whose keys are equal by comparing (numbers' keys are never equal
					// but for equal numbers, which a stable sort leaves in order).
					RowSort.radixSort(keys: &keys, rows: &rows)
					if case .texts = columns[0] {
						var start = 0
						while start < count {
							var end = start + 1
							while end < count, keys[end] == keys[start] { end += 1 }
							if end - start > 1 {
								RowSort.mergeSort(&rows, in: start ..< end, by: order)
							}
							start = end
						}
					}
				} else {
					RowSort.mergeSort(&rows, by: order)
				}
				return finished(rows, by: order, options: options)
			}
			switch order {
			case let .numbers(order): return sorted(by: order)
			case let .texts(order): return sorted(by: order)
			}
		}
	}

	/// The sorted rows as `Int`s, without duplicates (rows equal in every key) if asked.
	private static func finished<Row: FixedWidthInteger>(_ rows: [Row], by order: some RowOrder, options: Options) -> [Int] {
		var rows = rows
		if options.removeDuplicates {
			var previous: Row?
			rows.removeAll { row in
				defer { previous = row }
				return previous.map { order.compare(Int($0), Int(row)) == 0 } ?? false
			}
		}
		return rows.map { Int($0) }
	}

	/// Each row's rank in one column sorted on its own (in its direction, `missing value` last): 0 for the first text,
	/// and the same for texts that are equal.
	private static func ranks<Row: FixedWidthInteger & UnsignedInteger>(_: Row.Type, count: Int, of column: Prepared, options: Options) -> [UInt64] {
		let sorted = order(Row.self, count: count, columns: [column], options: Options(flags: options.flags, removeDuplicates: false))
		var ranks = [UInt64](repeating: 0, count: count)
		withOrder(column, numeric: options.flags & 2 != 0) { order in
			var rank: UInt64 = 0
			for (index, row) in sorted.enumerated() {
				if index > 0, order.compare(sorted[index - 1], row) != 0 {
					rank += 1
				}
				ranks[row] = rank
			}
		}
		return ranks
	}

	/// Calls `body` with an order for the column, which is valid only there.
	private static func withOrder<Result>(_ column: Prepared, numeric: Bool, _ body: (ColumnOrder) -> Result) -> Result {
		switch column {
		case let .numbers(keys):
			keys.withUnsafeBufferPointer { body(.numbers(NumberOrder(keys: $0))) }
		case let .texts(keys, ascending):
			keys.withOrder(ascending: ascending, numeric: numeric) { body(.texts($0)) }
		}
	}

	/// Lists shorter than this are sorted by comparing.
	static let radixThreshold = 64

	/// A column ready to compare: numbers as keys in its direction (see `RowSort.numberKey`).
	enum Prepared {
		case numbers([UInt64])
		case texts(TextKeys, ascending: Bool)

		init(_ column: Column, ascending: Bool) {
			switch column {
			case let .numbers(values): self = .numbers(values.map { RowSort.numberKey($0, ascending: ascending) })
			case let .texts(keys): self = .texts(keys, ascending: ascending)
			}
		}

		/// Keys for a radix sort by this column, which orders rows whose keys differ: rows with equal keys still need
		/// comparing. Not for text with flag 2.
		func radixKeys(numeric: Bool) -> [UInt64]? {
			switch self {
			case let .numbers(keys): keys
			case let .texts(keys, ascending): numeric ? nil : keys.prefixKeys(ascending: ascending)
			}
		}
	}

	/// Sorts the rows (in order) by number keys, with a radix sort: by the least important column first.
	private static func radixSort<Row: FixedWidthInteger>(_ rows: inout [Row], by columns: [[UInt64]]) {
		for (index, column) in columns.enumerated().reversed() {
			// The first sort's rows are in order; later ones need the column's keys in the rows' order.
			var keys = index == columns.count - 1 ? column : rows.map { column[Int($0)] }
			RowSort.radixSort(keys: &keys, rows: &rows)
		}
	}
}
