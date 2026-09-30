import AppleEventCore
import Foundation
import Testing
@testable import TextAdditions

@MainActor
struct CaseTests {
	@Test func upper() {
		#expect(TextAdditions.transformCase("straße ǆ", CFStringUppercase) == "STRASSE Ǆ")
	}

	@Test func lowerUsesFinalSigma() {
		#expect(TextAdditions.transformCase("ΣΑΣ", CFStringLowercase) == "σας")
	}

	@Test func titleWordBoundaries() {
		#expect(TextAdditions.transformCase("o'neil hello-world foo_bar 123abc", CFStringCapitalize) == "O'neil Hello-World Foo_Bar 123Abc")
	}
}

@MainActor
struct NumberParsingTests {
	@Test(arguments: [("1.5", 1.5), (" 2.5", 2.5), ("1e3", 1000), ("0x10", 16), ("1.5abc", 1.5), ("1,5", 1.5), (".5", 0.5)])
	func reals(_ text: String, _ expected: Double) throws {
		#expect(try TextAdditions.parseReal(text) == expected)
	}

	@Test(arguments: ["abc", ""])
	func notReals(_ text: String) {
		#expect(throws: OSAXError.coercionFailed) { try TextAdditions.parseReal(text) }
	}

	@Test(arguments: [("0xa0", 160), ("42", 42), ("-7", -7), ("010", 10), ("08", 8), ("  5", 5), ("0X1F", 31), ("2147483648", 2_147_483_648)])
	func integers(_ text: String, _ expected: Int64) throws {
		#expect(try TextAdditions.parseInteger(text, base: nil) == expected)
	}

	@Test func signedHex() throws {
		#expect(try TextAdditions.parseInteger("-0x10", base: nil) == -16)
		#expect(try TextAdditions.parseInteger("+0x10", base: nil) == 16)
	}

	@Test(arguments: ["abc", "12abc", "", "1.9", "--5", "-+5", "0x"])
	func notIntegers(_ text: String) {
		#expect(throws: OSAXError.coercionFailed) { try TextAdditions.parseInteger(text, base: nil) }
	}

	@Test func bases() throws {
		#expect(try TextAdditions.parseInteger("101", base: 2) == 5)
		#expect(try TextAdditions.parseInteger("Z", base: 36) == 35)
		#expect(try TextAdditions.parseInteger("0x1f", base: 16) == 31)
		#expect(throws: OSAXError.coercionFailed) { try TextAdditions.parseInteger("19", base: 8) }
	}
}

@MainActor
struct EntityTests {
	@Test func encode() {
		#expect(TextAdditions.encodeEntities(#"'a' < "b" & c >"#) == "&apos;a&apos; &lt; &quot;b&quot; &amp; c &gt;")
	}

	@Test func resolveNamedAndNumeric() {
		#expect(TextAdditions.resolveEntities("&lt;&amp;amp;&#65;&#x41;&#x1F600;") == "<&amp;AA😀")
	}

	@Test func leavesOthersAlone() {
		#expect(TextAdditions.resolveEntities("&eacute; &AMP; &lt a & b") == "&eacute; &AMP; &lt a & b")
	}

	/// Satimage turned these into U+0000 or U+FFFD.
	@Test func malformedNumericLeftAlone() {
		#expect(TextAdditions.resolveEntities("&#;&#xZZ;&#0;&#1114112;&#12a;") == "&#;&#xZZ;&#0;&#1114112;&#12a;")
	}

	/// Each `&` used to scan to the end of the text for a `;`.
	@Test func manyAmpersandsAreQuick() {
		let text = String(repeating: "&", count: 200_000) + ";"
		let start = Date()
		#expect(TextAdditions.resolveEntities(text) == text)
		#expect(Date().timeIntervalSince(start) < 2)
		#expect(TextAdditions.resolveEntities("&" + String(repeating: "x", count: 40) + ";&lt;") == "&" + String(repeating: "x", count: 40) + ";<")
	}

	@Test func uppercaseHexReference() {
		#expect(TextAdditions.resolveEntities("&#X42;") == "B")
	}
}

@MainActor
struct URLEscapingTests {
	@Test func escapes() {
		#expect(TextAdditions.escapeURL("http://x.com/a b?q=é#f [x]", alsoEscaping: "") == "http://x.com/a%20b?q=%C3%A9%23f%20%5Bx%5D")
	}

	@Test func keepsLegalCharacters() {
		#expect(TextAdditions.escapeURL("~!*'();/?:@&=+$,", alsoEscaping: "") == "~!*'();/?:@&=+$,")
	}

	@Test func extraCharacters() {
		#expect(TextAdditions.escapeURL("a/b=c", alsoEscaping: "/=") == "a%2Fb%3Dc")
	}

	@Test func unescapes() throws {
		#expect(try TextAdditions.unescapeURL("a%20b%C3%A9%F0%9F%98%80+", keeping: "") == "a bé😀+")
	}

	@Test func keeping() throws {
		#expect(try TextAdditions.unescapeURL("a%2Fb%20c%2f", keeping: "/") == "a%2Fb c%2f")
		// A byte-order mark is a character like any other: dropped, it put the kept escapes out of step.
		#expect(try TextAdditions.unescapeURL("%EF%BB%BF%41", keeping: "A") == "\u{FEFF}%41")
		#expect(try TextAdditions.unescapeURL("%EF%BB%BFx", keeping: "") == "\u{FEFF}x")
	}

	/// "%+4" used to decode as byte 4.
	@Test(arguments: ["%zz", "100%", "%E9", "%+4", "%-4"])
	func invalid(_ text: String) {
		#expect(throws: OSAXError(-1)) { try TextAdditions.unescapeURL(text, keeping: "") }
	}
}

@MainActor
struct HashAndTransformTests {
	/// Values recorded from SatimageOSAX.
	@Test(arguments: [("", 0), ("abc", 12_885_873), ("ABC", 10_566_673), ("é", 794_120), ("e\u{301}", 794_120), ("ﬁ", 792_085), ("😀", 4_969_531)])
	func hash(_ text: String, _ expected: Int) {
		#expect(TextAdditions.hash(text) == expected)
	}

	@Test func transform() throws {
		#expect(try TextAdditions.transformUnicode("éç", "NFD; [:Nonspacing Mark:] Remove", inverse: false) == "ec")
		#expect(try TextAdditions.transformUnicode("&#x65;", "Any-Hex/XML", inverse: true) == "e")
	}

	@Test func caseTransformInverse() throws {
		#expect(try TextAdditions.transformUnicode("ABC", "Any-Upper", inverse: true) == "abc")
	}

	@Test func unknownTransform() {
		#expect(throws: OSAXError(-1)) { try TextAdditions.transformUnicode("a", "Nope-Nope", inverse: false) }
	}
}
