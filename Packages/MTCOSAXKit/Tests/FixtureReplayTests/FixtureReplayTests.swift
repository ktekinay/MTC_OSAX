import Foundation
import MTCOSAX
import Testing
import TestSupport

enum Fixtures {
	static let directory = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent() // FixtureReplayTests
		.deletingLastPathComponent() // Tests
		.appendingPathComponent("Fixtures")

	/// Folders that aren't replayed against the full catalog.
	/// Examples replay against a stub; XMLNetwork needs the test server (NetworkFixtureTests).
	static let excludedFolders: Set = ["Examples", "XMLNetwork"]

	/// Folders whose reals may differ from SatimageOSAX's by a few units in the last place: Intel's and Apple
	/// silicon's math libraries differ slightly (up to 15 units for `lgamma` near its roots).
	static let realTolerances = ["MathFunctions": 16, "MathFunctionsFixes": 16, "Arrays": 16, "ArraysFixes": 16]

	/// Folders whose reals may also differ by that much in absolute terms: `evalformula`'s functions near a root
	/// (`lgamma` near 2 is a few units of 1 away, hundreds of units of the tiny result).
	static let absoluteTolerances = ["Arrays": 16 * Double.ulpOfOne, "ArraysFixes": 16 * Double.ulpOfOne]

	/// Least-squares fits, whose last digits depend on the method (SatimageOSAX's coefficients for an exact
	/// interpolation came out 1e-14 from 1): within 1e-12 of the recorded ones.
	static let fixtureAbsoluteTolerances = ["Arrays/fitpolynomial-": 1e-12, "Arrays/fitrational-": 1e-12, "ArraysFixes/fitpolynomial-": 1e-12]

	/// Paths relative to the Fixtures folder, e.g. "Diagnostics/ping.json". `cases*.json` files are inputs, not fixtures.
	static func paths(in folder: String? = nil) -> [String] {
		let root = folder.map { directory.appendingPathComponent($0) } ?? directory
		let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("cases") } ?? []
		return files
			.map { String($0.standardizedFileURL.path.dropFirst(directory.standardizedFileURL.path.count + 1)) }
			.filter { folder != nil || !excludedFolders.contains(String($0.prefix { $0 != "/" })) }
			.sorted()
	}

	static func load(_ path: String) throws -> Fixture {
		try Fixture(contentsOf: directory.appendingPathComponent(path))
	}

	/// Replays a fixture with its variables set for this run: `FILES` is the `Input` folder next to the fixture (or its
	/// section's, for a "…Fixes" folder),
	/// `TMP` a new empty folder, removed afterwards. `TMP` is a real path (`/private/var/…`, not `/var/…`), as
	/// recorded, since file references and aliases in results resolve symbolic links.
	@MainActor
	static func replay(_ path: String, using dispatcher: CommandDispatcher) throws -> [String] {
		let fixture = try load(path)
		var temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mtc-replay-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
		if let real = realpath(temporary.path, nil) {
			temporary = URL(fileURLWithPath: String(cString: real), isDirectory: true)
			free(real)
		}
		defer { try? FileManager.default.removeItem(at: temporary) }
		// A "…Fixes" folder shares its section's inputs (e.g. PropertyListsFixes uses PropertyLists/Input).
		let fixtureFolder = directory.appendingPathComponent(path).deletingLastPathComponent()
		var input = fixtureFolder.appendingPathComponent("Input")
		if !FileManager.default.fileExists(atPath: input.path), fixtureFolder.lastPathComponent.hasSuffix("Fixes") {
			input = fixtureFolder.deletingLastPathComponent()
				.appendingPathComponent(String(fixtureFolder.lastPathComponent.dropLast("Fixes".count)))
				.appendingPathComponent("Input")
		}
		let folder = String(path.prefix { $0 != "/" })
		// A copy of the inputs in the temporary folder, whose path has no spaces (URLs in replies stay as recorded).
		let files = temporary.appendingPathComponent("files")
		if FileManager.default.fileExists(atPath: input.path) {
			try FileManager.default.copyItem(at: input, to: files)
		}
		return fixture.replay(
			using: dispatcher, variables: ["FILES": files.path, "TMP": temporary.path],
			realTolerance: realTolerances[folder] ?? 0,
			absoluteTolerance: fixtureAbsoluteTolerances.first { path.hasPrefix($0.key) }?.value ?? absoluteTolerances[folder] ?? 0
		)
	}
}

/// Replays every recorded fixture against the app's real commands.
@MainActor
struct FixtureReplayTests {
	@Test(arguments: Fixtures.paths())
	func replay(_ path: String) throws {
		let timeZone = try Fixtures.load(path).timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
		// Settings of their own: fixtures don't read or change the machine's.
		let differences = try Fixtures.replay(path, using: CommandCatalog.makeDispatcher(timeZone: timeZone, settings: MemoryDefaults.make()))
		#expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
	}

	@Test func fixturesExist() {
		#expect(!Fixtures.paths().isEmpty)
	}
}

/// XMLOpen of http URLs, replayed against the test server they were recorded with (`$HTTP`), with the XML
/// fixtures' input files.
@MainActor
struct NetworkFixtureTests {
	@Test(arguments: Fixtures.paths(in: "XMLNetwork"))
	func replay(_ path: String) throws {
		let files = Fixtures.directory.appendingPathComponent("XML/Input")
		let server = try NetworkFixtureServer(folder: files)
		let fixture = try Fixtures.load(path)
		let differences = fixture.replay(using: CommandCatalog.makeDispatcher(), variables: ["HTTP": server.address, "FILES": files.path])
		#expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
	}
}

/// The test server serves only the files in its folder.
@MainActor
struct NetworkFixtureServerTests {
	@Test func staysInItsFolder() throws {
		let files = Fixtures.directory.appendingPathComponent("XML/Input")
		let server = try NetworkFixtureServer(folder: files)
		func status(_ path: String) throws -> Int? {
			let url = try #require(URL(string: server.address + path))
			let result = Result<Data, Error>.fetchStatus(URLRequest(url: url))
			return result
		}
		#expect(try status("/files/simple.xml") == 200)
		for path in ["/files/../FixtureReplayTests.swift", "/files/%2E%2E%2Fcases.json", "/files/", "/files/.."] {
			#expect(try status(path) == 404, "\(path)")
		}
	}
}

extension Result where Success == Data, Failure == Error {
	/// The status of a synchronous request.
	static func fetchStatus(_ request: URLRequest) -> Int? {
		let done = DispatchSemaphore(value: 0)
		nonisolated(unsafe) var status: Int?
		URLSession.shared.dataTask(with: request) { _, response, _ in
			status = (response as? HTTPURLResponse)?.statusCode
			done.signal()
		}.resume()
		done.wait()
		return status
	}
}

/// Satimage fixtures recorded before the command is implemented, replayed against a stand-in,
/// to show that recording and replay work end to end.
@MainActor
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
