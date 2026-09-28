import CPCRE2
import Foundation

/// A compiled PCRE2 pattern (`syntax "PCRE"`, an MTC_OSAX extension), with PCRE's own semantics, except that `^`
/// and `$` match at every line unless the pattern (`(?-m)`) or the `SINGLELINE` flag says otherwise. Unicode-aware
/// (`\w`, `\d`, case), and any Unicode line ending counts. Text that isn't valid UTF-16 (a lone surrogate) is
/// searched rather than rejected.
final class PCREEngine: RegexEngine {
	let groupCount: Int
	let namedGroups: [String: [Int]]
	private let code: OpaquePointer
	private let matchOptions: UInt32

	/// Flags PCRE has no equivalent for: error -1, as for an unknown flag.
	private static let unsupported: [(RegexFlags, String)] = [
		(.findLongest, "FIND LONGEST"), (.negateSingleline, "NEGATE SINGLELINE"), (.newlineInNegativeCC, "NEWLINE IN NEGATIVE CC"),
	]

	init(_ pattern: String, flags: RegexFlags) throws(RegexError) {
		if let (_, name) = Self.unsupported.first(where: { flags.contains($0.0) }) {
			throw RegexError(code: -1, message: "\(name) isn't available with PCRE", isExtension: true)
		}
		var options = UInt32(PCRE2_UTF | PCRE2_UCP | PCRE2_MATCH_INVALID_UTF)
		if !flags.contains(.singleline) { options |= UInt32(PCRE2_MULTILINE) }
		if flags.contains(.ignoreCase) { options |= UInt32(PCRE2_CASELESS) }
		if flags.contains(.extend) { options |= UInt32(PCRE2_EXTENDED) }
		if flags.contains(.dotAll) { options |= UInt32(PCRE2_DOTALL) }
		if flags.contains(.dontCaptureGroup) { options |= UInt32(PCRE2_NO_AUTO_CAPTURE) }

		let context = pcre2_compile_context_create_16(nil)
		defer { pcre2_compile_context_free_16(context) }
		pcre2_set_newline_16(context, UInt32(PCRE2_NEWLINE_ANY))

		// A terminator, so an empty pattern still has an address.
		let units = Array(pattern.utf16) + [0]
		var error: Int32 = 0
		var offset = 0
		guard let code = pcre2_compile_16(units, units.count - 1, options, &error, &offset, context) else {
			throw RegexError(code: -3000 - Int(error), message: "\(Self.message(for: error)) at offset \(offset)", isExtension: true)
		}
		self.code = code

		var matchOptions: UInt32 = 0
		if flags.contains(.findNotEmpty) { matchOptions |= UInt32(PCRE2_NOTEMPTY) }
		if flags.contains(.notBOL) { matchOptions |= UInt32(PCRE2_NOTBOL) }
		if flags.contains(.notEOL) { matchOptions |= UInt32(PCRE2_NOTEOL) }
		self.matchOptions = matchOptions

		var count: UInt32 = 0
		pcre2_pattern_info_16(code, UInt32(PCRE2_INFO_CAPTURECOUNT), &count)
		groupCount = Int(count)
		namedGroups = Self.namedGroups(of: code)
	}

	deinit {
		pcre2_code_free_16(code)
	}

	/// Forward: PCRE's search from `start`. Backward: the last position from `start` down to `limit` where the
	/// pattern matches (PCRE can only search forward, so each position is tried anchored).
	func search(_ text: UTF16Text, bounds: Range<Int>, start: Int, limit: Int) -> RegexMatch? {
		guard let data = pcre2_match_data_create_from_pattern_16(code, nil) else { return nil }
		defer { pcre2_match_data_free_16(data) }
		func run(_ subject: UnsafePointer<UInt16>) -> RegexMatch? {
			func match(at position: Int, options: UInt32) -> RegexMatch? {
				let result = pcre2_match_16(code, subject, bounds.upperBound, position, matchOptions | options, data, nil)
				guard result > 0 else { return nil }
				let vector = pcre2_get_ovector_pointer_16(data)!
				return RegexMatch(groups: (0 ... groupCount).map { index -> Range<Int>? in
					guard index < Int(result) else { return nil }
					let begin = vector[2 * index]
					let end = vector[2 * index + 1]
					// PCRE2_UNSET is all bits set.
					guard begin &+ 1 != 0 else { return nil }
					// \K can put the start after the end; the match is then empty at the end.
					return Int(min(begin, end)) ..< Int(end)
				})
			}
			guard limit < start else {
				return start <= limit ? match(at: start, options: 0) : nil
			}
			var position = start
			while position >= limit {
				if let found = match(at: position, options: UInt32(PCRE2_ANCHORED)) {
					return found
				}
				position -= 1
			}
			return nil
		}
		// Empty text still needs an address.
		return text.units.isEmpty ? [UInt16(0)].withUnsafeBufferPointer { run($0.baseAddress!) }
			: text.units.withUnsafeBufferPointer { run($0.baseAddress!) }
	}

	private static func message(for error: Int32) -> String {
		var buffer = [UInt16](repeating: 0, count: 256)
		let length = pcre2_get_error_message_16(error, &buffer, buffer.count)
		return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF16.self) : "PCRE error \(error)"
	}

	/// PCRE's name table: each entry is the group number, then the name, padded to the entry size.
	private static func namedGroups(of code: OpaquePointer) -> [String: [Int]] {
		var count: UInt32 = 0
		var size: UInt32 = 0
		var table: UnsafePointer<UInt16>?
		pcre2_pattern_info_16(code, UInt32(PCRE2_INFO_NAMECOUNT), &count)
		pcre2_pattern_info_16(code, UInt32(PCRE2_INFO_NAMEENTRYSIZE), &size)
		pcre2_pattern_info_16(code, UInt32(PCRE2_INFO_NAMETABLE), &table)
		guard let table else { return [:] }
		var names: [String: [Int]] = [:]
		for entry in 0 ..< Int(count) {
			let start = table + entry * Int(size)
			let nameUnits = UnsafeBufferPointer(start: start + 1, count: Int(size) - 1).prefix { $0 != 0 }
			names[String(decoding: nameUnits, as: UTF16.self), default: []].append(Int(start[0]))
		}
		return names
	}
}
