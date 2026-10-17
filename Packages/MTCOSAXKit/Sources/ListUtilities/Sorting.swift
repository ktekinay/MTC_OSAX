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
		let ascending = directions(request, count: 1).first ?? true

		if let values = ArrayOfReal.values(of: descriptor) {
			return try ArrayOfReal(sortedNumbers(values, ascending: ascending, options: options)).descriptor()
		}
		// A single value is a list of one (SatimageOSAX returned an empty list).
		let list = RawList(descriptor) ?? RawList(single: descriptor)
		let isListOfLists = list.count > 0 && (0 ..< list.count).allSatisfy { isList(list, $0) }
		if isListOfLists, let respect = request.descriptor(for: "from") {
			let criteria = try criteria(respect)
			return try sortTogether((0 ..< list.count).map(list.descriptor), by: criteria, ascending: directions(request, count: criteria.count), options: options)
		}
		if isListOfLists {
			return try (0 ..< list.count).map { index in
				let sublist = list.descriptor(index)
				if let values = ArrayOfReal.values(of: sublist) {
					return try ArrayOfReal(sortedNumbers(values, ascending: ascending, options: options)).descriptor()
				}
				return try sortedList(RawList(sublist)!, ascending: ascending, options: options)
			}.appleEventDescriptor
		}
		return try sortedList(list, ascending: ascending, options: options)
	}

	/// `ascending`'s first `count` booleans, all that are used (an array of 10,000,000 made a descriptor for each of
	/// its numbers: 12 s and 1.6 GB).
	private static func directions(_ request: AppleEventRequest, count: Int) -> [Bool] {
		guard let descriptor = request.descriptor(for: "Asce") else {
			return []
		}
		if let values = ArrayOfReal.values(of: descriptor) {
			return values.prefix(count).map { NSAppleEventDescriptor(double: $0).booleanValue }
		}
		guard let list = RawList(descriptor) else {
			return [descriptor.booleanValue]
		}
		return (0 ..< min(count, list.count)).map { list.descriptor($0).booleanValue }
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

	/// Whether an item is a list or an `array of real` (checked by its type first, so other items aren't read).
	private static func isList(_ list: RawList, _ index: Int) -> Bool {
		switch list.info(index).type {
		case typeAEList: true
		case ArrayOfReal.descriptorType: ArrayOfReal.values(of: list.descriptor(index)) != nil
		default: false
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

	static func sortedNumbers(_ values: [Double], ascending: Bool, options: Options) -> [Double] {
		order(rows: values.indices, keys: [.numbers(values)], ascending: [ascending], options: options).map { values[$0] }
	}

	static func sortedList(_ list: RawList, ascending: Bool, options: Options) throws -> NSAppleEventDescriptor {
		let column = try classify(list, flags: options.flags)
		let rows = order(rows: 0 ..< list.count, keys: [column.keys], ascending: [ascending], options: options)
		return try list.list(of: rows, replacing: column.replacement)
	}

	/// A list to sort with others: an `array of real`'s numbers (a descriptor for each number made huge arrays take
	/// gigabytes), or a list.
	enum Together {
		case reals([Double])
		case list(RawList)

		init(_ descriptor: NSAppleEventDescriptor) {
			if let values = ArrayOfReal.values(of: descriptor) {
				self = .reals(values)
			} else {
				self = .list(RawList(descriptor) ?? RawList(.list())!)
			}
		}

		var count: Int {
			switch self {
			case let .reals(values): values.count
			case let .list(list): list.count
			}
		}

		/// The items at `rows`, in that order: an `array of real` for numbers, a list otherwise.
		func selecting(_ rows: [Int]) throws -> NSAppleEventDescriptor {
			switch self {
			case let .reals(values): try ArrayOfReal.descriptor(count: rows.count) { buffer in
					for (index, row) in rows.enumerated() { buffer[index] = values[row] }
				}
			case let .list(list): try list.list(of: rows)
			}
		}
	}

	/// Sorts the lists together, by the lists at `criteria` in priority order. Every list must have the same length
	/// and the criteria must name lists (error -1 otherwise, as in SatimageOSAX).
	static func sortTogether(_ lists: [NSAppleEventDescriptor], by criteria: [Int], ascending: [Bool], options: Options) throws -> NSAppleEventDescriptor {
		let columns = lists.map(Together.init)
		let count = columns.first?.count ?? 0
		guard columns.allSatisfy({ $0.count == count }), !criteria.isEmpty,
		      criteria.allSatisfy({ columns.indices.contains($0 - 1) })
		else {
			throw OSAXError(-1)
		}
		let directions = criteria.indices.map { ascending.indices.contains($0) ? ascending[$0] : (ascending.first ?? true) }
		// A criterion that repeats an earlier one can't change the order: rows equal by every criterion before it are
		// equal by it too, whatever its direction (1,000 of them on 100,000 rows took 10 s and 1.7 GB).
		var seen = Set<Int>()
		let unique = criteria.indices.filter { seen.insert(criteria[$0]).inserted }
		let keys = try unique.map { index -> Column in
			switch columns[criteria[index] - 1] {
			case let .reals(values): Column.numbers(values)
			case let .list(list): try classify(list, flags: options.flags).keys
			}
		}
		let rows = order(rows: 0 ..< count, keys: keys, ascending: unique.map { directions[$0] }, options: options)
		return try columns.map { try $0.selecting(rows) }.appleEventDescriptor
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
		let missing = FourCharCode(fourCharString: "msng")
		var kinds: [Kind] = []
		var types: [DescType] = []
		var sizes: [Int] = []
		kinds.reserveCapacity(list.count)
		types.reserveCapacity(list.count)
		sizes.reserveCapacity(list.count)
		for index in 0 ..< list.count {
			let (type, size) = list.info(index)
			types.append(type)
			sizes.append(size)
			switch type {
			case typeSInt16, typeSInt32, typeSInt64: kinds.append(.number)
			case typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint: kinds.append(.real)
			case _ where NSAppleEventDescriptor.textTypes.contains(type), typeTrue, typeFalse, typeBoolean: kinds.append(.text)
			case typeLongDateTime: kinds.append(.date)
			case typeType where size == 4 && list.value(index, type: typeType, as: FourCharCode.self) == missing: kinds.append(.missing)
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
				if types[index] == typeUnicodeText {
					let count = list.utf16(index, size: sizes[index], into: &buffer)
					// A byte-order mark is left to the descriptor's text, as it was.
					if count == 0 || (buffer[0] != 0xFEFF && buffer[0] != 0xFFFE) {
						buffer.withUnsafeBufferPointer { keys.append(utf16: UnsafeBufferPointer(rebasing: $0[..<count])) }
						continue
					}
				}
				// Text that can't be read sorts as missing value, and stays as it is.
				if let text = Self.text(list, index, type: types[index]) {
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
				kinds[index] == .missing || sizes[index] != 8 ? .nan : Double(list.value(index, type: typeLongDateTime, as: Int64.self))
			}
			return Classified(keys: .numbers(seconds)) { _ in nil }
		}
		// NaN (not a number: from `ln -1`, say, in an array) sorts as missing value, as it does alone: as a number it
		// compared equal to every number, so rows weren't sorted, and `remove duplicates` dropped real ones.
		let values = (0 ..< list.count).map { index in
			kinds[index] == .missing ? .nan : number(list, index, type: types[index])
		}
		guard present.contains(.real) else {
			return Classified(keys: .numbers(values)) { _ in nil }
		}
		// With a real, every number is a real.
		return Classified(keys: .numbers(values)) { row in
			kinds[row] != .missing && types[row] != typeIEEE64BitFloatingPoint ? .real(values[row]) : nil
		}
	}

	/// A number item's value, from its data.
	private static func number(_ list: RawList, _ index: Int, type: DescType) -> Double {
		switch type {
		case typeSInt16: Double(list.value(index, type: type, as: Int16.self))
		case typeSInt32: Double(list.value(index, type: type, as: Int32.self))
		case typeSInt64: Double(list.value(index, type: type, as: Int64.self))
		case typeIEEE32BitFloatingPoint: Double(list.value(index, type: type, as: Float32.self))
		default: list.value(index, type: type, as: Double.self)
		}
	}

	/// An item that isn't `utxt` as text (see `ListUtilities.text`): numbers and booleans from their data.
	private static func text(_ list: RawList, _ index: Int, type: DescType) -> String? {
		switch type {
		case typeSInt16: NumberText.text(Int64(list.value(index, type: type, as: Int16.self)))
		case typeSInt32: NumberText.text(Int64(list.value(index, type: type, as: Int32.self)))
		case typeSInt64: NumberText.text(list.value(index, type: type, as: Int64.self))
		case typeIEEE64BitFloatingPoint: NumberText.text(list.value(index, type: type, as: Double.self))
		case typeTrue: "true"
		case typeFalse: "false"
		default: ListUtilities.text(list.descriptor(index))
		}
	}

	/// The rows in sorted order: stable, `missing value` last, duplicates (equal in every key) removed if asked.
	package static func order(rows: Range<Int>, keys: [Column], ascending: [Bool], options: Options) -> [Int] {
		let columns = zip(keys, ascending).map { Prepared($0, ascending: $1) }
		// Row numbers are 32 bits, unless there are too many rows.
		if rows.count <= Int(UInt32.max) {
			return order(UInt32.self, count: rows.count, columns: columns, options: options)
		}
		return order(UInt64.self, count: rows.count, columns: columns, options: options)
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
