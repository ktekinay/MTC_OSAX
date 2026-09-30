import AppleEventCore
import CTOML
import Foundation

/// `PlistToTOML` and `PlistFromTOML` (MTC_OSAX extensions), between property list values (as `PropertyLists.object(of:)`
/// gives them) and TOML. Reading uses tomlc17 (TOML 1.1); writing is ours.
enum TOML {
	// MARK: Writing

	/// A dictionary as a TOML document: in each table the keys with simple values first, then sub-tables
	/// (`[a.b]`) and arrays of tables (`[[a]]`). Dates are UTC with whole seconds, data is base64 text, and a
	/// `missing value` in a table is the comment `# key = NULL`. -50 for anything else at the top level, and for a
	/// `missing value` in an array.
	static func write(_ object: Any) throws -> String {
		guard let table = object as? NSDictionary else {
			throw OSAXError(-50, "TOML's top level must be a table: give PlistToTOML a dictionary.")
		}
		try checkSizes(table)
		var lines: [String] = []
		try writeTable(table, path: [], header: nil, into: &lines)
		return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
	}

	/// The most keys in a table, or items in an array, tomlc17 reads (it refuses 16,384; its keys are looked up one by
	/// one, so it can't take many more): PlistToTOML wrote what PlistFromTOML then refused.
	static let maximumCount = (1 << 14) - 1

	private static func checkSizes(_ object: Any) throws {
		let children: [Any]
		switch object {
		case let dictionary as NSDictionary: children = dictionary.allValues
		case let array as NSArray: children = array as [AnyObject]
		default: return
		}
		guard children.count <= maximumCount else {
			throw OSAXError(-50, "TOML (as MTC_OSAX reads it) has at most \(maximumCount) keys in a table or items in an array.")
		}
		try children.forEach(checkSizes)
	}

	private static func writeTable(_ table: NSDictionary, path: [String], header: String?, into lines: inout [String]) throws {
		let keys = table.allKeys.compactMap { $0 as? String }
		let simple = keys.filter { !isTable(table[$0]!) && !isArrayOfTables(table[$0]!) }
		let nested = keys.filter { isTable(table[$0]!) || isArrayOfTables(table[$0]!) }
		// A table with only sub-tables needs no header of its own; an empty one does.
		if let header, !(simple.isEmpty && !nested.isEmpty) {
			if !lines.isEmpty { lines.append("") }
			lines.append(header)
		}
		for key in simple {
			let value = table[key]!
			if isMissingValue(value) {
				lines.append("# \(self.key(key)) = NULL")
			} else {
				lines.append("\(self.key(key)) = \(try inline(value, path: path + [key]))")
			}
		}
		for key in nested {
			let value = table[key]!
			let childPath = path + [key]
			let name = childPath.map(self.key).joined(separator: ".")
			if let child = value as? NSDictionary {
				try writeTable(child, path: childPath, header: "[\(name)]", into: &lines)
			} else if let array = value as? NSArray {
				for case let element as NSDictionary in array {
					if !lines.isEmpty { lines.append("") }
					lines.append("[[\(name)]]")
					var body: [String] = []
					try writeTable(element, path: childPath, header: nil, into: &body)
					lines += body
				}
			}
		}
	}

	private static func isTable(_ value: Any) -> Bool {
		value is NSDictionary
	}

	/// A non-empty array whose elements are all dictionaries: an array of tables.
	private static func isArrayOfTables(_ value: Any) -> Bool {
		guard let array = value as? NSArray, array.count > 0 else { return false }
		return array.allSatisfy { $0 is NSDictionary }
	}

	/// A value on one line: arrays and inline tables (`{ a = 1 }`) for dictionaries inside arrays.
	private static func inline(_ value: Any, path: [String]) throws -> String {
		if isMissingValue(value) {
			throw OSAXError(-50, "TOML has no null: the missing value in \(path.joined(separator: ".")) can only be written as a table's key.")
		}
		switch value {
		case let text as String:
			return quoted(text)
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return number.boolValue ? "true" : "false"
			}
			if CFNumberIsFloatType(number) {
				return real(number.doubleValue)
			}
			return String(number.int64Value)
		case let date as Date:
			return ISO8601DateFormatter().string(from: date)
		case let data as Data:
			return quoted(data.base64EncodedString())
		case let array as NSArray:
			return "[" + (try array.map { try inline($0, path: path) }).joined(separator: ", ") + "]"
		case let table as NSDictionary:
			let entries = try table.allKeys.compactMap { $0 as? String }.map { key in
				"\(self.key(key)) = \(try inline(table[key]!, path: path + [key]))"
			}
			return entries.isEmpty ? "{}" : "{ " + entries.joined(separator: ", ") + " }"
		default:
			return quoted("\(value)")
		}
	}

	private static func real(_ value: Double) -> String {
		if value.isNaN { return "nan" }
		if value.isInfinite { return value < 0 ? "-inf" : "inf" }
		return "\(value)"
	}

	/// A key: bare when it can be (letters, digits, `_` and `-`), otherwise quoted.
	static func key(_ key: String) -> String {
		let bare = !key.isEmpty && key.unicodeScalars.allSatisfy { scalar in
			scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-")
		}
		return bare ? key : quoted(key)
	}

	/// A basic string, with TOML's escapes.
	static func quoted(_ text: String) -> String {
		var result = "\""
		for scalar in text.unicodeScalars {
			switch scalar {
			case "\"": result += "\\\""
			case "\\": result += "\\\\"
			case "\n": result += "\\n"
			case "\t": result += "\\t"
			case "\r": result += "\\r"
			case "\u{08}": result += "\\b"
			case "\u{0C}": result += "\\f"
			default:
				if scalar.value < 0x20 || scalar.value == 0x7F {
					result += String(format: "\\u%04X", scalar.value)
				} else {
					result.unicodeScalars.append(scalar)
				}
			}
		}
		return result + "\""
	}

	// MARK: Reading

	/// A TOML document as a dictionary. Offset date-times are that moment; local date-times and dates are read in
	/// `timeZone` (a date alone is midnight); local times are text. Comments are ignored. -1 with tomlc17's
	/// message for text that isn't TOML.
	static func read(_ text: String, timeZone: TimeZone = .current) throws -> Any {
		let length = try Int32(length: text.utf8.count)
		let result = text.withCString { toml_parse($0, length) }
		defer { toml_free(result) }
		guard result.ok else {
			let message = withUnsafeBytes(of: result.errmsg) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
			throw OSAXError(-1, "Not TOML: \(message)")
		}
		return object(result.toptab, timeZone: timeZone)
	}

	private static func object(_ datum: toml_datum_t, timeZone: TimeZone) -> Any {
		switch datum.type {
		case TOML_STRING:
			return string(datum.u.str.ptr, Int(datum.u.str.len))
		case TOML_INT64:
			return NSNumber(value: datum.u.int64)
		case TOML_FP64:
			return NSNumber(value: datum.u.fp64)
		case TOML_BOOLEAN:
			return NSNumber(value: datum.u.boolean)
		case TOML_DATETIMETZ:
			// Read in UTC and then moved by the offset: TOML allows offsets up to 23:59, TimeZone only 18 hours.
			let utc = date(datum, timeZone: TimeZone(identifier: "UTC")!)
			return utc.addingTimeInterval(-Double(datum.u.ts.tz) * 60)
		case TOML_DATETIME, TOML_DATE:
			return date(datum, timeZone: timeZone)
		case TOML_TIME:
			let ts = datum.u.ts
			var text = String(format: "%02d:%02d:%02d", ts.hour, ts.minute, ts.second)
			if ts.usec > 0 {
				text += "." + String(format: "%06d", ts.usec).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
			}
			return text
		case TOML_ARRAY:
			return (0 ..< Int(datum.u.arr.size)).map { object(datum.u.arr.elem[$0], timeZone: timeZone) } as NSArray
		case TOML_TABLE:
			let table = NSMutableDictionary()
			for index in 0 ..< Int(datum.u.tab.size) {
				table[string(datum.u.tab.key[index], Int(datum.u.tab.len[index]))] = object(datum.u.tab.value[index], timeZone: timeZone)
			}
			return table
		default:
			return ""
		}
	}

	private static func string(_ pointer: UnsafePointer<CChar>?, _ length: Int) -> String {
		guard let pointer else { return "" }
		return pointer.withMemoryRebound(to: UInt8.self, capacity: length) {
			String(decoding: UnsafeBufferPointer(start: $0, count: length), as: UTF8.self)
		}
	}

	private static func date(_ datum: toml_datum_t, timeZone: TimeZone) -> Date {
		let ts = datum.u.ts
		var components = DateComponents()
		components.year = Int(ts.year)
		components.month = Int(ts.month)
		components.day = Int(ts.day)
		if datum.type != TOML_DATE {
			components.hour = Int(ts.hour)
			components.minute = Int(ts.minute)
			components.second = Int(ts.second)
			components.nanosecond = Int(ts.usec) * 1000
		}
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = timeZone
		return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
	}
}

/// Whether a property list value is `missing value`: data holding AppleScript's `missing value`, as `PlistFromJSON`
/// stores JSON's `null`.
func isMissingValue(_ value: Any) -> Bool {
	guard let data = value as AnyObject as? NSData else {
		return false
	}
	return data as Data == PropertyLists.missingValueData
}

extension PropertyLists {
	nonisolated static let missingValueData = flatten(.missingValue)
}
