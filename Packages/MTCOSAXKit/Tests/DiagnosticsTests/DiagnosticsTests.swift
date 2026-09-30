import AppleEventCore
import Foundation
import Testing
@testable import Diagnostics

@MainActor
struct DiagnosticsTests {
	/// mtc_describe recursed without a limit, and wrote out every byte of long data.
	@Test func describeLimits() {
		var deep: NSAppleEventDescriptor = NSAppleEventDescriptor(int32: 1)
		for _ in 0 ..< 600 {
			let list = NSAppleEventDescriptor.list()
			list.insert(deep, at: 1)
			deep = list
		}
		#expect(send("MTCddesc", ["----": deep]).error?.number == -50)
		let data = NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "rdat"), data: Data(count: 1_000_000))!
		let summary = send("MTCddesc", ["----": data]).result?.stringValue ?? ""
		#expect(summary.count < 600 && summary.contains("…"))
	}

	private let dispatcher: CommandDispatcher = {
		let dispatcher = CommandDispatcher()
		dispatcher.register(Diagnostics.commands(version: { "MTC_OSAX 9.9 (99)" }))
		return dispatcher
	}()

	private func send(_ code: String, _ parameters: [String: NSAppleEventDescriptor] = [:]) -> AppleEventReply {
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
		for (keyword, value) in parameters {
			event.setParam(value, forKeyword: FourCharCode(fourCharString: keyword))
		}
		return dispatcher.dispatch(event)
	}

	@Test func ping() {
		#expect(send("MTCdping").result?.stringValue == "pong")
	}

	@Test func version() {
		#expect(send("MTCdvers").result?.stringValue == "MTC_OSAX 9.9 (99)")
	}

	@Test func echoReturnsValueUnchanged() {
		let value = AppleEventRecord(["mPos": 1, "list": AppleEventList(["a", 2.5])]).appleEventDescriptor
		let result = send("MTCdecho", ["----": value]).result
		#expect(result.map(DescriptorSnapshot.init) == DescriptorSnapshot(value))
	}

	@Test func echoRequiresValue() {
		#expect(send("MTCdecho").error == .missingParameter)
	}

	@Test func describe() {
		let value = [NSAppleEventDescriptor(string: "a"), NSAppleEventDescriptor(int32: 1)].appleEventDescriptor
		let reply = send("MTCddesc", ["----": value])
		#expect(reply.result?.stringValue == #"list [utxt "a", long 1]"#)
	}

	@Test func describeWithoutValue() {
		#expect(send("MTCddesc").result?.stringValue == "(no direct parameter)")
	}

	@Test func raiseErrorWithMessage() {
		let reply = send("MTCdrais", ["----": NSAppleEventDescriptor(string: "boom"), "errn": NSAppleEventDescriptor(int32: 42)])
		#expect(reply.error == OSAXError(42, "boom"))
	}

	/// Error 0 is success to AppleScript, so the command seemed to do nothing.
	@Test func raiseErrorZero() {
		#expect(send("MTCdrais", ["errn": NSAppleEventDescriptor(int32: 0)]).error?.number == -50)
	}

	@Test func raiseErrorWithoutMessage() {
		#expect(send("MTCdrais", ["errn": NSAppleEventDescriptor(int32: -1728)]).error == OSAXError(-1728))
	}

	@Test func raiseErrorRequiresNumber() {
		#expect(send("MTCdrais", ["----": NSAppleEventDescriptor(string: "boom")]).error == .missingParameter)
	}
}
