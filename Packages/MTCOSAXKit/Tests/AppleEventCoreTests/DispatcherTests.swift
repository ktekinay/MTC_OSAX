import Foundation
import Testing
@testable import AppleEventCore

/// Builds an Apple event with the given parameters, as a script would send it.
func makeEvent(_ code: String, _ parameters: [String: NSAppleEventDescriptor] = [:]) -> NSAppleEventDescriptor {
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return event
}

func makeReplyEvent() -> NSAppleEventDescriptor {
	NSAppleEventDescriptor.untargetedEvent(EventKey(eventClass: kCoreEventClass, eventID: kAEAnswer))
}

struct RequestTests {
	@Test func requiredParameterPresent() throws {
		let request = AppleEventRequest(makeEvent("TESTtest", ["$in ": NSAppleEventDescriptor(string: "abc")]))
		#expect(try request.requiredParameter("$in ", as: String.self) == "abc")
	}

	@Test func requiredParameterMissing() {
		let request = AppleEventRequest(makeEvent("TESTtest"))
		#expect(throws: OSAXError.missingParameter) {
			try request.requiredParameter("$in ", as: String.self)
		}
	}

	/// AppleScript sends an omitted direct parameter as null (see the uppercase-missing-parameter fixture).
	@Test func nullDirectParameterCountsAsMissing() {
		let request = AppleEventRequest(makeEvent("TESTtest", ["----": .null()]))
		#expect(!request.has("----"))
		#expect(throws: OSAXError.missingParameter) {
			try request.requiredDirectParameter(as: String.self)
		}
	}

	@Test func parameterCoercionFails() {
		let request = AppleEventRequest(makeEvent("TESTtest", ["CaSe": ["a"].appleEventDescriptor]))
		#expect(throws: OSAXError.coercionFailed) {
			try request.parameter("CaSe", as: String.self)
		}
	}

	@Test func parameterDefault() throws {
		let request = AppleEventRequest(makeEvent("TESTtest"))
		#expect(try request.parameter("CaSe", default: true))
	}
}

struct DispatcherTests {
	private func dispatcher() -> CommandDispatcher {
		let dispatcher = CommandDispatcher()
		dispatcher.register([
			CommandDefinition("test double", code: "TESTdoub") { request in
				try request.requiredDirectParameter(as: Int.self) * 2
			},
			CommandDefinition("test nothing", code: "TESTnone") { _ in nil },
			CommandDefinition("test fail", code: "TESTfail") { _ in
				throw OSAXError(-1234, "custom")
			},
			CommandDefinition("test swift error", code: "TESTswft") { _ in
				throw CocoaError(.fileNoSuchFile)
			},
		])
		return dispatcher
	}

	@Test func dispatchesToHandler() {
		let reply = dispatcher().dispatch(makeEvent("TESTdoub", ["----": NSAppleEventDescriptor(int32: 21)]))
		#expect(reply.error == nil)
		#expect(reply.result?.int32Value == 42)
	}

	@Test func unknownEventIsNotHandled() {
		#expect(dispatcher().dispatch(makeEvent("TESTnope")).error == .eventNotHandled)
	}

	@Test func osaxErrorIsReturned() {
		#expect(dispatcher().dispatch(makeEvent("TESTfail")).error == OSAXError(-1234, "custom"))
	}

	@Test func otherErrorsBecomeGeneralErrors() {
		let error = dispatcher().dispatch(makeEvent("TESTswft")).error
		#expect(error?.number == -2700)
		#expect(error?.message?.isEmpty == false)
	}

	@Test func writesResultToReply() {
		let replyEvent = makeReplyEvent()
		dispatcher().handle(event: makeEvent("TESTdoub", ["----": NSAppleEventDescriptor(int32: 5)]), reply: replyEvent)
		#expect(replyEvent.paramDescriptor(forKeyword: keyDirectObject)?.int32Value == 10)
		#expect(replyEvent.paramDescriptor(forKeyword: keyErrorNumber) == nil)
	}

	@Test func writesErrorToReply() {
		let replyEvent = makeReplyEvent()
		dispatcher().handle(event: makeEvent("TESTfail"), reply: replyEvent)
		#expect(replyEvent.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value == -1234)
		#expect(replyEvent.paramDescriptor(forKeyword: keyErrorString)?.stringValue == "custom")
		#expect(AppleEventReply(replyEvent: replyEvent).error == OSAXError(-1234, "custom"))
	}

	@Test func standardErrorsHaveNoMessage() {
		let replyEvent = makeReplyEvent()
		dispatcher().handle(event: makeEvent("TESTdoub"), reply: replyEvent)
		#expect(replyEvent.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value == -1701)
		#expect(replyEvent.paramDescriptor(forKeyword: keyErrorString) == nil)
	}

	@Test func noResultLeavesReplyEmpty() {
		let replyEvent = makeReplyEvent()
		dispatcher().handle(event: makeEvent("TESTnone"), reply: replyEvent)
		#expect(replyEvent.numberOfItems == 0)
	}

	@Test func nullReplyIsIgnored() {
		// Sent with no reply requested; must not crash.
		dispatcher().handle(event: makeEvent("TESTdoub", ["----": NSAppleEventDescriptor(int32: 1)]), reply: .null())
	}
}
