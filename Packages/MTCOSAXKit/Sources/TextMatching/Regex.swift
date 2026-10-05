import COnigmo
import Foundation

/// A regex syntax, named as in Satimage's `syntax` parameter, plus MTC_OSAX's `PCRE`, which uses the PCRE2 engine
/// instead of Onigmo.
public enum RegexSyntax: String, CaseIterable, Sendable {
	case ruby = "RUBY"
	case perl = "PERL"
	case java = "JAVA"
	case gnuRegex = "GNU_REGEX"
	case grep = "GREP"
	case emacs = "EMACS"
	case posixBasic = "POSIX"
	case posixExtended = "POSIX_EXTENDED"
	case pcre = "PCRE"

	/// Accepts Satimage's names in any case, with spaces or underscores.
	public init?(name: String) {
		let normalized = name.uppercased().replacingOccurrences(of: " ", with: "_")
		self.init(rawValue: normalized)
	}

	/// The Onigmo syntax; nil for PCRE.
	var onigmoSyntax: MTCOnigSyntax? {
		switch self {
		case .ruby: MTCOnigSyntaxRuby
		case .perl: MTCOnigSyntaxPerl
		case .java: MTCOnigSyntaxJava
		case .gnuRegex: MTCOnigSyntaxGnuRegex
		case .grep: MTCOnigSyntaxGrep
		case .emacs: MTCOnigSyntaxEmacs
		case .posixBasic: MTCOnigSyntaxPosixBasic
		case .posixExtended: MTCOnigSyntaxPosixExtended
		case .pcre: nil
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
	/// MTC_OSAX extension, PCRE only: `.` matches newlines (PCRE's `DOTALL`).
	public static let dotAll = RegexFlags(rawValue: 1 << 12)

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
		"DOTALL": .dotAll,
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
	var onigmoCompileOptions: OnigOptionType {
		// CR LF is one line end: `$` matches before it and `^` after it, not between the two. (SatimageOSAX's build
		// took them as two, so `change "$" into ";"` put a `;` inside every Windows line end.)
		var options: OnigOptionType = MTCOnigOptionNewlineCRLF
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
	var onigmoSearchOptions: OnigOptionType {
		var options: OnigOptionType = 0
		if contains(.notBOL) { options |= MTCOnigOptionNotBOL }
		if contains(.notEOL) { options |= MTCOnigOptionNotEOL }
		return options
	}
}

/// A pattern that failed to compile, or options the engine doesn't have.
public struct RegexError: Error, Equatable, CustomStringConvertible {
	/// Onigmo's error code (negative); for PCRE2, -3000 minus its compile error (positive: -3101 and down) or
	/// -3000 plus its match error (negative: -3047 for the match limit, -3063 for the heap limit); or -1 for an
	/// option the engine doesn't have.
	public let code: Int
	public let message: String
	/// Whether scripts get the message with the error: PCRE's errors, which Satimage never had. Onigmo's errors
	/// are only numbers, as in Satimage.
	public let isExtension: Bool

	public init(code: Int, message: String, isExtension: Bool = false) {
		self.code = code
		self.message = message
		self.isExtension = isExtension
	}

	public var description: String { message }
}

/// A match: the range of the whole match and of each group, in UTF-16 offsets. Unmatched groups are nil.
public struct RegexMatch: Equatable, Sendable {
	public let groups: [Range<Int>?]

	public var range: Range<Int> { groups[0]! }
}

/// An engine's compiled pattern: Onigmo's or PCRE2's.
protocol RegexEngine: AnyObject {
	/// Number of capture groups, not counting the whole match.
	var groupCount: Int { get }
	/// Group numbers for each named group.
	var namedGroups: [String: [Int]] { get }
	/// The first match starting at or after `start`; the text ends at `bounds.upperBound` but starts at 0, so
	/// lookbehind and `^` see what comes before `bounds`.
	/// Errors are the engine's limits (runaway backtracking), not "no match".
	func search(_ text: UTF16Text, bounds: Range<Int>, start: Int) throws(RegexError) -> RegexMatch?
	/// Whether the search after an empty match before CR LF starts after both (PCRE's rule for finding every
	/// match: a search started between the two would find an end of line there).
	var stepsOverCRLFTogether: Bool { get }
}

/// A compiled pattern, with Onigmo (Satimage's engine) or, for `syntax "PCRE"`, PCRE2. Searches text as UTF-16, so
/// offsets are UTF-16 code units, as in `NSString`.
public final class CompiledRegex {
	public let pattern: String
	public let syntax: RegexSyntax
	public let flags: RegexFlags
	private let engine: any RegexEngine

	public init(_ pattern: String, syntax: RegexSyntax = .ruby, flags: RegexFlags = []) throws(RegexError) {
		self.pattern = pattern
		self.syntax = syntax
		self.flags = flags
		if syntax == .pcre {
			engine = try PCREEngine(pattern, flags: flags)
		} else {
			engine = try OnigmoEngine(pattern, syntax: syntax, flags: flags)
		}
	}

	/// Number of capture groups, not counting the whole match.
	public var groupCount: Int { engine.groupCount }
	/// Group numbers for each named group.
	public var namedGroups: [String: [Int]] { engine.namedGroups }

	/// The first match starting at or after `start`, looking only within `bounds`. `bounds` defaults to the whole
	/// text. (Only forward: no command searches backward with a pattern, and the code that did was run by tests alone.)
	public func firstMatch(in text: UTF16Text, from start: Int? = nil, within bounds: Range<Int>? = nil) throws(RegexError) -> RegexMatch? {
		let bounds = bounds ?? 0 ..< text.count
		return try engine.search(text, bounds: bounds, start: start ?? bounds.lowerBound)
	}

	/// Every non-overlapping match within `bounds`, left to right. After an empty match, the search
	/// continues one character later, so it always terminates. With `\K` in a lookbehind, a match can start before
	/// the search did, and the search from where it ended finds it again: one that ends no later than the last
	/// match is left out, and the search goes on one character later (it used to find it forever).
	///
	/// `searchingAtEnd` false is Satimage's loop, which the commands use: a search never starts at the end of the
	/// range, so there's no empty match there (and none in empty text). The one loop for both: the commands had a
	/// copy of their own, and the tests here ran this one.
	public func allMatches(in text: UTF16Text, within bounds: Range<Int>? = nil, searchingAtEnd: Bool = true) throws(RegexError) -> [RegexMatch] {
		let bounds = bounds ?? 0 ..< text.count
		var matches: [RegexMatch] = []
		var position = bounds.lowerBound
		while searchingAtEnd ? position <= bounds.upperBound : position < bounds.upperBound,
		      let match = try engine.search(text, bounds: bounds, start: position)
		{
			if !match.range.isEmpty, let last = matches.last, match.range.upperBound <= last.range.upperBound {
				guard position < bounds.upperBound else { break }
				position = text.index(after: position)
				continue
			}
			matches.append(match)
			if match.range.isEmpty {
				guard match.range.upperBound < bounds.upperBound else { break }
				position = text.index(after: match.range.upperBound)
				if engine.stepsOverCRLFTogether, position < bounds.upperBound, text.units[position - 1] == 0x0D, text.units[position] == 0x0A {
					position += 1
				}
			} else {
				position = match.range.upperBound
			}
		}
		return matches
	}
}
