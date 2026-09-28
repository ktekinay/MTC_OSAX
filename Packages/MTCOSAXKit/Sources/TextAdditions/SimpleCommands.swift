import AppleEventCore
import Foundation

/// The commands that transform one string (or each string of a list) without searching.
/// Their exact behavior is recorded in `Fixtures/TextAdditions/Simple`.
extension TextAdditions {
	static func simpleCommands() -> [CommandDefinition] {
		[
			eachString("uppercase", code: "SATIUPPE") { transformCase($0, CFStringUppercase) },
			eachString("lowercase", code: "SATILOWE") { transformCase($0, CFStringLowercase) },
			eachString("titlecase", code: "SATICAPI") { transformCase($0, CFStringCapitalize) },

			CommandDefinition("atof", code: "SATIATOF") { request in
				try TextInput(request, keyword: Keyword.directObject).map { try parseReal($0).appleEventDescriptor }
			},
			CommandDefinition("atoi", code: "SATIATOI") { request in
				let base = try request.parameter("base", as: Int.self)
				if let base, base != 0, !(2 ... 36).contains(base) {
					throw OSAXError.parameterError
				}
				return try TextInput(request, keyword: Keyword.directObject).map { string in
					var value = try parseInteger(string, base: base == 0 ? nil : base)
					// Satimage returns a 64-bit integer (`comp`), not an AppleScript integer.
					return NSAppleEventDescriptor(descriptorType: typeSInt64, bytes: &value, length: MemoryLayout<Int64>.size)
				}
			},

			eachString("encode entities", code: "SATIEsEn", encodeEntities),
			eachString("resolve entities", code: "SATIReEn", resolveEntities),

			CommandDefinition("escapeURL", code: "SATIAdd%") { request in
				let extra = try request.parameter("escp", default: "")
				return try TextInput(request, keyword: Keyword.directObject).map { escapeURL($0, alsoEscaping: extra).appleEventDescriptor }
			},
			CommandDefinition("unescapeURL", code: "SATIRem%") { request in
				let keeping = try request.parameter("leav", default: "")
				return try TextInput(request, keyword: Keyword.directObject).map { try unescapeURL($0, keeping: keeping).appleEventDescriptor }
			},

			CommandDefinition("normalize unicode", code: "SATIUnNo") { request in
				let decompose = try request.parameter("Deco", default: false)
				return try TextInput(request, keyword: Keyword.directObject).map {
					(decompose ? $0.decomposedStringWithCanonicalMapping : $0.precomposedStringWithCanonicalMapping).appleEventDescriptor
				}
			},
			CommandDefinition("transform unicode", code: "SATIUnTr") { request in
				let transform = try request.requiredParameter("by  ", as: String.self)
				let inverse = try request.parameter("inv ", default: false)
				return try TextInput(request, keyword: Keyword.directObject).map { string in
					try transformUnicode(string, transform, inverse: inverse).appleEventDescriptor
				}
			},
			CommandDefinition("hash", code: "SATIHASH") { request in
				hash(try request.requiredDirectParameter(as: String.self))
			},

			CommandDefinition("join", code: "SATIJoin") { request in
				let separator = try request.requiredParameter("by  ", as: String.self)
				let items = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
				return try joinItems(items).joined(separator: separator)
			},
		]
	}

	/// A command that applies `transform` to its direct parameter, a string or each string of a list.
	private static func eachString(_ name: String, code: String, _ transform: @escaping (String) throws -> String) -> CommandDefinition {
		CommandDefinition(name, code: code) { request in
			try TextInput(request, keyword: Keyword.directObject).map { try transform($0).appleEventDescriptor }
		}
	}

	// MARK: Case

	/// Core Foundation's case mapping, with no locale, matches Satimage exactly (e.g. Greek final sigma,
	/// "ß" to "SS", "ǆ" to "ǅ" in title case, and word boundaries at hyphens and digits but not apostrophes).
	static func transformCase(_ string: String, _ function: (CFMutableString?, CFLocale?) -> Void) -> String {
		let mutable = NSMutableString(string: string)
		function(mutable, nil)
		return mutable as String
	}

	// MARK: Numbers

	/// Like `strtod`, accepting a comma as the decimal point. The text must start with a number; anything
	/// after it is ignored. No number: error -1700.
	static func parseReal(_ string: String) throws -> Double {
		let normalized = string.replacingOccurrences(of: ",", with: ".")
		return try normalized.withCString { start in
			var end: UnsafeMutablePointer<CChar>?
			let value = strtod(start, &end)
			guard let end, end != UnsafeMutablePointer(mutating: start) else {
				throw OSAXError.coercionFailed
			}
			return value
		}
	}

	/// The whole text must be an integer, after leading white space and an optional sign: decimal (even with
	/// leading zeros), or hexadecimal with `0x`. `base` (2–36) reads other bases; base 16 also allows `0x`.
	/// (Satimage rejected a sign before `0x`.)
	static func parseInteger(_ string: String, base: Int?) throws -> Int64 {
		var text = Substring(string.drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
		var negative = false
		if let sign = text.first, sign == "-" || sign == "+" {
			negative = sign == "-"
			text = text.dropFirst()
		}
		var radix = base ?? 10
		if base == nil || base == 16, text.hasPrefix("0x") || text.hasPrefix("0X") {
			text = text.dropFirst(2)
			radix = 16
		}
		guard let first = text.first, first != "-", first != "+", let value = Int64(text, radix: radix) else {
			throw OSAXError.coercionFailed
		}
		return negative ? -value : value
	}

	// MARK: Entities

	static func encodeEntities(_ string: String) -> String {
		var result = ""
		for character in string {
			switch character {
			case "&": result += "&amp;"
			case "<": result += "&lt;"
			case ">": result += "&gt;"
			case "\"": result += "&quot;"
			case "'": result += "&apos;"
			default: result.append(character)
			}
		}
		return result
	}

	private static let namedEntities: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]

	/// Resolves the five XML entities (exact case) and numeric references `&#65;`, `&#x41;` or `&#X41;`, in one pass.
	/// Anything else, including HTML entities and numeric references that aren't a valid character (`&#;`,
	/// `&#xZZ;`, `&#0;`, above U+10FFFF), is left alone. (Satimage turned those into U+0000 or U+FFFD.)
	/// Only the next 32 characters are looked at for the `;` (the longest reference that resolves is far shorter), so
	/// text full of `&`s doesn't take time proportional to its length squared.
	static func resolveEntities(_ string: String) -> String {
		let units = Array(string.utf16)
		var result: [UInt16] = []
		var index = 0
		while index < units.count {
			let window = (index + 1) ..< min(index + 33, units.count)
			guard units[index] == 0x26, let semicolon = units[window].firstIndex(of: 0x3B) else { // & … ;
				result.append(units[index])
				index += 1
				continue
			}
			let name = String(decoding: units[(index + 1) ..< semicolon], as: UTF16.self)
			if let replacement = namedEntities[name] {
				result += Array(replacement.utf16)
			} else if name.hasPrefix("#"), let scalar = Self.numericReference(name.dropFirst()) {
				result += Array(String(scalar).utf16)
			} else {
				result.append(units[index])
				index += 1
				continue
			}
			index = semicolon + 1
		}
		return String(decoding: result, as: UTF16.self)
	}

	/// The character of a numeric reference's digits ("65", "x41" or "X41"); nil if they aren't one.
	private static func numericReference(_ digits: Substring) -> Unicode.Scalar? {
		let hex = digits.hasPrefix("x") || digits.hasPrefix("X")
		let number = hex ? digits.dropFirst() : digits
		guard !number.isEmpty, number.allSatisfy({ hex ? $0.isHexDigit : ($0.isASCII && $0.isNumber) }),
		      let value = UInt32(number, radix: hex ? 16 : 10), value != 0
		else {
			return nil
		}
		return Unicode.Scalar(value)
	}

	// MARK: URLs

	/// Characters escapeURL leaves alone: RFC 2396's unreserved and reserved characters, except `#`.
	private static let urlLegal = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'();/?:@&=+$,")

	static func escapeURL(_ string: String, alsoEscaping extra: String) -> String {
		var allowed = urlLegal
		allowed.remove(charactersIn: extra)
		var result = ""
		for scalar in string.unicodeScalars {
			if allowed.contains(scalar) {
				result.unicodeScalars.append(scalar)
			} else {
				for byte in String(scalar).utf8 {
					result += String(format: "%%%02X", byte)
				}
			}
		}
		return result
	}

	/// Decodes `%XX` escapes as UTF-8. Characters in `keeping` stay escaped. A bad escape or invalid UTF-8: error -1.
	static func unescapeURL(_ string: String, keeping: String) throws -> String {
		let bytes = Array(string.utf8)
		var decoded: [UInt8] = []
		// Where each run of escapes starts and ends in the original, to restore kept characters.
		var result = ""
		var index = 0
		func flushEscapes(original: Substring) throws {
			guard !decoded.isEmpty else { return }
			guard let text = String(bytes: decoded, encoding: .utf8) else {
				throw invalidOptionError
			}
			if keeping.isEmpty {
				result += text
			} else {
				// Re-escape the kept characters exactly as they were written.
				var originalIndex = original.startIndex
				for character in text {
					let length = String(character).utf8.count * 3
					let end = original.index(originalIndex, offsetBy: length)
					result += keeping.contains(character) ? String(original[originalIndex ..< end]) : String(character)
					originalIndex = end
				}
			}
			decoded = []
		}
		var runStart = 0
		while index < bytes.count {
			if bytes[index] == UInt8(ascii: "%") {
				guard index + 2 < bytes.count,
				      let byte = UInt8(String(decoding: bytes[(index + 1) ... (index + 2)], as: UTF8.self), radix: 16)
				else {
					throw invalidOptionError
				}
				if decoded.isEmpty { runStart = index }
				decoded.append(byte)
				index += 3
			} else {
				try flushEscapes(original: Substring(String(decoding: bytes[runStart ..< index], as: UTF8.self)))
				let next = bytes[index...].firstIndex(of: UInt8(ascii: "%")) ?? bytes.count
				result += String(decoding: bytes[index ..< next], as: UTF8.self)
				index = next
			}
		}
		try flushEscapes(original: Substring(String(decoding: bytes[runStart ..< index], as: UTF8.self)))
		return result
	}

	// MARK: transform unicode

	/// ICU's inverses of the case transforms, which Foundation won't run in reverse.
	private static let caseInverses = ["Upper": "Lower", "Lower": "Upper", "Title": "Lower"]

	/// An ICU transform through Foundation. An unknown transform ID is error -1.
	static func transformUnicode(_ string: String, _ id: String, inverse: Bool) throws -> String {
		if let result = string.applyingTransform(StringTransform(id), reverse: inverse) {
			return result
		}
		// "Any-Upper" run in reverse is "Any-Lower" in ICU, as Satimage returned.
		if inverse, let dash = id.lastIndex(of: "-"), let target = caseInverses[String(id[id.index(after: dash)...])],
		   let result = string.applyingTransform(StringTransform(String(id[..<dash]) + "-" + target), reverse: false)
		{
			return result
		}
		throw invalidOptionError
	}

	// MARK: hash

	/// `CFHash` of the NFKD form, low 24 bits.
	static func hash(_ string: String) -> Int {
		Int(CFHash(string.decomposedStringWithCompatibilityMapping as CFString) & 0xFFFFFF)
	}

	// MARK: join

	/// Each item as text: `missing value` is "", a nested list is error -1700. A single value counts as a list of one.
	private static func joinItems(_ descriptor: NSAppleEventDescriptor) throws -> [String] {
		let items = descriptor.descriptorType == typeAEList
			? (0 ..< descriptor.numberOfItems).map { descriptor.atIndex($0 + 1)! }
			: [descriptor]
		return try items.map { item in
			if item.descriptorType == typeType, item.typeCodeValue == FourCharCode(fourCharString: "msng") {
				return ""
			}
			guard item.descriptorType != typeAEList else {
				throw OSAXError.coercionFailed
			}
			return try String(appleEventDescriptor: item)
		}
	}
}
