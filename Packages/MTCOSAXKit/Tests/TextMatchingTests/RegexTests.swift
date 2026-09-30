import Foundation
import Testing
@testable import TextMatching

private func first(_ pattern: String, in string: String, syntax: RegexSyntax = .ruby, flags: RegexFlags = []) throws -> String? {
	let text = UTF16Text(string)
	return try CompiledRegex(pattern, syntax: syntax, flags: flags).firstMatch(in: text).map { text[$0.range] }
}

/// The behaviors that identified Satimage's engine as Onigmo with Ruby syntax (see Implemented/PLAN-TextAdditions.md).
@MainActor
struct SatimageFingerprintTests {
	@Test func hIsHexDigit() throws {
		#expect(try first(#"\h+"#, in: "zz 1aF zz") == "1aF")
	}

	@Test func caretMatchesAtEveryLine() throws {
		#expect(try first("^b", in: "a\nb") == "b")
	}

	@Test func conditionals() throws {
		#expect(try first("(a)?(?(1)b|c)", in: "xc") == "c")
	}

	@Test func classIntersection() throws {
		#expect(try first("[a-z&&[^aeiou]]+", in: "aeibcd") == "bcd")
	}

	@Test func inlineMMakesDotMatchNewline() throws {
		#expect(try first("(?m)a.b", in: "a\nb") == "a\nb")
	}

	@Test func grepSyntaxGroups() throws {
		#expect(try first(#"\(ab\)c"#, in: "xabc", syntax: .grep) == "abc")
	}
}

@MainActor
struct RegexTests {
	@Test func offsetsAreUTF16Units() throws {
		for string in ["😀b", "e\u{301}b", "日本b", "éb"] {
			let text = UTF16Text(string)
			let match = try #require(try CompiledRegex("b").firstMatch(in: text))
			#expect(match.range == (text.count - 1) ..< text.count, "\(string)")
		}
	}

	@Test func groups() throws {
		let text = UTF16Text("2007-12-24")
		let match = try #require(try CompiledRegex(#"(\d+)-(\d+)-(x)?"#).firstMatch(in: text))
		#expect(match.groups.count == 4)
		#expect(match.groups[1] == 0 ..< 4)
		#expect(match.groups[2] == 5 ..< 7)
		#expect(match.groups[3] == nil)
	}

	@Test func namedGroups() throws {
		let regex = try CompiledRegex(#"(?<year>\d+)-(?<month>\d+)"#)
		#expect(regex.groupCount == 2)
		#expect(regex.namedGroups == ["year": [1], "month": [2]])
	}

	@Test func allMatches() throws {
		let text = UTF16Text("a 2007-12-24 b")
		let matches = try CompiledRegex("[0-9]+").allMatches(in: text)
		#expect(matches.map { text[$0.range] } == ["2007", "12", "24"])
	}

	/// With `\K` in a lookbehind a match starts before the search did, and the search from where it ended found it
	/// again, forever: the app hung, taking more and more memory.
	@Test func allMatchesWithKeepInLookbehind() throws {
		let text = UTF16Text("abc")
		#expect(try CompiledRegex(#"(?<=\K.)"#).allMatches(in: text).map(\.range) == [0 ..< 1, 1 ..< 2, 2 ..< 3])
		// Matches can still overlap.
		#expect(try CompiledRegex(#"(?<=\K.)b"#).allMatches(in: UTF16Text("abb")).map(\.range) == [0 ..< 2, 1 ..< 3])
	}

	@Test func allMatchesAdvancesPastEmptyMatches() throws {
		let text = UTF16Text("a😀b")
		let matches = try CompiledRegex("x*").allMatches(in: text)
		// One empty match before each character and one at the end; the emoji counts once.
		#expect(matches.map(\.range) == [0 ..< 0, 1 ..< 1, 3 ..< 3, 4 ..< 4])
	}

	@Test func searchFromStart() throws {
		let text = UTF16Text("ab ab")
		let match = try CompiledRegex("ab").firstMatch(in: text, from: 1)
		#expect(match?.range == 3 ..< 5)
	}

	@Test func backwardSearch() throws {
		let text = UTF16Text("ab ab")
		let match = try CompiledRegex("ab").firstMatch(in: text, backward: true)
		#expect(match?.range == 3 ..< 5)
	}

	@Test func boundsLimitTheMatch() throws {
		let text = UTF16Text("abcdef")
		#expect(try CompiledRegex("def").firstMatch(in: text, within: 0 ..< 5) == nil)
		#expect(try CompiledRegex("cd").firstMatch(in: text, within: 1 ..< 5)?.range == 2 ..< 4)
	}

	@Test func noMatch() throws {
		#expect(try first("z", in: "abc") == nil)
	}

	@Test func invalidPatternThrows() {
		#expect(throws: RegexError.self) {
			try CompiledRegex("(unclosed")
		}
	}

	/// Onigmo quotes part of the pattern from its buffer, which used to be read after the buffer's scope had ended.
	@Test func messageQuotingThePattern() {
		let error = #expect(throws: RegexError.self) { try CompiledRegex(#"(?<x>a)\k<nope>"#) }
		#expect(error?.message.contains("nope") == true)
	}

	@Test func invalidPatternMessage() {
		do {
			_ = try CompiledRegex("a{2,1}")
			Issue.record("expected an error")
		} catch {
			#expect(error.code < 0)
			#expect(!error.message.isEmpty)
		}
	}
}

@MainActor
struct RegexFlagTests {
	@Test func parsesSatimageSpellings() {
		#expect(RegexFlags(names: ["IGNORECASE", "find longest", "FIND_NOT_EMPTY", "Newline In Negative CC"])
			== [.ignoreCase, .findLongest, .findNotEmpty, .newlineInNegativeCC])
	}

	@Test func rejectsUnknownNames() {
		#expect(RegexFlags(names: ["IGNORECASE", "NOPE"]) == nil)
	}

	@Test func dollarReferencesFlag() {
		#expect(RegexFlags(names: ["DOLLAR REFERENCES"]) == [.dollarReferences])
	}

	@Test func ignoreCase() throws {
		#expect(try first("abc", in: "xABC", flags: .ignoreCase) == "ABC")
	}

	@Test func multilineDotMatchesNewline() throws {
		#expect(try first("a.b", in: "a\nb") == nil)
		#expect(try first("a.b", in: "a\nb", flags: .multiline) == "a\nb")
	}

	@Test func singlelineAnchorsToText() throws {
		#expect(try first("^b", in: "a\nb", flags: .singleline) == nil)
	}

	@Test func extendIgnoresSpaces() throws {
		#expect(try first("a b c", in: "abc", flags: .extend) == "abc")
	}

	@Test func findLongest() throws {
		#expect(try first("a|ab", in: "ab") == "a")
		#expect(try first("a|ab", in: "ab", flags: .findLongest) == "ab")
	}

	@Test func findNotEmpty() throws {
		#expect(try first("x*", in: "ab") == "")
		#expect(try first("x*", in: "ab", flags: .findNotEmpty) == nil)
	}

	@Test func notBOL() throws {
		#expect(try first(#"\Aa"#, in: "ab") == "a")
		#expect(try first("^a", in: "ab", flags: .notBOL) == nil)
	}

	@Test func dontCaptureGroup() throws {
		let text = UTF16Text("ab")
		let match = try CompiledRegex("(a)(b)", flags: .dontCaptureGroup).firstMatch(in: text)
		#expect(match?.groups.count == 1)
	}

	@Test func negatedClassesExcludeLineFeedAndReturn() throws {
		// Onigmo's syntaxes (PCRE keeps its own rule: see PCRERegexTests).
		for syntax in RegexSyntax.allCases where ![.posixBasic, .grep, .emacs, .pcre].contains(syntax) {
			#expect(try first("a[^x]b", in: "a\nb", syntax: syntax) == nil, "\(syntax)")
			#expect(try first("a[^x]b", in: "a\rb", syntax: syntax) == nil, "\(syntax)")
		}
		#expect(try first("a[^x]b", in: "a\u{85}b") == "a\u{85}b")
	}

	@Test func newlineInNegativeCharacterClass() throws {
		#expect(try first("a[^x]b", in: "a\rb", flags: .newlineInNegativeCC) == "a\rb")
		#expect(try first("a[^x]b", in: "a\nb", flags: .newlineInNegativeCC) == "a\nb")
	}

	@Test(arguments: ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"])
	func satimageLineEnds(_ lineEnd: String) throws {
		#expect(try first("^b", in: "a\(lineEnd)b") == "b")
		#expect(try first("a$", in: "a\(lineEnd)b") == "a")
		#expect(try first("a.b", in: "a\(lineEnd)b") == nil)
	}

	@Test(arguments: ["\u{0B}", "\u{0C}"])
	func verticalTabAndFormFeedAreNotLineEnds(_ character: String) throws {
		#expect(try first("^b", in: "a\(character)b") == nil)
		#expect(try first("a.b", in: "a\(character)b") == "a\(character)b")
	}

	@Test func crlfIsTwoLineEnds() throws {
		let text = UTF16Text("a\r\nb")
		#expect(try CompiledRegex("$").allMatches(in: text).map(\.range.lowerBound) == [1, 2, 4])
	}

	/// Satimage's build ended (?x) comments at a return and at the escapes \n and \r, not only at a linefeed.
	@Test func extendedCommentEndings() throws {
		#expect(try first(#"(?x)a # c\nb"#, in: "ab") == "ab")
		#expect(try first(#"(?x)a # c\rb"#, in: "ab") == "ab")
		#expect(try first("(?x)a # c\rb", in: "ab") == "ab")
		#expect(try first("(?x)a # c\nb", in: "ab") == "ab")
		#expect(try first(#"(?x)a # c\tb"#, in: "ab") == "a")
		#expect(try first("(?x)a # c\u{2028}b", in: "ab") == "a")
	}

	@Test func unnamedGroupsAreNumberedWithNamedOnes() throws {
		let regex = try CompiledRegex("(?<n>a)(b)")
		#expect(regex.groupCount == 2)
		#expect(regex.namedGroups == ["n": [1]])
	}

	@Test func syntaxNames() {
		#expect(RegexSyntax(name: "ruby") == .ruby)
		#expect(RegexSyntax(name: "POSIX EXTENDED") == .posixExtended)
		#expect(RegexSyntax(name: "gnu_regex") == .gnuRegex)
		#expect(RegexSyntax(name: "pcre") == .pcre)
		#expect(RegexSyntax(name: "NOT_A_SYNTAX") == nil)
	}
}

@MainActor
struct RegexCacheTests {
	@Test func reusesCompiledPatterns() throws {
		let cache = RegexCache()
		let a = try cache.regex("a+")
		let b = try cache.regex("a+")
		#expect(a === b)
		#expect(try cache.regex("a+", flags: .ignoreCase) !== a)
	}

	@Test func evictsOldest() throws {
		let cache = RegexCache(capacity: 2)
		let first = try cache.regex("1")
		_ = try cache.regex("2")
		_ = try cache.regex("3")
		#expect(cache.count == 2)
		#expect(try cache.regex("1") !== first)
	}
}

/// Runaway backtracking is an error, not "no match" or a crash.
@MainActor
struct RegexLimitTests {
	/// Onigmo's backtracking stack used to be unlimited.
	@Test func onigmoStackLimit() throws {
		// Fails only after backtracking through every character (with nothing Onigmo can rule out beforehand).
		let pattern = try CompiledRegex(#"\A(?:a|b)*(?<!b)\z"#)
		let error = #expect(throws: RegexError.self) { try pattern.firstMatch(in: UTF16Text(String(repeating: "ab", count: 3_000_000))) }
		#expect(error?.code == -15)
		#expect(try pattern.firstMatch(in: UTF16Text(String(repeating: "ab", count: 100_000))) == nil)
		#expect(try CompiledRegex("(?:a|b)*").firstMatch(in: UTF16Text(String(repeating: "a", count: 100_000)))?.range == 0 ..< 100_000)
	}

	/// PCRE2's limits used to be reported as no match.
	@Test func pcreMatchLimit() throws {
		let text = UTF16Text(String(repeating: "a", count: 40) + "b")
		let error = #expect(throws: RegexError.self) { try CompiledRegex("(a+)+$", syntax: .pcre).firstMatch(in: text) }
		#expect(error?.code == -3047)
		#expect(error?.message.contains("limit") == true)
	}
}

/// Text from a script can hold a lone surrogate. Onigmo's UTF-16 read the pair's second half anyway, past the end
/// of the text (AddressSanitizer caught it in a case-insensitive search).
@MainActor
struct LoneSurrogateTests {
	@Test(arguments: [[UInt16(0xD800)], [0xD800, 0x61], [0x61, 0xDC00], [0xD83D, 0xDE00, 0xD800]])
	func caseInsensitiveSearch(_ units: [UInt16]) throws {
		let text = UTF16Text(units: units)
		#expect(try CompiledRegex("b", flags: .ignoreCase).firstMatch(in: text) == nil)
		#expect(try CompiledRegex("x+", flags: .ignoreCase).allMatches(in: text).isEmpty)
	}

	@Test func loneSurrogatesAreOneUnit() throws {
		let text = UTF16Text(units: [0x61, 0xD800, 0x62])
		#expect(try CompiledRegex("a.b").firstMatch(in: text)?.range == 0 ..< 3)
		#expect(try CompiledRegex("A", flags: .ignoreCase).firstMatch(in: UTF16Text(units: [0xD800, 0x61]))?.range == 1 ..< 2)
	}
}

/// A text character that folds to more than is left of the pattern's text (ß is ss) made Onigmo read past the
/// pattern (AddressSanitizer caught it).
@MainActor
struct CaseFoldingTests {
	@Test func foldsLongerThanThePattern() throws {
		#expect(try CompiledRegex("s", flags: .ignoreCase).firstMatch(in: UTF16Text("ß")) == nil)
		#expect(try CompiledRegex("xs", flags: .ignoreCase).firstMatch(in: UTF16Text("xßy")) == nil)
		#expect(try CompiledRegex("ss", flags: .ignoreCase).firstMatch(in: UTF16Text("aßb"))?.range == 1 ..< 2)
		// The find-text fixture fold-dotless-i: İ folds to i and a combining dot.
		let dotted = try CompiledRegex("i", flags: .ignoreCase).allMatches(in: UTF16Text("I ı İ")).map(\.range)
		#expect(dotted == [0 ..< 1])
	}
}

/// Onigmo peeked at the character after the end of the text when a greedy repeat of anything was followed by a
/// literal, as in the find-script-ldjson fixture (AddressSanitizer caught it).
@MainActor
struct PeekAtEndTests {
	@Test func greedyRepeatBeforeALiteral() throws {
		let regex = try CompiledRegex(#"<s>([\s\S]*)</s>"#)
		#expect(try regex.firstMatch(in: UTF16Text("<s>a</s> b"))?.range == 0 ..< 8)
		#expect(try regex.firstMatch(in: UTF16Text("<s>a b")) == nil)
	}
}
