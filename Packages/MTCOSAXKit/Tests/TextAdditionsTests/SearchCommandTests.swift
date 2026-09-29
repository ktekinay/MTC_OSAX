import AppleEventCore
import Foundation
import Testing
@testable import TextAdditions

/// Sends a command to the Text suite's handlers, with the app-wide dollar references setting as given.
@MainActor
private func send(
	_ code: String,
	_ parameters: [String: any AppleEventEncodable],
	dollarReferencesDefault: Bool = false
) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(TextAdditions.commands(context: TextContext(dollarReferencesDefault: { dollarReferencesDefault })))
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return dispatcher.dispatch(event)
}

private let change = "SATIRPLl"
private let findText = "SATIFINd"

/// The dollar references extension: parameter, then flag, then app-wide default.
@MainActor
struct DollarReferencesTests {
	private let regexChange: [String: any AppleEventEncodable] = ["----": "(b)", "by  ": "[$1]", "$in ": "abc", "UsGR": true]

	@Test func offByDefault() {
		#expect(send(change, regexChange).result?.stringValue == "a[$1]c")
	}

	@Test func parameter() {
		var parameters = regexChange
		parameters["DlRf"] = true
		#expect(send(change, parameters).result?.stringValue == "a[b]c")
	}

	@Test func flag() {
		var parameters = regexChange
		parameters["Flag"] = ["DOLLAR REFERENCES"]
		#expect(send(change, parameters).result?.stringValue == "a[b]c")
	}

	@Test func appWideDefault() {
		#expect(send(change, regexChange, dollarReferencesDefault: true).result?.stringValue == "a[b]c")
	}

	@Test func explicitFalseOverridesDefaultAndFlag() {
		var parameters = regexChange
		parameters["DlRf"] = false
		parameters["Flag"] = ["DOLLAR_REFERENCES"]
		#expect(send(change, parameters, dollarReferencesDefault: true).result?.stringValue == "a[$1]c")
	}

	@Test func findTextUsing() {
		let reply = send(findText, ["----": "([a-z]+)-([0-9]+)", "$in ": "x ab-12", "by  ": "$2:$1", "UsGR": true, "WaMr": true, "DlRf": true])
		#expect(reply.result?.stringValue == "12:ab")
	}

	@Test func literalChangeIgnoresIt() {
		let reply = send(change, ["----": "b", "by  ": "$0", "$in ": "abc", "DlRf": true])
		#expect(reply.result?.stringValue == "a$0c")
	}
}

/// Rules recorded from Satimage that aren't obvious from its dictionary.
@MainActor
struct SearchRuleTests {
	@Test func notFoundIsError2763() {
		#expect(send(findText, ["----": "z", "$in ": "abc"]).error == OSAXError(-2763))
	}

	@Test func notFoundWithAllOccurrencesIsEmptyList() {
		let reply = send(findText, ["----": "z", "$in ": "abc", "WaAl": true])
		#expect(reply.error == nil)
		#expect(reply.result?.numberOfItems == 0)
	}

	@Test func notFoundInListIsMissingValue() {
		let reply = send(findText, ["----": "a", "$in ": ["a", "b"], "WaMr": true])
		#expect(reply.result.map(DescriptorSnapshot.init)?.summary == #"list [utxt "a", type 'msng']"#)
	}

	@Test func emptyMatchNotTakenAtEnd() {
		let reply = send(change, ["----": "x*", "by  ": "-", "$in ": "ab", "UsGR": true])
		#expect(reply.result?.stringValue == "-a-b")
	}

	@Test func dollarMatchesAtEnd() {
		let reply = send(change, ["----": "$", "by  ": "!", "$in ": "a\nb", "UsGR": true])
		#expect(reply.result?.stringValue == "a!\nb!")
	}

	@Test func literalSearchIsCanonical() {
		let reply = send(findText, ["----": "é", "$in ": "cafe\u{301}"])
		#expect(reply.result.map(DescriptorSnapshot.init)?.summary == #"reco {mPos: long 3, mLen: long 2, mRes: utxt "é"}"#)
	}

	@Test func wholeWordTreatsUnderscoreAsLetter() {
		#expect(send(findText, ["----": "cat", "$in ": "cat_x", "WhWo": true]).error == OSAXError(-2763))
		#expect(send(findText, ["----": "cat", "$in ": "(cat)", "WhWo": true]).error == nil)
	}

	@Test func backwardUsesTextBeforeStart() {
		let reply = send(findText, ["----": "b", "$in ": "abcabc", "back": true, "strt": 3, "WaMr": true])
		#expect(reply.result?.stringValue == "b")
	}

	@Test func optionsOverrideParameters() {
		let reply = send(findText, ["----": "B", "$in ": "abc", "Opti": "cs", "CaSe": true])
		#expect(reply.result?.stringValue == "b")
	}

	@Test func unknownFlagIsMinusOne() {
		#expect(send(findText, ["----": "a", "$in ": "a", "UsGR": true, "Flag": ["NOPE"]]).error == OSAXError(-1))
	}

	@Test func invalidRegexReturnsOnigmoCode() {
		#expect(send(findText, ["----": "(a", "$in ": "a", "UsGR": true]).error == OSAXError(-117))
	}

	@Test func mismatchedChangeLists() {
		#expect(send(change, ["----": ["a", "b"], "by  ": ["x"], "$in ": "ab"]).error == OSAXError(-1))
	}

	/// Satimage returned error 5.
	@Test func emptyChangeListsLeaveTextAlone() {
		#expect(send(change, ["----": [String](), "by  ": [String](), "$in ": "ab"]).result?.stringValue == "ab")
	}

	/// Satimage returned no result at all.
	@Test func onlyBackreferenceUnmatchedLeavesMatch() {
		let reply = send(change, ["----": "a(x)?(c)", "by  ": "X", "$in ": "ac axc", "UsGR": true, "back": 1])
		#expect(reply.result?.stringValue == "ac aXc")
	}

	@Test func reCompileReturnsPattern() {
		#expect(send("SATICmpi", ["----": "a(b)c"]).result?.stringValue == "a(b)c")
	}

	/// Each match used to copy the whole text again, so 1,250 matches in 100 KB took 8 seconds, and this took over
	/// 10 minutes. It now takes about 0.3 seconds (about 1 with AddressSanitizer).
	@Test func literalSearchOfManyMatchesIsFast() {
		let text = String(repeating: "ab ", count: 20_000)
		let clock = ContinuousClock()
		var found: AppleEventReply?
		var changed: AppleEventReply?
		let elapsed = clock.measure {
			found = send(findText, ["----": "ab", "$in ": text, "WaAl": true, "WaMr": true])
			changed = send(change, ["----": "ab", "by  ": "x", "$in ": text])
		}
		#expect(found?.result?.numberOfItems == 20_000)
		#expect(changed?.result?.stringValue == String(repeating: "x ", count: 20_000))
		#expect(elapsed < .seconds(5))
	}
}
