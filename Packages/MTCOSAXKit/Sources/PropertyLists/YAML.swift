import AppleEventCore
import CYAML
import Foundation

/// `PlistToYAML` and `PlistFromYAML` (MTC_OSAX extensions), between property list values (as
/// `PropertyLists.object(of:)` gives them) and YAML, with YAML 1.2's rules for booleans and null. Reading uses
/// libyaml; writing is ours.
enum YAML {
	// MARK: Writing

	/// Block style with two-space indentation (sequences in a mapping aren't indented further); text is plain when
	/// it can't be read as anything else, otherwise double-quoted. Dates are plain, in UTC with whole seconds;
	/// data is `!!binary`; `missing value` is `null`.
	static func write(_ object: Any) -> String {
		var lines: [String] = []
		if let collection = block(object) {
			append(collection, indent: 0, into: &lines)
		} else {
			lines.append(scalar(object))
		}
		return lines.joined(separator: "\n") + "\n"
	}

	private enum Block {
		case mapping([(String, Any)])
		case sequence([Any])
	}

	/// A non-empty dictionary or array; empty ones are written inline (`{}`, `[]`).
	private static func block(_ value: Any) -> Block? {
		if let dictionary = value as? NSDictionary, dictionary.count > 0 {
			return .mapping(dictionary.allKeys.compactMap { key in (key as? String).map { ($0, dictionary[key]!) } })
		}
		if let array = value as? NSArray, array.count > 0 {
			return .sequence(array.map { $0 })
		}
		return nil
	}

	private static func append(_ block: Block, indent: Int, into lines: inout [String], firstPrefix: String? = nil) {
		let pad = String(repeating: " ", count: indent)
		var prefix = firstPrefix
		func line(_ text: String) {
			lines.append((prefix ?? pad) + text)
			prefix = nil
		}
		switch block {
		case let .mapping(entries):
			for (key, value) in entries {
				if let child = self.block(value) {
					line(scalarText(key) + ":")
					switch child {
					case .mapping: append(child, indent: indent + 2, into: &lines)
					case .sequence: append(child, indent: indent, into: &lines)
					}
				} else {
					line(scalarText(key) + ": " + scalar(value))
				}
			}
		case let .sequence(items):
			for item in items {
				if let child = self.block(item) {
					// The first line of a nested collection goes after the dash.
					let dash = (prefix ?? pad) + "- "
					prefix = nil
					append(child, indent: indent + 2, into: &lines, firstPrefix: dash)
				} else {
					line("- " + scalar(item))
				}
			}
		}
	}

	private static func scalar(_ value: Any) -> String {
		if isMissingValue(value) {
			return "null"
		}
		switch value {
		case let text as String:
			return scalarText(text)
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return number.boolValue ? "true" : "false"
			}
			if CFNumberIsFloatType(number) {
				let real = number.doubleValue
				if real.isNaN { return ".nan" }
				if real.isInfinite { return real < 0 ? "-.inf" : ".inf" }
				return "\(real)"
			}
			return String(number.int64Value)
		case let date as Date:
			return ISO8601DateFormatter().string(from: date)
		case let data as Data:
			return "!!binary " + data.base64EncodedString()
		case let dictionary as NSDictionary where dictionary.count == 0:
			return "{}"
		case let array as NSArray where array.count == 0:
			return "[]"
		default:
			return scalarText("\(value)")
		}
	}

	/// Text, plain when it would read back as the same text, otherwise double-quoted.
	static func scalarText(_ text: String) -> String {
		isPlainSafe(text) ? text : quoted(text)
	}

	private static let indicators: Set<Character> = ["-", "?", ":", ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`"]

	private static func isPlainSafe(_ text: String) -> Bool {
		guard let first = text.first, let last = text.last,
		      !first.isWhitespace, !last.isWhitespace, last != ":", !indicators.contains(first),
		      !text.contains(": "), !text.contains(" #"),
		      !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || $0 == "\u{85}" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{FEFF}" })
		else {
			return false
		}
		// Anything a YAML reader could take for another type (YAML 1.1's yes/no too, for older readers).
		if case .text = resolve(plain: text), !["yes", "no", "on", "off", "y", "n"].contains(text.lowercased()) {
			return true
		}
		return false
	}

	private static func quoted(_ text: String) -> String {
		var result = "\""
		for scalar in text.unicodeScalars {
			switch scalar {
			case "\"": result += "\\\""
			case "\\": result += "\\\\"
			case "\n": result += "\\n"
			case "\t": result += "\\t"
			case "\r": result += "\\r"
			case "\0": result += "\\0"
			default:
				if scalar.value < 0x20 || scalar.value == 0x7F || scalar == "\u{85}" || scalar == "\u{2028}" || scalar == "\u{2029}" || scalar == "\u{FEFF}" {
					result += String(format: "\\u%04X", scalar.value)
				} else {
					result.unicodeScalars.append(scalar)
				}
			}
		}
		return result + "\""
	}

	// MARK: Resolving plain scalars

	enum Resolved {
		case null
		case boolean(Bool)
		case integer(Int64)
		case real(Double)
		case date(Date)
		case text
	}

	private static var integerPattern: Regex<Substring> { /[-+]?[0-9]+/ }
	private static var octalPattern: Regex<(Substring, Substring)> { /0o([0-7]+)/ }
	private static var hexPattern: Regex<(Substring, Substring)> { /0x([0-9a-fA-F]+)/ }
	private static var realPattern: Regex<(Substring, Substring, Substring?, Substring?)> { /[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?/ }
	private static var datePattern: Regex<(Substring, Substring, Substring, Substring)> { /([0-9]{4})-([0-9]{2})-([0-9]{2})/ }
	private static var timestampPattern: Regex<(Substring, Substring, Substring, Substring, Substring, Substring, Substring, Substring?, Substring?)> { /([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?:[Tt]|[ \t]+)([0-9]{1,2}):([0-9]{2}):([0-9]{2})(\.[0-9]*)?(?:[ \t]*(Z|[-+][0-9]{1,2}(?::?[0-9]{2})?))?/ }

	/// A plain scalar by YAML 1.2's core schema, plus YAML 1.1's timestamps: a date without a zone is in `timeZone`.
	static func resolve(plain text: String, timeZone: TimeZone = .current) -> Resolved {
		switch text {
		case "", "~", "null", "Null", "NULL": return .null
		case "true", "True", "TRUE": return .boolean(true)
		case "false", "False", "FALSE": return .boolean(false)
		case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF": return .real(.infinity)
		case "-.inf", "-.Inf", "-.INF": return .real(-.infinity)
		case ".nan", ".NaN", ".NAN": return .real(.nan)
		default: break
		}
		if text.wholeMatch(of: integerPattern) != nil {
			if let integer = Int64(text.hasPrefix("+") ? String(text.dropFirst()) : text) { return .integer(integer) }
			return Double(text).map { .real($0) } ?? .text
		}
		if let match = text.wholeMatch(of: octalPattern), let integer = Int64(match.1, radix: 8) { return .integer(integer) }
		if let match = text.wholeMatch(of: hexPattern), let integer = Int64(match.1, radix: 16) { return .integer(integer) }
		if text.wholeMatch(of: realPattern) != nil, let real = Double(text) { return .real(real) }
		if let match = text.wholeMatch(of: datePattern) {
			return date(year: match.1, month: match.2, day: match.3, timeZone: timeZone).map { .date($0) } ?? .text
		}
		if let match = text.wholeMatch(of: timestampPattern) {
			var zone = timeZone
			if let designator = match.8 {
				zone = designator == "Z" ? TimeZone(secondsFromGMT: 0)! : offsetZone(String(designator)) ?? timeZone
			}
			let fraction = match.7.flatMap { Double("0" + $0) } ?? 0
			return date(year: match.1, month: match.2, day: match.3, hour: match.4, minute: match.5, second: match.6,
			            nanosecond: Int((fraction * 1e9).rounded()), timeZone: zone).map { .date($0) } ?? .text
		}
		return .text
	}

	private static func offsetZone(_ text: String) -> TimeZone? {
		let sign = text.hasPrefix("-") ? -1 : 1
		let digits = text.dropFirst().filter(\.isNumber)
		let hours = Int(digits.prefix(digits.count > 2 ? digits.count - 2 : digits.count)) ?? 0
		let minutes = digits.count > 2 ? Int(digits.suffix(2)) ?? 0 : 0
		return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
	}

	private static func date(year: Substring, month: Substring, day: Substring, hour: Substring = "0", minute: Substring = "0",
	                         second: Substring = "0", nanosecond: Int = 0, timeZone: TimeZone) -> Date?
	{
		var components = DateComponents(year: Int(year), month: Int(month), day: Int(day), hour: Int(hour), minute: Int(minute),
		                                 second: Int(second), nanosecond: nanosecond)
		components.timeZone = timeZone
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = timeZone
		guard components.isValidDate(in: calendar) else { return nil }
		return calendar.date(from: components)
	}

	// MARK: Reading

	private static let tagPrefix = "tag:yaml.org,2002:"

	/// One YAML document as a property list value. -1 with libyaml's message (line and column) for text that isn't
	/// YAML or has no document; -50 for several documents, a mapping or sequence used as a key, or an alias that
	/// contains itself.
	static func read(_ text: String, timeZone: TimeZone = .current) throws -> Any {
		var parser = yaml_parser_t()
		guard yaml_parser_initialize(&parser) == 1 else { throw OSAXError(-1, "YAML reader unavailable") }
		defer { yaml_parser_delete(&parser) }
		let bytes = Array(text.utf8)
		return try bytes.withUnsafeBufferPointer { buffer in
			yaml_parser_set_input_string(&parser, buffer.baseAddress ?? UnsafePointer([0]), buffer.count)
			var document = yaml_document_t()
			guard yaml_parser_load(&parser, &document) == 1 else { throw error(parser) }
			defer { yaml_document_delete(&document) }
			guard let root = yaml_document_get_root_node(&document) else {
				throw OSAXError(-1, "Not YAML: there's no document.")
			}
			var next = yaml_document_t()
			guard yaml_parser_load(&parser, &next) == 1 else { throw error(parser) }
			let another = yaml_document_get_root_node(&next) != nil
			yaml_document_delete(&next)
			if another {
				throw OSAXError(-50, "The YAML has several documents; PlistFromYAML reads one.")
			}
			var reader = Reader(document: document, timeZone: timeZone)
			return try reader.object(root)
		}
	}

	private static func error(_ parser: yaml_parser_t) -> OSAXError {
		let problem = parser.problem.map { String(cString: $0) } ?? "invalid YAML"
		let context = parser.context.map { String(cString: $0) + " " } ?? ""
		let mark = parser.problem_mark
		return OSAXError(-1, "Not YAML: \(context)\(problem) at line \(mark.line + 1), column \(mark.column + 1)")
	}

	private struct Reader {
		var document: yaml_document_t
		let timeZone: TimeZone
		/// Nodes being read, to catch an alias inside itself.
		var active: Set<Int> = []

		init(document: yaml_document_t, timeZone: TimeZone) {
			self.document = document
			self.timeZone = timeZone
		}

		mutating func node(_ index: Int32) -> UnsafeMutablePointer<yaml_node_t>? {
			yaml_document_get_node(&document, index)
		}

		mutating func object(_ node: UnsafeMutablePointer<yaml_node_t>) throws -> Any {
			let identity = Int(bitPattern: node)
			guard active.insert(identity).inserted else {
				throw OSAXError(-50, "The YAML has an alias inside what it refers to, which can't be a property list.")
			}
			defer { active.remove(identity) }
			let tag = node.pointee.tag.map { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) } ?? ""
			switch node.pointee.type {
			case YAML_SCALAR_NODE:
				return try scalar(node, tag: tag)
			case YAML_SEQUENCE_NODE:
				var items: [Any] = []
				var item = node.pointee.data.sequence.items.start
				while let current = item, current != node.pointee.data.sequence.items.top {
					guard let child = self.node(current.pointee) else { break }
					items.append(try object(child))
					item = current + 1
				}
				return items as NSArray
			case YAML_MAPPING_NODE:
				return try mapping(node)
			default:
				return PropertyLists.missingValueData
			}
		}

		/// A mapping; merge keys (`<<`) add the keys of a mapping, or of each in a sequence, that aren't there.
		mutating func mapping(_ node: UnsafeMutablePointer<yaml_node_t>) throws -> NSMutableDictionary {
			let dictionary = NSMutableDictionary()
			var merged: [NSDictionary] = []
			var pair = node.pointee.data.mapping.pairs.start
			while let current = pair, current != node.pointee.data.mapping.pairs.top {
				pair = current + 1
				guard let keyNode = self.node(current.pointee.key), let valueNode = self.node(current.pointee.value) else { continue }
				guard keyNode.pointee.type == YAML_SCALAR_NODE else {
					throw OSAXError(-50, "The YAML has a mapping or sequence as a key; a property list's keys are text.")
				}
				let key = text(keyNode)
				if key == "<<", keyNode.pointee.data.scalar.style == YAML_PLAIN_SCALAR_STYLE {
					switch try object(valueNode) {
					case let source as NSDictionary: merged.append(source)
					case let sources as NSArray: merged += sources.compactMap { $0 as? NSDictionary }
					default: throw OSAXError(-50, "The YAML's merge key (<<) needs a mapping or a list of mappings.")
					}
					continue
				}
				dictionary[key] = try object(valueNode)
			}
			for source in merged {
				for (key, value) in source where dictionary[key] == nil {
					dictionary[key] = value
				}
			}
			return dictionary
		}

		func text(_ node: UnsafeMutablePointer<yaml_node_t>) -> String {
			let scalar = node.pointee.data.scalar
			guard let value = scalar.value else { return "" }
			return String(decoding: UnsafeBufferPointer(start: value, count: scalar.length), as: UTF8.self)
		}

		/// Plain scalars are resolved (YAML 1.2, plus timestamps); quoted ones are text; tags win.
		func scalar(_ node: UnsafeMutablePointer<yaml_node_t>, tag: String) throws -> Any {
			let value = text(node)
			let isPlain = node.pointee.data.scalar.style == YAML_PLAIN_SCALAR_STYLE
			switch tag.hasPrefix(tagPrefix) ? String(tag.dropFirst(tagPrefix.count)) : tag {
			case "binary":
				guard let data = Data(base64Encoded: value.filter { !$0.isWhitespace }) else {
					throw OSAXError(-50, "The YAML's !!binary value isn't base64.")
				}
				return data
			case "str" where isPlain:
				// libyaml gives untagged scalars the str tag, so a plain one is resolved.
				return resolved(value)
			case "str":
				return value
			case "null", "bool", "int", "float", "timestamp":
				return resolved(value)
			default:
				return value
			}
		}

		func resolved(_ value: String) -> Any {
			switch YAML.resolve(plain: value, timeZone: timeZone) {
			case .null: return PropertyLists.missingValueData
			case let .boolean(boolean): return NSNumber(value: boolean)
			case let .integer(integer): return NSNumber(value: integer)
			case let .real(real): return NSNumber(value: real)
			case let .date(date): return date
			case .text: return value
			}
		}
	}
}
