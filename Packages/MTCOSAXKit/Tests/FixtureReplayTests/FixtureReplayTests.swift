import Foundation
import MTCOSAX
import Testing

enum Fixtures {
	static let directory = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent() // FixtureReplayTests
		.deletingLastPathComponent() // Tests
		.appendingPathComponent("Fixtures")

	/// Folders that aren't replayed against the full catalog.
	static let excludedFolders: Set = ["Examples"]

	/// Paths relative to the Fixtures folder, e.g. "Diagnostics/ping.json". `cases.json` files are inputs, not fixtures.
	static func paths(in folder: String? = nil) -> [String] {
		let root = folder.map { directory.appendingPathComponent($0) } ?? directory
		let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "json" && $0.lastPathComponent != "cases.json" } ?? []
		return files
			.map { String($0.standardizedFileURL.path.dropFirst(directory.standardizedFileURL.path.count + 1)) }
			.filter { folder != nil || !excludedFolders.contains(String($0.prefix { $0 != "/" })) }
			.sorted()
	}

	static func load(_ path: String) throws -> Fixture {
		try Fixture(contentsOf: directory.appendingPathComponent(path))
	}
}

/// Replays every recorded fixture against the app's real commands.
struct FixtureReplayTests {
	@Test(arguments: Fixtures.paths())
	func replay(_ path: String) throws {
		let differences = try Fixtures.load(path).replay(using: CommandCatalog.makeDispatcher())
		#expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
	}

	@Test func fixturesExist() {
		#expect(!Fixtures.paths().isEmpty)
	}
}

/// Satimage fixtures recorded before the command is implemented, replayed against a stand-in,
/// to show that recording and replay work end to end.
struct ExampleFixtureTests {
	private let stub: CommandDispatcher = {
		let dispatcher = CommandDispatcher()
		dispatcher.register(CommandDefinition("uppercase", code: "SATIUPPE") { request in
			let value = try request.requiredDirectParameter(as: AnyDescriptor.self).descriptor
			if value.descriptorType == typeAEList {
				return try [String](appleEventDescriptor: value).map { $0.uppercased() }
			}
			return try String(appleEventDescriptor: value).uppercased()
		})
		return dispatcher
	}()

	@Test(arguments: Fixtures.paths(in: "Examples"))
	func replayAgainstStub(_ path: String) throws {
		let fixture = try Fixtures.load(path)
		#expect(fixture.recordedFrom == "SatimageOSAX")
		let differences = fixture.replay(using: stub)
		#expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
	}

	@Test func wrongStubIsCaught() throws {
		let lowercase = CommandDispatcher()
		lowercase.register(CommandDefinition("uppercase", code: "SATIUPPE") { request in
			try request.requiredDirectParameter(as: String.self).lowercased()
		})
		#expect(!(try Fixtures.load("Examples/uppercase-text.json").replay(using: lowercase).isEmpty))
	}
}
