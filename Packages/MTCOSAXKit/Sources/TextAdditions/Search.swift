import AppleEventCore
import Foundation
import TextMatching

/// Error -2763 ("No result was returned"), which Satimage returns when `find text` finds nothing.
/// Scripts rely on it: `try … on error` is their "not found" branch.
let notFoundError = OSAXError(-2763)

/// Satimage's error for an unknown `regexpflag` or `syntax` name, and for mismatched pattern/replacement lists.
let invalidOptionError = OSAXError(-1)

/// A match: the ranges of the whole match and each group, in UTF-16 offsets. Literal matches have no groups.
struct TextMatch {
	let groups: [Range<Int>?]

	var range: Range<Int> { groups[0]! }

	func range(ofGroup number: Int) -> Range<Int>? {
		groups.indices.contains(number) ? groups[number] : nil
	}

	func text(ofGroup number: Int, in text: UTF16Text) -> String {
		range(ofGroup: number).map { text[$0] } ?? ""
	}
}

/// The matching parameters shared by `find text`, `change` and `splittext`.
struct SearchOptions {
	var regexp = false
	var caseSensitive = true
	var diacriticSensitive = true
	var wholeWord = false
	var backward = false
	var allOccurrences = false
	var stringResult = false
	var flags: RegexFlags = []
	var syntax: RegexSyntax = .ruby
	var start: Int?
	var length: Int?
	var dollarReferences = false

	/// Reads the parameters a command has. `options` shortcut letters override the individual parameters.
	@MainActor
	init(_ request: AppleEventRequest, context: TextContext, readsBackward: Bool = false) throws {
		syntax = context.regexSyntaxDefault()
		regexp = try request.parameter("UsGR", default: false)
		caseSensitive = try request.parameter("CaSe", default: true)
		diacriticSensitive = try request.parameter("DiSe", default: true)
		wholeWord = try request.parameter("WhWo", default: false)
		allOccurrences = try request.parameter("WaAl", default: false)
		stringResult = try request.parameter("WaMr", default: false)
		if readsBackward {
			backward = try request.parameter("back", default: false)
		}
		start = try request.parameter("strt", as: Int.self)
		length = try request.parameter("for ", as: Int.self)

		if let names = try request.parameter("Flag", as: [String].self) {
			guard let parsed = RegexFlags(names: names) else {
				throw invalidOptionError
			}
			flags = parsed
		}
		if let name = try request.parameter("synt", as: String.self) {
			guard let parsed = RegexSyntax(name: name) else {
				throw invalidOptionError
			}
			syntax = parsed
		}
		if let shortcuts = try request.parameter("Opti", as: String.self) {
			for letter in shortcuts {
				switch letter {
				case "a": allOccurrences = true
				case "r": regexp = true
				case "s": stringResult = true
				case "c": caseSensitive = false
				case "d": diacriticSensitive = false
				default: break // Satimage ignores unknown letters.
				}
			}
		}

		// MTC_OSAX extension: an explicit parameter wins, then the flag, then the app-wide default.
		if let explicit = try request.parameter(dollarReferencesKeyword, as: Bool.self) {
			dollarReferences = explicit
		} else {
			dollarReferences = flags.contains(.dollarReferences) || context.dollarReferencesDefault()
		}
	}

	/// The part of the text searched: `starting at` (clamped at 0) for `for` characters.
	/// Nil if `starting at` is past the end.
	func bounds(in text: UTF16Text) -> Range<Int>? {
		let lower = max(start ?? 0, 0)
		guard lower <= text.count else {
			return nil
		}
		let upper = length.map { min(lower + max($0, 0), text.count) } ?? text.count
		return lower ..< upper
	}
}

extension OSAXError {
	/// A pattern's error: Onigmo's number alone, as in Satimage; PCRE's with its message.
	init(_ error: RegexError) {
		self.init(error.code, error.isExtension ? error.message : nil)
	}
}

/// The `dollar references` parameter MTC_OSAX adds to `find text`, `change` and `filter text`.
let dollarReferencesKeyword = "DlRf"

/// Finds a pattern, literally or as a regex, following Satimage's rules.
struct TextSearcher {
	let options: SearchOptions
	private let pattern: String
	private let regex: CompiledRegex?

	@MainActor
	init(pattern: String, options: SearchOptions, context: TextContext) throws {
		self.pattern = pattern
		self.options = options
		if options.regexp {
			var flags = options.flags
			if !options.caseSensitive {
				flags.insert(.ignoreCase)
			}
			do {
				regex = try context.regexCache.regex(pattern, syntax: options.syntax, flags: flags)
			} catch {
				throw OSAXError(error)
			}
		} else {
			regex = nil
		}
	}

	var groupCount: Int { regex?.groupCount ?? 0 }
	var namedGroups: [String: [Int]] { regex?.namedGroups ?? [:] }

	/// The first match (the last one for a literal `backward` search). Errors are the regex engine's limits.
	func firstMatch(in text: UTF16Text) throws -> TextMatch? {
		guard let bounds = options.bounds(in: text) else {
			return nil
		}
		if let regex {
			// Satimage never starts a search at the very end of the text, so an empty pattern finds nothing in "".
			guard bounds.lowerBound < bounds.upperBound else {
				return nil
			}
			do {
				return try regex.firstMatch(in: text, from: bounds.lowerBound, within: bounds).map { TextMatch(groups: $0.groups) }
			} catch {
				throw OSAXError(error)
			}
		}
		if options.backward {
			// Backward: searches the text before `starting at` (the whole text if not given).
			let upper = options.start.map { min(max($0, 0), text.count) } ?? text.count
			return literalMatch(in: text, string: Self.searchString(text), within: 0 ..< upper, backward: true)
		}
		return literalMatch(in: text, string: Self.searchString(text), within: bounds, backward: false)
	}

	/// Every non-overlapping match, left to right. (Matches can still overlap when a match starts before the search
	/// did, with `\K` in a lookbehind.)
	func allMatches(in text: UTF16Text) throws -> [TextMatch] {
		guard let bounds = options.bounds(in: text) else {
			return []
		}
		// Satimage's loop: a search never starts at the end of the searched range. After an empty match
		// the next search starts one character later.
		if let regex {
			do {
				return try regex.allMatches(in: text, within: bounds, searchingAtEnd: false).map { TextMatch(groups: $0.groups) }
			} catch {
				throw OSAXError(error)
			}
		}
		var matches: [TextMatch] = []
		var position = bounds.lowerBound
		let string = Self.searchString(text)
		while position < bounds.upperBound, let match = literalMatch(in: text, string: string, within: position ..< bounds.upperBound, backward: false) {
			matches.append(match)
			position = match.range.isEmpty ? text.index(after: match.range.upperBound) : match.range.upperBound
		}
		return matches
	}

	/// The text for `literalMatch`, made once per search: copying it for every match made a search of all
	/// occurrences take time proportional to the text's length times the number of matches (8 seconds for 1,250
	/// matches in 100 KB). Made from the UTF-16 units, so positions are found directly.
	private static func searchString(_ text: UTF16Text) -> NSString {
		text.units.withUnsafeBufferPointer { units in
			guard let characters = units.baseAddress else {
				return ""
			}
			return NSString(characters: characters, length: units.count)
		}
	}

	/// `NSString` search: canonically equivalent text matches (precomposed and decomposed é), with optional
	/// case and diacritic folding. `whole word` skips matches next to a letter, digit or underscore.
	private func literalMatch(in text: UTF16Text, string: NSString, within bounds: Range<Int>, backward: Bool) -> TextMatch? {
		guard !pattern.isEmpty, !bounds.isEmpty else {
			return nil
		}
		var compareOptions: NSString.CompareOptions = []
		if !options.caseSensitive { compareOptions.insert(.caseInsensitive) }
		if !options.diacriticSensitive { compareOptions.insert(.diacriticInsensitive) }
		if backward { compareOptions.insert(.backwards) }

		var searchRange = NSRange(location: bounds.lowerBound, length: bounds.count)
		while searchRange.length > 0 {
			let found = string.range(of: pattern, options: compareOptions, range: searchRange)
			guard found.location != NSNotFound else {
				return nil
			}
			let range = found.location ..< found.location + found.length
			if !options.wholeWord || isWholeWord(range, in: text) {
				return TextMatch(groups: [range])
			}
			// Keep looking past this candidate.
			if backward {
				searchRange.length = found.location + found.length - 1 - searchRange.location
			} else {
				let next = found.location + 1
				searchRange = NSRange(location: next, length: bounds.upperBound - next)
			}
		}
		return nil
	}

	private func isWholeWord(_ range: Range<Int>, in text: UTF16Text) -> Bool {
		func isWordUnit(_ offset: Int) -> Bool {
			guard offset >= 0, offset < text.count, let scalar = Unicode.Scalar(text.units[offset]) else {
				return false
			}
			return scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
		}
		return !isWordUnit(range.lowerBound - 1) && !isWordUnit(range.upperBound)
	}
}

/// The text a command works on: a string, each string of a list, or a file's text.
enum TextInput {
	case single(String)
	case list([String])
	case file(URL)

	/// Reads the `in` parameter (or another text parameter). Lists give one result per item.
	/// Records and other values that aren't text are reported as a missing parameter, as Satimage does.
	init(_ request: AppleEventRequest, keyword: String) throws {
		guard let descriptor = request.descriptor(for: keyword) else {
			throw OSAXError.missingParameter
		}
		if descriptor.descriptorType == typeAEList {
			self = .list(try [String](appleEventDescriptor: descriptor))
			return
		}
		if Self.isFile(descriptor) {
			self = .file(try URL(appleEventDescriptor: descriptor))
			return
		}
		guard let string = try? String(appleEventDescriptor: descriptor) else {
			throw OSAXError.missingParameter
		}
		self = .single(string)
	}

	static func isFile(_ descriptor: NSAppleEventDescriptor) -> Bool {
		["alis", "furl", "fsrf", "bmrk", "fss "].contains(descriptor.descriptorType.fourCharString)
	}

	/// Applies `transform` to each string, returning a single result or a list of results.
	func map(_ transform: (String) throws -> NSAppleEventDescriptor?) throws -> NSAppleEventDescriptor? {
		switch self {
		case let .single(string):
			return try transform(string)
		case let .list(strings):
			return try strings.map { try transform($0) ?? .missingValue }.appleEventDescriptor
		case let .file(url):
			return try transform(FileText.read(url).text)
		}
	}
}
