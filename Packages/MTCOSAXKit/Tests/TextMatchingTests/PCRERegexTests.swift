import Foundation
import Testing
@testable import TextMatching

private func pcre(_ pattern: String, _ flags: RegexFlags = []) throws -> CompiledRegex {
	try CompiledRegex(pattern, syntax: .pcre, flags: flags)
}

private func matches(_ pattern: String, in string: String, _ flags: RegexFlags = []) throws -> [String] {
	let text = UTF16Text(string)
	return try pcre(pattern, flags).allMatches(in: text).map { text[$0.range] }
}

@MainActor
struct PCRERegexTests {
	@Test func utf16Offsets() throws {
		let text = UTF16Text("😀 cafe\u{301} x")
		let match = try #require(try pcre(#"\w+"#).firstMatch(in: text))
		// The emoji is two code units; "cafe" plus the combining accent (a mark, so \w with Unicode) is five.
		#expect(match.range == 3 ..< 8)
	}

	@Test func groupsAndNames() throws {
		let regex = try pcre(#"(?<year>\d+)-(\d+)(x)?"#)
		#expect(regex.groupCount == 3)
		#expect(regex.namedGroups == ["year": [1]])
		let match = try #require(try regex.firstMatch(in: UTF16Text("on 2026-09")))
		#expect(match.groups == [3 ..< 10, 3 ..< 7, 8 ..< 10, nil])
		// Duplicate names, with (?J).
		#expect(try pcre(#"(?J)(?<n>a)|(?<n>b)"#).namedGroups == ["n": [1, 2]])
	}

	@Test func anchorsMatchEveryLineByDefault() throws {
		let text = "one\ntwo\r\nthree\u{2028}four"
		#expect(try matches("^\\w+$", in: text) == ["one", "two", "three", "four"])
		#expect(try matches("(?-m)^\\w+", in: text) == ["one"])
		#expect(try matches("^\\w+", in: text, .singleline) == ["one"])
		#expect(try matches(#"\w+\z"#, in: text) == ["four"])
		// SINGLELINE wins over MULTILINE.
		#expect(try matches("^\\w+", in: text, [.singleline, .multiline]) == ["one"])
	}

	@Test func flags() throws {
		#expect(try matches("é", in: "É é", .ignoreCase) == ["É", "é"])
		#expect(try matches("a b # comment", in: "ab", .extend) == ["ab"])
		#expect(try matches("a.b", in: "a\nb") == [])
		#expect(try matches("a.b", in: "a\nb", .dotAll) == ["a\nb"])
		#expect(try matches("(?s)a.b", in: "a\nb") == ["a\nb"])
		#expect(try pcre("(a)(b)", .dontCaptureGroup).groupCount == 0)
		#expect(try matches("x*", in: "ab", .findNotEmpty) == [])
		#expect(try matches("^a", in: "ab", .notBOL) == [])
		for flag in [RegexFlags.findLongest, .negateSingleline, .newlineInNegativeCC] {
			let error = #expect(throws: RegexError.self) { try pcre("a", flag) }
			#expect(error?.code == -1)
		}
		// DOTALL is PCRE's name; Onigmo rejects it.
		#expect((try? CompiledRegex("a", flags: .dotAll)) == nil)
	}

	@Test func pcreFeatures() throws {
		#expect(try matches(#"\h+"#, in: "a \t b") == [" \t "])
		#expect(try matches(#"(?<=\$)\d+"#, in: "$12 34") == ["12"])
		#expect(try matches(#"a++b"#, in: "aaab") == ["aaab"])
		#expect(try matches(#"foo\Kbar"#, in: "foobar") == ["bar"])
		#expect(try matches(#"\((?:[^()]|(?R))*\)"#, in: "x(a(b)c)y") == ["(a(b)c)"])
		// Negated classes match line ends (Onigmo's Satimage build doesn't).
		#expect(try matches("a[^x]b", in: "a\nb") == ["a\nb"])
	}

	@Test func errors() throws {
		let error = #expect(throws: RegexError.self) { try pcre("(unclosed") }
		if let error {
			#expect(error.code == -3114)
			#expect(error.isExtension)
			#expect(error.message.contains("missing closing parenthesis"))
			#expect(error.message.contains("offset 9"))
		}
	}

	@Test func boundsAndBackward() throws {
		let text = UTF16Text("abcabc")
		let regex = try pcre("abc")
		#expect(try regex.firstMatch(in: text, from: 1)?.range == 3 ..< 6)
		#expect(try regex.firstMatch(in: text, within: 0 ..< 5)?.range == 0 ..< 3)
		#expect(try regex.firstMatch(in: text, from: 1, within: 1 ..< 5) == nil)
		// Lookbehind sees text before the bounds.
		#expect(try pcre("(?<=a)b").firstMatch(in: text, within: 1 ..< 6)?.range == 1 ..< 2)
		#expect(try pcre("x*").allMatches(in: UTF16Text("")).count == 1)
		// The commands' loop never searches at the end of the range.
		#expect(try pcre("x*").allMatches(in: UTF16Text(""), searchingAtEnd: false).isEmpty)
		#expect(try pcre("x*").allMatches(in: UTF16Text("ax"), searchingAtEnd: false).map(\.range) == [0 ..< 0, 1 ..< 2])
		#expect(try pcre("x*").allMatches(in: UTF16Text("ax")).map(\.range) == [0 ..< 0, 1 ..< 2, 2 ..< 2])
	}

	@Test func invalidUTF16IsSearched() throws {
		let text = UTF16Text(units: [0x61, 0xD800, 0x62])
		#expect(!text.isValidUTF16)
		#expect(try pcre("b").firstMatch(in: text)?.range == 2 ..< 3)
		// The same pattern, both ways round, and the bounds or start cutting a pair.
		let regex = try pcre("b")
		let pair = UTF16Text("a😀b")
		#expect(pair.isValidUTF16 && pair.splitsPair(at: 2) && !pair.splitsPair(at: 1) && !pair.splitsPair(at: 3))
		#expect(try regex.firstMatch(in: pair)?.range == 3 ..< 4)
		#expect(try regex.firstMatch(in: pair, within: 0 ..< 2) == nil)
		#expect(try regex.firstMatch(in: pair, from: 2)?.range == 3 ..< 4)
		#expect(try regex.firstMatch(in: text)?.range == 2 ..< 3)
	}

	/// With PCRE2_MATCH_INVALID_UTF, every call checked the text to its end, and there's a call per match: a search
	/// of a large text took time that grew with the square of its length (a minute for 400,000 units).
	@Test func manyMatchesInALargeTextAreQuick() throws {
		let text = UTF16Text(String(repeating: "xxxxa", count: 80_000))
		let start = Date()
		#expect(try pcre("a").allMatches(in: text).count == 80_000)
		#expect(Date().timeIntervalSince(start) < 5)
	}

	@Test func cacheKeepsEnginesApart() throws {
		let cache = RegexCache()
		let text = UTF16Text("a\nb")
		let onigmo = try cache.regex("a[^x]b")
		let pcre = try cache.regex("a[^x]b", syntax: .pcre)
		#expect(try onigmo.firstMatch(in: text) == nil)
		#expect(try pcre.firstMatch(in: text) != nil)
		#expect(cache.count == 2)
	}
}
