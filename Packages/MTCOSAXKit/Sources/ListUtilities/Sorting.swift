import AppleEventCore
import Foundation
import Numerics

/// `sortlist`: a stable sort of numbers, text or dates.
///
/// - A list with text (or booleans) sorts as text, and numbers in it become text, as in SatimageOSAX. Numbers stay
///   integers unless one is a real. Dates can't be mixed with anything else.
/// - Text compares by character code ("ABC" before "abc", "é" after "z"); `comparison` adds 1 case-insensitive,
///   2 numbers by value ("a2" before "a10"), 4 case-insensitive with uppercase first when equal ("A" < "a" < "B").
/// - `missing value` comes last in both directions (SatimageOSAX made it NaN, and put it in the middle when
///   sorting descending).
/// - A list of lists (or arrays) is sorted list by list, or all together by the lists `with respect to` names.
enum Sorting {
	/// A list's sort keys, made once for each item (made for each comparison instead, lowercasing and copying the
	/// text each time, text sorts took 3 to 6 times as long as SatimageOSAX's). nil is `missing value`.
	enum Column {
		/// Numbers, or dates as seconds.
		case numbers([Double?])
		case texts([TextKey?])
	}

	/// Text as it's compared: its scalars' values, lowercased if case is ignored; with flag 4, also the text as it
	/// is, which orders texts that differ only in case.
	struct TextKey {
		let scalars: [UInt32]
		let exact: [UInt32]?

		init(_ text: String, flags: Int) {
			scalars = (flags & (1 | 4) != 0 ? text.lowercased() : text).unicodeScalars.map(\.value)
			exact = flags & 4 != 0 ? text.unicodeScalars.map(\.value) : nil
		}
	}

	static func sortList(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let options = Options(
			flags: try request.parameter("Cfla", default: 0),
			removeDuplicates: try request.parameter("Uniq", default: false)
		)
		let ascending = request.descriptor(for: "Asce").map { ListUtilities.items($0) ?? [$0] }?.map(\.booleanValue) ?? []

		if let values = ArrayOfReal.values(of: descriptor) {
			return ArrayOfReal(sortedNumbers(values, ascending: ascending.first ?? true, options: options)).appleEventDescriptor
		}
		// A single value is a list of one (SatimageOSAX returned an empty list).
		let items = ListUtilities.items(descriptor) ?? [descriptor]
		let isListOfLists = !items.isEmpty && items.allSatisfy(ListUtilities.isList)
		if isListOfLists, let respect = request.descriptor(for: "from") {
			// Whole numbers only (1.5 used to become 1, and 1.0E+19 trapped); SatimageOSAX gave -1700 for 1.0E+19.
			let criteria = try (ListUtilities.items(respect) ?? [respect]).map { item in
				let value = try Numbers.number(item)
				guard value.rounded() == value, abs(value) <= Double(Int32.max) else {
					throw OSAXError.coercionFailed
				}
				return Int(value)
			}
			return try sortTogether(items, by: criteria, ascending: ascending, options: options)
		}
		if isListOfLists {
			return try items.map { list in
				if let values = ArrayOfReal.values(of: list) {
					return ArrayOfReal(sortedNumbers(values, ascending: ascending.first ?? true, options: options)).appleEventDescriptor
				}
				return try sortedList(ListUtilities.items(list) ?? [], ascending: ascending.first ?? true, options: options)
			}.appleEventDescriptor
		}
		return try sortedList(items, ascending: ascending.first ?? true, options: options)
	}

	struct Options {
		var flags: Int
		var removeDuplicates: Bool
	}

	static func sortedNumbers(_ values: [Double], ascending: Bool, options: Options) -> [Double] {
		let keys = Column.numbers(values.map { $0.isNaN ? nil : $0 })
		return order(rows: values.indices, keys: [keys], ascending: [ascending], options: options).map { values[$0] }
	}

	static func sortedList(_ items: [NSAppleEventDescriptor], ascending: Bool, options: Options) throws -> NSAppleEventDescriptor {
		let (keys, converted) = try classify(items, flags: options.flags)
		return order(rows: items.indices, keys: [keys], ascending: [ascending], options: options).map { converted[$0] }.appleEventDescriptor
	}

	/// Sorts the lists together, by the lists at `criteria` in priority order. Every list must have the same length
	/// and the criteria must name lists (error -1 otherwise, as in SatimageOSAX).
	static func sortTogether(_ lists: [NSAppleEventDescriptor], by criteria: [Int], ascending: [Bool], options: Options) throws -> NSAppleEventDescriptor {
		// Arrays stay numbers (a descriptor for each number made huge arrays take gigabytes).
		let columns = lists.map { ListUtilities.Items($0) ?? .descriptors([]) }
		let count = columns.first?.count ?? 0
		guard columns.allSatisfy({ $0.count == count }), !criteria.isEmpty,
		      criteria.allSatisfy({ columns.indices.contains($0 - 1) })
		else {
			throw OSAXError(-1)
		}
		let keys = try criteria.map { criterion -> Column in
			switch columns[criterion - 1] {
			case let .reals(values): Column.numbers(values.map { $0.isNaN ? nil : $0 })
			case let .descriptors(items): try classify(items, flags: options.flags).keys
			}
		}
		let directions = criteria.indices.map { ascending.indices.contains($0) ? ascending[$0] : (ascending.first ?? true) }
		let rows = order(rows: 0 ..< count, keys: keys, ascending: directions, options: options)
		return columns.map { $0.selecting(rows) }.appleEventDescriptor
	}

	/// The sort keys for a list, and its items as the sorted result returns them.
	static func classify(_ items: [NSAppleEventDescriptor], flags: Int) throws -> (keys: Column, converted: [NSAppleEventDescriptor]) {
		enum Kind { case number, real, text, date, missing }
		let kinds: [Kind] = try items.map { item in
			switch item.descriptorType {
			case typeSInt16, typeSInt32, typeSInt64: return .number
			case typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint: return .real
			case typeUnicodeText, typeUTF8Text, typeChar, FourCharCode(fourCharString: "ut16"), typeTrue, typeFalse, typeBoolean: return .text
			case typeLongDateTime: return .date
			case typeType where item.typeCodeValue.fourCharString == "msng": return .missing
			default: throw OSAXError.coercionFailed
			}
		}
		let present = Set(kinds).subtracting([.missing])
		if present.contains(.date) && present.count > 1 {
			throw OSAXError.coercionFailed
		}
		if present.contains(.text) {
			let texts = items.map { ListUtilities.text($0) }
			return (.texts(texts.map { $0.map { TextKey($0, flags: flags) } }), zip(items, texts).map { item, text in text.map(NSAppleEventDescriptor.init(string:)) ?? item })
		}
		if present.contains(.date) {
			return (.numbers(items.map { $0.dateValue?.timeIntervalSinceReferenceDate }), items)
		}
		let anyReal = present.contains(.real)
		// NaN (not a number: from `ln -1`, say, in an array) sorts as missing value, as it does alone: as a number it
		// compared equal to every number, so rows weren't sorted, and `remove duplicates` dropped real ones.
		let keys = Column.numbers(items.map { item in
			item.descriptorType == typeType || item.doubleValue.isNaN ? nil : item.doubleValue
		})
		let converted = items.map { item in
			anyReal && item.descriptorType != typeType ? NSAppleEventDescriptor(double: item.doubleValue) : item
		}
		return (keys, converted)
	}

	/// The rows in sorted order: stable, `missing value` last, duplicates (equal in every key) removed if asked.
	static func order(rows: Range<Int>, keys: [Column], ascending: [Bool], options: Options) -> [Int] {
		let comparisons = zip(keys, ascending).map { comparison(of: $0, ascending: $1, flags: options.flags) }
		func compare(_ a: Int, _ b: Int) -> ComparisonResult {
			for comparison in comparisons {
				let result = comparison(a, b)
				if result != .orderedSame {
					return result
				}
			}
			return .orderedSame
		}
		let sorted = rows.sorted { a, b in
			let result = compare(a, b)
			return result == .orderedSame ? a < b : result == .orderedAscending
		}
		guard options.removeDuplicates else {
			return sorted
		}
		var unique: [Int] = []
		for row in sorted where unique.last.map({ compare($0, row) != .orderedSame }) ?? true {
			unique.append(row)
		}
		return unique
	}

	/// How two rows compare by one column.
	private static func comparison(of column: Column, ascending: Bool, flags: Int) -> (Int, Int) -> ComparisonResult {
		switch column {
		case let .numbers(keys):
			return { a, b in
				ordered(keys[a], keys[b], ascending: ascending) { x, y in
					x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
				}
			}
		case let .texts(keys):
			let numeric = flags & 2 != 0
			return { a, b in
				ordered(keys[a], keys[b], ascending: ascending) { x, y in compareText(x, y, numeric: numeric) }
			}
		}
	}

	/// `missing value` (nil) last in both directions.
	private static func ordered<Value>(_ x: Value?, _ y: Value?, ascending: Bool, by compare: (Value, Value) -> ComparisonResult) -> ComparisonResult {
		guard let x else {
			return y == nil ? .orderedSame : .orderedDescending
		}
		guard let y else {
			return .orderedAscending
		}
		let result = compare(x, y)
		return ascending ? result : ComparisonResult(rawValue: -result.rawValue)!
	}

	/// Text by character code; flag 1 ignores case, 2 compares digit runs by value, 4 ignores case but puts
	/// uppercase first when otherwise equal (the keys were made for the flags).
	static func compareText(_ a: TextKey, _ b: TextKey, numeric: Bool) -> ComparisonResult {
		let result = compareScalars(a.scalars, b.scalars, numeric: numeric)
		if result == .orderedSame, let x = a.exact, let y = b.exact {
			return compareScalars(x, y, numeric: numeric)
		}
		return result
	}

	private static func compareScalars(_ x: [UInt32], _ y: [UInt32], numeric: Bool) -> ComparisonResult {
		var i = 0, j = 0
		while i < x.count, j < y.count {
			if numeric, isDigit(x[i]), isDigit(y[j]) {
				let (xEnd, yEnd) = (digitsEnd(x, from: i), digitsEnd(y, from: j))
				let xDigits = x[i ..< xEnd].drop { $0 == 0x30 }, yDigits = y[j ..< yEnd].drop { $0 == 0x30 }
				if xDigits.count != yDigits.count {
					return xDigits.count < yDigits.count ? .orderedAscending : .orderedDescending
				}
				for (p, q) in zip(xDigits, yDigits) where p != q {
					return p < q ? .orderedAscending : .orderedDescending
				}
				(i, j) = (xEnd, yEnd)
				continue
			}
			if x[i] != y[j] {
				return x[i] < y[j] ? .orderedAscending : .orderedDescending
			}
			i += 1
			j += 1
		}
		let (xLeft, yLeft) = (x.count - i, y.count - j)
		return xLeft == yLeft ? .orderedSame : (xLeft < yLeft ? .orderedAscending : .orderedDescending)
	}

	private static func isDigit(_ scalar: UInt32) -> Bool {
		(0x30 ... 0x39).contains(scalar) // 0-9
	}

	private static func digitsEnd(_ scalars: [UInt32], from start: Int) -> Int {
		var end = start
		while end < scalars.count, isDigit(scalars[end]) {
			end += 1
		}
		return end
	}
}
