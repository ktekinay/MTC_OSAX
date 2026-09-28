import AppleEventCore
import Foundation
import Testing
import TextMatching
@testable import TextAdditions

/// Expands `template` for the first match of `pattern` in `string`.
private func expand(_ template: String, pattern: String, in string: String, dollarReferences: Bool = false) throws -> String {
	let text = UTF16Text(string)
	let regex = try CompiledRegex(pattern)
	let match = try #require(try regex.firstMatch(in: text))
	return try Template(template, dollarReferences: dollarReferences)
		.expand(TextMatch(groups: match.groups), in: text, groupCount: regex.groupCount, namedGroups: regex.namedGroups)
}

struct TemplateTests {
	@Test func numberedGroups() throws {
		#expect(try expand(#"[\0|\1|\2]"#, pattern: "(a)(b)", in: "xab") == "[ab|a|b]")
	}

	@Test func onlyOneDigit() throws {
		#expect(try expand(#"\10"#, pattern: "(a)", in: "a") == "a0")
	}

	@Test func unmatchedGroupIsEmpty() throws {
		#expect(try expand(#"[\1][\2]"#, pattern: "(a)|(b)", in: "b") == "[][b]")
	}

	@Test func escapes() throws {
		#expect(try expand(#"\t\n\r\\"#, pattern: "a", in: "a") == "\t\n\r\\")
	}

	@Test func unicodeEscape() throws {
		#expect(try expand(#"A😀"#, pattern: "a", in: "a") == "A😀")
	}

	@Test(arguments: [#"\q"#, #"\$"#, #"\x41"#, #"\u41"#, #"\"#, #"\k<1"#, #"\g<1>"#, #"\u+FFF"#, #"\u-FFF"#])
	func invalidEscapes(_ template: String) {
		#expect(throws: Template.invalidBackreference) {
			try Template(template)
		}
	}

	@Test func groupNumberTooBig() {
		#expect(throws: Template.tooBigBackreference) {
			try expand(#"\2"#, pattern: "(a)", in: "a")
		}
	}

	/// Satimage inserted the whole match whatever the name; MTC_OSAX inserts the group.
	@Test func kReferencesGroups() throws {
		#expect(try expand(#"[\k<n>][\k<1>][\k<0>]"#, pattern: "a(?<n>b)", in: "ab") == "[b][b][ab]")
	}

	@Test func kUnknownName() {
		#expect(throws: OSAXError(-217)) {
			try expand(#"\k<nope>"#, pattern: "(a)", in: "a")
		}
	}

	@Test func dollarIsLiteralByDefault() throws {
		#expect(try expand("[$1|$0|$$|${1}]", pattern: "(a)", in: "a") == "[$1|$0|$$|${1}]")
	}

	@Test func dollarReferences() throws {
		#expect(try expand("[$0|$1|$$|${n}]", pattern: "(?<n>a)b", in: "ab", dollarReferences: true) == "[ab|a|$|a]")
	}

	@Test func dollarBracesWithNumber() throws {
		let pattern = "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)"
		#expect(try expand("${10}|${1}|$10", pattern: pattern, in: "abcdefghij", dollarReferences: true) == "j|a|a0")
	}

	@Test func dollarFollowedByOtherIsLiteral() throws {
		#expect(try expand("$x $ ${", pattern: "a", in: "a", dollarReferences: true) == "$x $ ${")
	}

	@Test func backslashFormsStillWorkWithDollarReferences() throws {
		#expect(try expand(#"\1-$1"#, pattern: "(a)", in: "a", dollarReferences: true) == "a-a")
	}

	/// A sign isn't a group number (these used to index before the groups and crash); it's an unknown name.
	@Test(arguments: [#"\k<-1>"#, #"\k<+1>"#, "${-1}", "${+1}"])
	func signedGroupNumbers(_ template: String) {
		#expect(throws: OSAXError(-217)) {
			try expand(template, pattern: "(a)", in: "a", dollarReferences: true)
		}
	}

	@Test func negativeGroupHasNoRange() {
		#expect(TextMatch(groups: [0 ..< 1, 0 ..< 1]).range(ofGroup: -1) == nil)
	}

	@Test func unknownNamedGroup() {
		#expect(throws: OSAXError(-217)) {
			try expand("${nope}", pattern: "(a)", in: "a", dollarReferences: true)
		}
	}
}
