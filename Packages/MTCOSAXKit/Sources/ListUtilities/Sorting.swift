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
	enum Key {
		case number(Double)
		case text(String)
		case date(Date)
		case missing

		var isMissing: Bool {
			if case .missing = self { return true }
			return false
		}
	}

	static func sortList(_ request: AppleEventRequest) throws -> NSAppleEventDescriptor {
		let descriptor = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
		let options = Options(
			flags: try request.parameter("Cfla", default: 0),
			removeDuplicates: try request.parameter("Uniq", default: false)
		)
		let ascending = try request.descriptor(for: "Asce").map { ListUtilities.items($0) ?? [$0] }?.map(\.booleanValue) ?? []

		if let values = ArrayOfReal.values(of: descriptor) {
			return ArrayOfReal(sortedNumbers(values, ascending: ascending.first ?? true, options: options)).appleEventDescriptor
		}
		// A single value is a list of one (SatimageOSAX returned an empty list).
		let items = ListUtilities.items(descriptor) ?? [descriptor]
		let isListOfLists = !items.isEmpty && items.allSatisfy(ListUtilities.isList)
		if isListOfLists, let respect = request.descriptor(for: "from") {
			let criteria = try (ListUtilities.items(respect) ?? [respect]).map { try Int(Numbers.number($0)) }
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
		let keys = values.map { $0.isNaN ? Key.missing : .number($0) }
		return order(rows: values.indices, keys: [keys], ascending: [ascending], options: options).map { values[$0] }
	}

	static func sortedList(_ items: [NSAppleEventDescriptor], ascending: Bool, options: Options) throws -> NSAppleEventDescriptor {
		let (keys, converted) = try classify(items)
		return order(rows: items.indices, keys: [keys], ascending: [ascending], options: options).map { converted[$0] }.appleEventDescriptor
	}

	/// Sorts the lists together, by the lists at `criteria` in priority order. Every list must have the same length
	/// and the criteria must name lists (error -1 otherwise, as in SatimageOSAX).
	static func sortTogether(_ lists: [NSAppleEventDescriptor], by criteria: [Int], ascending: [Bool], options: Options) throws -> NSAppleEventDescriptor {
		let columns = lists.map { ListUtilities.items($0) ?? [] }
		let count = columns.first?.count ?? 0
		guard columns.allSatisfy({ $0.count == count }), !criteria.isEmpty,
		      criteria.allSatisfy({ columns.indices.contains($0 - 1) })
		else {
			throw OSAXError(-1)
		}
		let keys = try criteria.map { try classify(columns[$0 - 1]).keys }
		let directions = criteria.indices.map { ascending.indices.contains($0) ? ascending[$0] : (ascending.first ?? true) }
		let rows = order(rows: 0 ..< count, keys: keys, ascending: directions, options: options)
		return zip(lists, columns).map { list, column in
			let sorted = rows.map { column[$0] }
			if ArrayOfReal.values(of: list) != nil {
				return ArrayOfReal(sorted.map(\.doubleValue)).appleEventDescriptor
			}
			return sorted.appleEventDescriptor
		}.appleEventDescriptor
	}

	/// The sort keys for a list, and its items as the sorted result returns them.
	static func classify(_ items: [NSAppleEventDescriptor]) throws -> (keys: [Key], converted: [NSAppleEventDescriptor]) {
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
			return (texts.map { $0.map(Key.text) ?? .missing }, zip(items, texts).map { item, text in text.map(NSAppleEventDescriptor.init(string:)) ?? item })
		}
		if present.contains(.date) {
			return (items.map { $0.dateValue.map(Key.date) ?? .missing }, items)
		}
		let anyReal = present.contains(.real)
		let keys = items.map { item -> Key in
			item.descriptorType == typeType ? .missing : .number(item.doubleValue)
		}
		let converted = items.map { item in
			anyReal && item.descriptorType != typeType ? NSAppleEventDescriptor(double: item.doubleValue) : item
		}
		return (keys, converted)
	}

	/// The rows in sorted order: stable, `missing value` last, duplicates (equal in every key) removed if asked.
	static func order(rows: Range<Int>, keys: [[Key]], ascending: [Bool], options: Options) -> [Int] {
		func compare(_ a: Int, _ b: Int) -> ComparisonResult {
			for (column, direction) in zip(keys, ascending) {
				let (x, y) = (column[a], column[b])
				switch (x.isMissing, y.isMissing) {
				case (true, true): continue
				case (true, false): return .orderedDescending
				case (false, true): return .orderedAscending
				default: break
				}
				var result = compareKeys(x, y, flags: options.flags)
				if !direction {
					result = ComparisonResult(rawValue: -result.rawValue)!
				}
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

	static func compareKeys(_ a: Key, _ b: Key, flags: Int) -> ComparisonResult {
		switch (a, b) {
		case let (.number(x), .number(y)):
			return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
		case let (.date(x), .date(y)):
			return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
		case let (.text(x), .text(y)):
			return compareText(x, y, flags: flags)
		default:
			return .orderedSame
		}
	}

	/// Text by character code; flag 1 ignores case, 2 compares digit runs by value, 4 ignores case but puts
	/// uppercase first when otherwise equal.
	static func compareText(_ a: String, _ b: String, flags: Int) -> ComparisonResult {
		let numeric = flags & 2 != 0
		let result = compareScalars(a, b, ignoringCase: flags & (1 | 4) != 0, numeric: numeric)
		if result == .orderedSame, flags & 4 != 0 {
			return compareScalars(a, b, ignoringCase: false, numeric: numeric)
		}
		return result
	}

	private static func compareScalars(_ a: String, _ b: String, ignoringCase: Bool, numeric: Bool) -> ComparisonResult {
		let x = Array((ignoringCase ? a.lowercased() : a).unicodeScalars)
		let y = Array((ignoringCase ? b.lowercased() : b).unicodeScalars)
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

	private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
		("0" ... "9").contains(scalar)
	}

	private static func digitsEnd(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
		var end = start
		while end < scalars.count, isDigit(scalars[end]) {
			end += 1
		}
		return end
	}
}
