import AppleEventCore
import Foundation
import Testing
import TestSupport
import TextMatching
@testable import TextAdditions
import Settings

/// Sends a command with the app-wide `RegexSyntax` setting as given.
private func send(_ code: String, _ parameters: [String: any AppleEventEncodable], syntaxDefault: RegexSyntax = .ruby) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(TextAdditions.commands(context: TextContext(dollarReferencesDefault: { false }, regexSyntaxDefault: { syntaxDefault })))
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return dispatcher.dispatch(event)
}

/// `syntax "PCRE"` (an MTC_OSAX extension) in each regex command, and the `RegexSyntax` setting.
struct PCRECommandTests {
	/// `\h` is PCRE's horizontal space; Onigmo's Ruby syntax reads it as a hex digit.
	private let spaces = "x \t y"

	@Test func findText() throws {
		let parameters: [String: any AppleEventEncodable] = ["----": #"\h+"#, "$in ": spaces, "UsGR": true, "WaMr": true, "synt": "PCRE"]
		#expect(send("SATIFINd", parameters).result?.stringValue == " \t ")
		// ^ and $ at every line by default; SINGLELINE anchors to the whole text.
		let lines: [String: any AppleEventEncodable] = ["----": "^\\w+$", "$in ": "one\ntwo", "UsGR": true, "WaMr": true, "WaAl": true, "synt": "PCRE"]
		#expect(try [String](appleEventDescriptor: #require(send("SATIFINd", lines).result)) == ["one", "two"])
		var anchored = lines
		anchored["Flag"] = ["SINGLELINE"]
		#expect(send("SATIFINd", anchored).result?.numberOfItems == 0)
		anchored["----"] = #"^\w+\z"#
		anchored["WaAl"] = false
		#expect(send("SATIFINd", anchored).error == OSAXError(-2763))
	}

	/// A group captured inside a lookbehind can start before the previous replacement ended; that used to build a
	/// reversed range and trap. Such a match is left as it is.
	@Test func onlyBackreferenceBehindThePreviousMatch() {
		let parameters: [String: any AppleEventEncodable] = ["----": "(?<=(a)b?)[bc]", "by  ": "X", "$in ": "abc", "UsGR": true, "synt": "PCRE", "back": 1]
		#expect(send("SATIRPLl", parameters).result?.stringValue == "Xbc")
	}

	/// PCRE2's match limit used to be "not found" (-2763).
	@Test func matchLimitIsAnError() {
		let reply = send("SATIFINd", ["----": "(a+)+$", "$in ": String(repeating: "a", count: 40) + "b", "UsGR": true, "synt": "PCRE"])
		#expect(reply.error?.number == -3047)
		#expect(reply.error?.message?.contains("limit") == true)
	}

	@Test func change() {
		let parameters: [String: any AppleEventEncodable] = ["----": #"(?<word>\w+)@(\w+)"#, "by  ": "\\2 at \\k<word>", "$in ": "me@home", "UsGR": true, "synt": "PCRE"]
		#expect(send("SATIRPLl", parameters).result?.stringValue == "home at me")
		var dollars = parameters
		dollars["by  "] = "${2}:$1"
		dollars["DlRf"] = true
		#expect(send("SATIRPLl", dollars).result?.stringValue == "home:me")
	}

	@Test func splitText() throws {
		let reply = send("SATISplt", ["----": "a1b22c", "by  ": #"\d+"#, "UsGR": true, "synt": "PCRE"])
		#expect(try [String](appleEventDescriptor: #require(reply.result)) == ["a", "b", "c"])
	}

	@Test func filterText() throws {
		let reply = send("SATIGPli", ["----": #"^(\w+) is (.*)$"#, "$in ": "John is ten\nAnna is twelve", "key ": "\\1", "by  ": "\\2", "synt": "PCRE"])
		let text = try #require(reply.result?.stringValue)
		let plist = try #require(PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: String])
		#expect(plist == ["John": "ten", "Anna": "twelve"])
	}

	@Test func reCompileAndErrors() {
		#expect(send("SATICmpi", ["----": #"(?<=\$)\d++"#, "synt": "PCRE"]).result?.stringValue == #"(?<=\$)\d++"#)
		let error = send("SATICmpi", ["----": "(unclosed", "synt": "pcre"]).error
		#expect(error?.number == -3114)
		#expect(error?.message?.contains("missing closing parenthesis") == true)
		// Onigmo's errors stay numbers only, as in Satimage.
		#expect(send("SATICmpi", ["----": "(unclosed"]).error?.message == nil)
		// Flags PCRE doesn't have, and DOTALL with Onigmo.
		#expect(send("SATIFINd", ["----": "a", "$in ": "a", "UsGR": true, "synt": "PCRE", "Flag": ["FIND LONGEST"]]).error?.number == -1)
		#expect(send("SATIFINd", ["----": "a", "$in ": "a", "UsGR": true, "Flag": ["DOTALL"]]).error?.number == -1)
	}

	@Test func appWideDefault() {
		let parameters: [String: any AppleEventEncodable] = ["----": #"\h+"#, "$in ": spaces, "UsGR": true, "WaMr": true]
		#expect(send("SATIFINd", parameters, syntaxDefault: .pcre).result?.stringValue == " \t ")
		// An explicit syntax wins.
		var ruby = parameters
		ruby["synt"] = "RUBY"
		#expect(send("SATIFINd", ruby, syntaxDefault: .pcre).error == OSAXError(-2763))
		#expect(send("SATICmpi", ["----": #"\d++"#], syntaxDefault: .pcre).error == nil)
		// Not set: Satimage's RUBY.
		#expect(send("SATIFINd", parameters).error == OSAXError(-2763))
	}

	@Test func defaultReadsTheSetting() throws {
		let defaults = MemoryDefaults.make()
		#expect(Settings.regexSyntax(in: defaults) == .ruby)
		defaults.set("pcre", forKey: "RegexSyntax")
		#expect(Settings.regexSyntax(in: defaults) == .pcre)
		defaults.set("NOT_A_SYNTAX", forKey: "RegexSyntax")
		#expect(Settings.regexSyntax(in: defaults) == .ruby)
	}
}
