import COnigmo
import Foundation

/// A regex syntax, named as in Satimage's `syntax` parameter.
public enum RegexSyntax: String, CaseIterable, Sendable {
	case ruby = "RUBY"
	case perl = "PERL"
	case java = "JAVA"
	case gnuRegex = "GNU_REGEX"
	case grep = "GREP"
	case emacs = "EMACS"
	case posixBasic = "POSIX"
	case posixExtended = "POSIX_EXTENDED"

	/// Accepts Satimage's names in any case, with spaces or underscores.
	public init?(name: String) {
		let normalized = name.uppercased().replacingOccurrences(of: " ", with: "_")
		self.init(rawValue: normalized)
	}

	var onigmoSyntax: MTCOnigSyntax {
		switch self {
		case .ruby: MTCOnigSyntaxRuby
		case .perl: MTCOnigSyntaxPerl
		case .java: MTCOnigSyntaxJava
		case .gnuRegex: MTCOnigSyntaxGnuRegex
		case .grep: MTCOnigSyntaxGrep
		case .emacs: MTCOnigSyntaxEmacs
		case .posixBasic: MTCOnigSyntaxPosixBasic
		case .posixExtended: MTCOnigSyntaxPosixExtended
		}
	}
}

/// Satimage's `regexpflag` values, plus MTC_OSAX's `DOLLAR REFERENCES` extension.
public struct RegexFlags: OptionSet, Hashable, Sendable {
	public let rawValue: UInt32

	public init(rawValue: UInt32) {
		self.rawValue = rawValue
	}

	public static let ignoreCase = RegexFlags(rawValue: 1 << 0)
	public static let extend = RegexFlags(rawValue: 1 << 1)
	/// `.` matches newlines (Onigmo's meaning of "multiline").
	public static let multiline = RegexFlags(rawValue: 1 << 2)
	/// `^` and `$` match only at the start and end of the text.
	public static let singleline = RegexFlags(rawValue: 1 << 3)
	public static let findLongest = RegexFlags(rawValue: 1 << 4)
	public static let findNotEmpty = RegexFlags(rawValue: 1 << 5)
	public static let negateSingleline = RegexFlags(rawValue: 1 << 6)
	public static let dontCaptureGroup = RegexFlags(rawValue: 1 << 7)
	public static let notBOL = RegexFlags(rawValue: 1 << 8)
	public static let notEOL = RegexFlags(rawValue: 1 << 9)
	/// Negative character classes such as `[^a-z]` also match `\n` and `\r` (by default they don't, in any syntax).
	public static let newlineInNegativeCC = RegexFlags(rawValue: 1 << 10)
	/// MTC_OSAX extension: `$1`-style references in replacement templates. Doesn't affect matching.
	public static let dollarReferences = RegexFlags(rawValue: 1 << 11)

	private static let names: [String: RegexFlags] = [
		"IGNORECASE": .ignoreCase,
		"EXTEND": .extend,
		"MULTILINE": .multiline,
		"SINGLELINE": .singleline,
		"FIND_LONGEST": .findLongest,
		"FIND_NOT_EMPTY": .findNotEmpty,
		"NEGATE_SINGLELINE": .negateSingleline,
		"DONT_CAPTURE_GROUP": .dontCaptureGroup,
		"NOTBOL": .notBOL,
		"NOTEOL": .notEOL,
		"NEWLINE_IN_NEGATIVE_CC": .newlineInNegativeCC,
		"DOLLAR_REFERENCES": .dollarReferences,
	]

	/// Parses flag names as scripts write them (`"FIND LONGEST"` or `"FIND_LONGEST"`, any case).
	/// Returns nil if any name is unknown.
	public init?(names: [String]) {
		var flags: RegexFlags = []
		for name in names {
			let key = name.uppercased().replacingOccurrences(of: " ", with: "_")
			guard let flag = Self.names[key] else {
				return nil
			}
			flags.insert(flag)
		}
		self = flags
	}

	/// Options given to Onigmo when compiling.
	var compileOptions: OnigOptionType {
		var options: OnigOptionType = 0
		let mapping: [(RegexFlags, OnigOptionType)] = [
			(.ignoreCase, MTCOnigOptionIgnoreCase),
			(.extend, MTCOnigOptionExtend),
			(.multiline, MTCOnigOptionMultiline),
			(.singleline, MTCOnigOptionSingleline),
			(.findLongest, MTCOnigOptionFindLongest),
			(.findNotEmpty, MTCOnigOptionFindNotEmpty),
			(.negateSingleline, MTCOnigOptionNegateSingleline),
			(.dontCaptureGroup, MTCOnigOptionDontCaptureGroup),
		]
		for (flag, option) in mapping where contains(flag) {
			options |= option
		}
		// Satimage numbers unnamed groups even when the pattern also has named ones.
		if !contains(.dontCaptureGroup) {
			options |= MTCOnigOptionCaptureGroup
		}
		return options
	}

	/// Options given to Onigmo when searching.
	var searchOptions: OnigOptionType {
		var options: OnigOptionType = 0
		if contains(.notBOL) { options |= MTCOnigOptionNotBOL }
		if contains(.notEOL) { options |= MTCOnigOptionNotEOL }
		return options
	}
}

/// A pattern that failed to compile.
public struct RegexError: Error, Equatable, CustomStringConvertible {
	/// Onigmo's error code (negative).
	public let code: Int
	public let message: String

	public var description: String { message }
}

/// A match: the range of the whole match and of each group, in UTF-16 offsets. Unmatched groups are nil.
public struct RegexMatch: Equatable, Sendable {
	public let groups: [Range<Int>?]

	public var range: Range<Int> { groups[0]! }
}

/// A compiled Onigmo pattern. Searches text as UTF-16, so offsets are UTF-16 code units, as in `NSString`.
///
/// Matches Satimage's build of Onigmo (see the line-end fixtures): CR, LF, NEL, U+2028 and U+2029 are line ends,
/// negated classes exclude `\n` and `\r` in every syntax unless `newlineInNegativeCC` is given, and unnamed groups
/// are numbered alongside named ones.
public final class CompiledRegex {
	public let pattern: String
	public let syntax: RegexSyntax
	public let flags: RegexFlags
	/// Number of capture groups, not counting the whole match.
	public let groupCount: Int
	/// Group numbers for each named group.
	public let namedGroups: [String: [Int]]

	private let regex: OnigRegex
	/// Onigmo keeps a pointer to the syntax, so the modified copy must live as long as the regex.
	private let customSyntax: UnsafeMutablePointer<OnigSyntaxType>

	public init(_ pattern: String, syntax: RegexSyntax = .ruby, flags: RegexFlags = []) throws(RegexError) {
		self.pattern = pattern
		self.syntax = syntax
		self.flags = flags

		let syntaxCopy = UnsafeMutablePointer<OnigSyntaxType>.allocate(capacity: 1)
		onig_copy_syntax(syntaxCopy, mtc_onig_syntax(syntax.onigmoSyntax))
		var behavior = onig_get_syntax_behavior(syntaxCopy) | MTCOnigSynNotNewlineInNegativeCC
		if flags.contains(.newlineInNegativeCC) {
			behavior &= ~MTCOnigSynNotNewlineInNegativeCC
		}
		onig_set_syntax_behavior(syntaxCopy, behavior)
		customSyntax = syntaxCopy

		var compiled: OnigRegex?
		var errorInfo = OnigErrorInfo()
		let units = Array(pattern.utf16)
		let status = units.withUnsafeBytes { bytes in
			let start = bytes.baseAddress!.assumingMemoryBound(to: OnigUChar.self)
			return onig_new(&compiled, start, start + bytes.count, flags.compileOptions, mtc_onig_encoding_satimage_utf16le(), syntaxCopy, &errorInfo)
		}
		guard status == ONIG_NORMAL, let compiled else {
			syntaxCopy.deallocate()
			throw RegexError(code: Int(status), message: Self.message(for: Int(status), info: &errorInfo))
		}
		regex = compiled
		groupCount = Int(onig_number_of_captures(compiled))
		namedGroups = Self.namedGroups(of: compiled)
	}

	deinit {
		onig_free(regex)
		customSyntax.deallocate()
	}

	/// The first match starting at or after `start` (or, with `backward`, the last match starting at or before it),
	/// looking only within `bounds`. `bounds` defaults to the whole text.
	public func firstMatch(in text: UTF16Text, from start: Int? = nil, within bounds: Range<Int>? = nil, backward: Bool = false) -> RegexMatch? {
		let bounds = bounds ?? 0 ..< text.count
		let start = start ?? (backward ? bounds.upperBound : bounds.lowerBound)
		let limit = backward ? bounds.lowerBound : bounds.upperBound
		return search(text, bounds: bounds, start: start, limit: limit)
	}

	/// Every non-overlapping match within `bounds`, left to right. After an empty match, the search
	/// continues one character later, so it always terminates.
	public func allMatches(in text: UTF16Text, within bounds: Range<Int>? = nil) -> [RegexMatch] {
		let bounds = bounds ?? 0 ..< text.count
		var matches: [RegexMatch] = []
		var position = bounds.lowerBound
		while position <= bounds.upperBound, let match = search(text, bounds: bounds, start: position, limit: bounds.upperBound) {
			matches.append(match)
			if match.range.isEmpty {
				guard match.range.upperBound < bounds.upperBound else { break }
				position = text.index(after: match.range.upperBound)
			} else {
				position = match.range.upperBound
			}
		}
		return matches
	}

	/// Runs `onig_search`: the text seen by the regex ends at `bounds.upperBound`, but starts at the beginning
	/// of the whole text, so lookbehind and `^` see what comes before `bounds.lowerBound`.
	private func search(_ text: UTF16Text, bounds: Range<Int>, start: Int, limit: Int) -> RegexMatch? {
		let region = onig_region_new()!
		defer { onig_region_free(region, 1) }

		let position = text.units.withUnsafeBytes { bytes -> OnigPosition in
			let base = bytes.baseAddress?.assumingMemoryBound(to: OnigUChar.self) ?? UnsafePointer(bitPattern: 1)!
			return onig_search(
				regex,
				base,
				base + bounds.upperBound * 2,
				base + start * 2,
				base + limit * 2,
				region,
				flags.searchOptions
			)
		}
		guard position >= 0 else {
			return nil
		}
		let groups = (0 ..< Int(region.pointee.num_regs)).map { index -> Range<Int>? in
			let begin = region.pointee.beg[index]
			let end = region.pointee.end[index]
			return begin < 0 ? nil : Int(begin) / 2 ..< Int(end) / 2
		}
		return RegexMatch(groups: groups)
	}

	private static func message(for code: Int, info: inout OnigErrorInfo) -> String {
		var buffer = [OnigUChar](repeating: 0, count: Int(MTCOnigMaxErrorMessageLength) + 1)
		let length = mtc_onig_error_message(&buffer, OnigPosition(code), &info)
		// Error messages quote the pattern in its own encoding (UTF-16LE); decode leniently.
		let bytes = Array(buffer.prefix(Int(max(length, 0))))
		return String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self)
	}

	private static func namedGroups(of regex: OnigRegex) -> [String: [Int]] {
		final class Collector {
			var names: [String: [Int]] = [:]
		}
		let collector = Collector()
		_ = onig_foreach_name(regex, { nameStart, nameEnd, count, groups, _, context in
			let collector = Unmanaged<Collector>.fromOpaque(context!).takeUnretainedValue()
			let byteCount = nameEnd! - nameStart!
			let name = UnsafeRawPointer(nameStart!).withMemoryRebound(to: UInt16.self, capacity: byteCount / 2) {
				String(decoding: UnsafeBufferPointer(start: $0, count: byteCount / 2), as: UTF16.self)
			}
			collector.names[name] = (0 ..< Int(count)).map { Int(groups![$0]) }
			return 0
		}, Unmanaged.passUnretained(collector).toOpaque())
		return collector.names
	}
}
