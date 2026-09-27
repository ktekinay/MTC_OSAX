import Foundation
import Testing
@testable import AppleEventCore

struct FixtureTests {
	private func fixture(expecting reply: AppleEventReply) -> Fixture {
		Fixture(
			name: "double",
			script: "test double 21",
			recordedFrom: "Test",
			recordedAt: Date(timeIntervalSince1970: 0),
			exchanges: [Fixture.Exchange(
				event: DescriptorSnapshot(makeEvent("TESTdoub", ["----": NSAppleEventDescriptor(int32: 21)])),
				reply: Fixture.Reply(reply)
			)]
		)
	}

	private func dispatcher() -> CommandDispatcher {
		let dispatcher = CommandDispatcher()
		dispatcher.register(CommandDefinition("test double", code: "TESTdoub") { request in
			try request.requiredDirectParameter(as: Int.self) * 2
		})
		return dispatcher
	}

	@Test func matchingReplyPasses() {
		let fixture = fixture(expecting: AppleEventReply(result: NSAppleEventDescriptor(int32: 42)))
		#expect(fixture.replay(using: dispatcher()).isEmpty)
	}

	@Test func differentResultFails() {
		let fixture = fixture(expecting: AppleEventReply(result: NSAppleEventDescriptor(int32: 43)))
		let differences = fixture.replay(using: dispatcher())
		#expect(differences.count == 1)
		#expect(differences.first?.contains("expected long 43") == true)
		#expect(differences.first?.contains("actual   long 42") == true)
	}

	@Test func unexpectedErrorFails() {
		let fixture = fixture(expecting: AppleEventReply(result: NSAppleEventDescriptor(int32: 42)))
		#expect(fixture.replay(using: CommandDispatcher()).first?.contains("error -1708") == true)
	}

	@Test func emptyFixtureFails() {
		var fixture = fixture(expecting: AppleEventReply())
		fixture.exchanges = []
		#expect(!fixture.replay(using: dispatcher()).isEmpty)
	}

	@Test func randomWildcards() {
		var expected = DescriptorSnapshot(type: "utxt")
		expected.text = "/tmp/dir{{random:6}}/"
		var actual = DescriptorSnapshot(type: "utxt")
		actual.text = "/tmp/dirAb3Xy9/"
		#expect(expected.matches(actual))
		actual.text = "/tmp/dirAb3Xy/"
		#expect(!expected.matches(actual))
		actual.text = "/tmp/xyzAb3Xy9/"
		#expect(!expected.matches(actual))
		let list = DescriptorSnapshot(["/tmp/dirAb3Xy9/"].appleEventDescriptor)
		var expectedList = DescriptorSnapshot(type: "list")
		expectedList.items = [expected]
		#expect(expectedList.normalized.matches(list.normalized))
	}

	@Test func writesAndReads() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID()).json")
		defer { try? FileManager.default.removeItem(at: url) }
		let original = fixture(expecting: AppleEventReply(error: OSAXError(-1701)))
		try original.write(to: url)
		let copy = try Fixture(contentsOf: url)
		#expect(copy.name == original.name)
		#expect(copy.recordedAt == original.recordedAt)
		#expect(copy.exchanges.first?.event == original.exchanges.first?.event)
		#expect(copy.exchanges.first?.reply == original.exchanges.first?.reply)
	}
}
