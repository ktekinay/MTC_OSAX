import Foundation
import Testing
@testable import AppleEventCore

@MainActor
struct FixtureTests {
	/// A case named after the cases file wrote over it, and quotes in the app's name or a variable broke the script.
	@Test func recordingNamesAndText() {
		let cases = URL(fileURLWithPath: "/x/cases.json")
		#expect(Fixture.problem(withCaseName: "uppercase-text", casesFile: cases) == nil)
		for name in ["cases", "Cases", "a/b", ".hidden", ""] {
			#expect(Fixture.problem(withCaseName: name, casesFile: cases) != nil, "\(name)")
		}
		#expect(Fixture.appleScriptStringContents(#"a "b" \c"#) == #"a \"b\" \\c"#)
	}

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

	/// A fixture's file-changing command is sent only with paths inside the replay's folders: a recorded path in a
	/// spelling the variables don't match (an HFS path) would otherwise act on the real place. The HFS spelling of a
	/// variable's value is itself replaced.
	@Test func fileChangesStayInTheReplayFolders() throws {
		let recorded = "/private/tmp/recorded-here"
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString)").path
		var sent: [String] = []
		let dispatcher = CommandDispatcher()
		dispatcher.register(CommandDefinition("fileremove", code: "QuomRemo") { request in
			sent.append(try request.requiredDirectParameter(as: String.self))
			return 1
		})
		dispatcher.register(CommandDefinition("filegetname", code: "QuomGFNa") { request in
			try request.requiredDirectParameter(as: String.self)
		})
		func fixture(_ code: String, _ path: String) -> Fixture {
			Fixture(
				name: "paths", script: "", recordedFrom: "Test", recordedAt: Date(timeIntervalSince1970: 0), variables: ["TMP": recorded],
				exchanges: [Fixture.Exchange(
					event: DescriptorSnapshot(makeEvent(code, ["----": NSAppleEventDescriptor(string: path)])),
					reply: Fixture.Reply(AppleEventReply(result: code == "QuomRemo" ? NSAppleEventDescriptor(int32: 1) : NSAppleEventDescriptor(string: path)))
				)]
			)
		}
		let volume = try #require(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
		// Inside, by the variable's value and by its HFS spelling (whatever the volume was called).
		#expect(fixture("QuomRemo", recorded + "/a.txt").replay(using: dispatcher, variables: ["TMP": folder]).isEmpty)
		#expect(fixture("QuomRemo", "Elsewhere:private:tmp:recorded-here:a.txt").replay(using: dispatcher, variables: ["TMP": folder]).isEmpty)
		#expect(sent == [folder + "/a.txt", volume + folder.replacingOccurrences(of: "/", with: ":") + ":a.txt"])
		// Outside: not sent, and a difference.
		for path in ["/private/tmp/other/a.txt", "file:///private/tmp/other/a.txt", "~/a.txt", volume + ":private:tmp:other:a.txt", recorded + "/../a.txt"] {
			let differences = fixture("QuomRemo", path).replay(using: dispatcher, variables: ["TMP": folder])
			#expect(differences.first?.contains("outside the replay's folders") == true, "\(path)")
		}
		#expect(sent.count == 2)
		// A command that only reads may name anything.
		#expect(fixture("QuomGFNa", "/private/tmp/other/a.txt").replay(using: dispatcher, variables: ["TMP": folder]).isEmpty)
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

	/// A recorded value is replaced everywhere, so only paths and URLs are allowed.
	@Test func recordedValuesArePathsOrURLs() {
		var fixture = fixture(expecting: AppleEventReply(result: NSAppleEventDescriptor(int32: 42)))
		fixture.variables = ["TMP": "/private/tmp/x"]
		#expect(fixture.replay(using: dispatcher(), variables: ["TMP": "/tmp/y"]).isEmpty)
		fixture.variables = ["N": "4"]
		#expect(fixture.replay(using: dispatcher(), variables: ["N": "5"]).first?.contains("isn't a path or URL") == true)
	}

	/// A keyword descriptor's data was read with an aligned load and no length check.
	@Test func shortKeyword() {
		let short = NSAppleEventDescriptor(descriptorType: typeKeyword, data: Data([0x61, 0x62]))!
		#expect(DescriptorSnapshot(short).code == "????")
		#expect(DescriptorSnapshot(NSAppleEventDescriptor(descriptorType: typeKeyword, bytes: [UInt32(0x6B657977)], length: 4)!).code == "keyw")
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
