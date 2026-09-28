import AppleEventCore
import Darwin
import Foundation
import Testing
@testable import FilesAndFolders

/// Runs a command with the given parameters.
private func send(_ code: String, _ parameters: [String: any AppleEventEncodable]) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(FilesAndFolders.commands())
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return dispatcher.dispatch(event)
}

/// A new, empty temporary folder for one test, removed afterwards.
private final class Sandbox {
	let url = FileManager.default.temporaryDirectory.appendingPathComponent("files-\(UUID().uuidString)")

	init() throws {
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	}

	deinit {
		// Unlock anything a test locked, so it can be removed.
		if let paths = FileManager.default.enumerator(atPath: url.path) {
			for case let path as String in paths {
				chflags(url.appendingPathComponent(path).path, 0)
			}
		}
		try? FileManager.default.removeItem(at: url)
	}

	func path(_ name: String) -> String { url.appendingPathComponent(name).path }

	func file(_ name: String, _ text: String = "x") throws -> URL {
		let file = url.appendingPathComponent(name)
		try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data(text.utf8).write(to: file)
		return file
	}

	func exists(_ name: String) -> Bool {
		var status = stat()
		return lstat(path(name), &status) == 0
	}
}

private let getName = "QuomGFNa", fileNew = "QuomNewF", makeDirectory = "QuomMkDi", rename = "QuomRenF"
private let changeMode = "Quomchmd", copy = "QuomCopy", move = "QuomMove", remove = "QuomRemo"
private let makeTemporaryFile = "Quommkst", makeTemporaryFolder = "Quommkdt"
private let createSymlink = "QuomSymL", testSymlink = "QuomIsSy", readLink = "Quomrdsy"

struct PathInputTests {
	@Test func pathForms() throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("a b.txt")
		let hfsVolume = try #require(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
		let hfs = hfsVolume + file.path.replacingOccurrences(of: "/", with: ":")
		for form: any AppleEventEncodable in [file, file.path, file.absoluteString, hfs] {
			#expect(send(getName, ["----": form]).result?.stringValue == "a b.txt", "\(form)")
		}
	}

	@Test func listsAndRelativePaths() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("a.txt")
		let names = send(getName, ["----": ["a.txt", "b.txt"], "from": sandbox.url])
		#expect(names.result.map(DescriptorSnapshot.init)?.summary == #"list [utxt "a.txt", utxt "b.txt"]"#)
	}
}

struct CreateTests {
	@Test func fileNewCreatesFoldersOnTheWay() throws {
		let sandbox = try Sandbox()
		let reply = send(fileNew, ["----": sandbox.path("a/b/n.txt")])
		#expect(reply.result?.stringValue == sandbox.path("a/b/n.txt"))
		#expect(sandbox.exists("a/b/n.txt"))
	}

	/// Satimage failed with error 1 for a path string directly in a system folder such as /private/tmp.
	@Test func pathStringsInSystemFolders() throws {
		let name = "/private/tmp/mtc-unit-\(UUID().uuidString)"
		defer {
			try? FileManager.default.removeItem(atPath: name)
			try? FileManager.default.removeItem(atPath: name + ".txt")
		}
		#expect(send(makeDirectory, ["----": name]).result?.stringValue == name + "/")
		#expect(send(fileNew, ["----": name + ".txt"]).result?.stringValue == name + ".txt")
	}

	@Test func fileNewWithName() throws {
		let sandbox = try Sandbox()
		#expect(send(fileNew, ["----": sandbox.url, "pnam": "n.txt"]).result?.stringValue == sandbox.path("n.txt"))
	}

	@Test func fileNewExisting() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("n.txt")
		#expect(send(fileNew, ["----": sandbox.path("n.txt")]).error == OSAXError(-48))
	}

	@Test func mkdir() throws {
		let sandbox = try Sandbox()
		#expect(send(makeDirectory, ["----": sandbox.path("a/b")]).result?.stringValue == sandbox.path("a/b") + "/")
		#expect(send(makeDirectory, ["----": sandbox.path("a/b")]).error == OSAXError(17))
		#expect(send(makeDirectory, ["----": sandbox.path("x/y"), "RECU": false]).error == OSAXError(2))
		#expect(send(makeDirectory, ["----": sandbox.url, "pnam": "c"]).result?.stringValue == sandbox.path("c") + "/")
	}

	@Test func renameFile() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("a.txt")
		_ = try sandbox.file("c.txt")
		#expect(send(rename, ["----": sandbox.path("a.txt"), "to  ": "b.txt"]).result?.stringValue == sandbox.path("b.txt"))
		#expect(send(rename, ["----": sandbox.path("b.txt"), "to  ": "c.txt"]).error == OSAXError(-48))
		#expect(send(rename, ["----": sandbox.path("b.txt"), "to  ": "x/y"]).error == OSAXError(-1))
		#expect(send(rename, ["----": sandbox.path("nope"), "to  ": "z"]).error == OSAXError(-43))
	}

	/// The same item with another case used to count as an existing item (-48).
	@Test func renameCaseOnly() throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("a.txt")
		#expect(send(rename, ["----": file, "to  ": "A.txt"]).result?.stringValue == sandbox.path("A.txt"))
		#expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.url.path) == ["A.txt"])
		_ = try sandbox.file("b.txt")
		#expect(send(rename, ["----": URL(fileURLWithPath: sandbox.path("b.txt")), "to  ": "a.txt"]).error == OSAXError(-48))
	}

	@Test func renameFolderHasNoTrailingSlash() throws {
		let sandbox = try Sandbox()
		try FileManager.default.createDirectory(at: sandbox.url.appendingPathComponent("d"), withIntermediateDirectories: false)
		#expect(send(rename, ["----": sandbox.path("d"), "to  ": "e"]).result?.stringValue == sandbox.path("e"))
	}
}

struct ChangeModeTests {
	@Test func getAndSet() throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("a.txt")
		Darwin.chmod(file.path, 0o644)
		#expect(send(changeMode, ["----": file]).result?.stringValue == "644")
		#expect(send(changeMode, ["----": file, "to  ": "0600"]).result?.stringValue == "644")
		#expect(send(changeMode, ["----": file]).result?.stringValue == "600")
	}

	@Test(arguments: ["abc", "999", "", "77777"])
	func invalid(_ mode: String) throws {
		let sandbox = try Sandbox()
		#expect(send(changeMode, ["----": try sandbox.file("a.txt"), "to  ": mode]).error == OSAXError(-1))
	}

	@Test func missing() throws {
		let sandbox = try Sandbox()
		#expect(send(changeMode, ["----": sandbox.path("nope")]).error == OSAXError(-1))
	}
}

struct CopyMoveTests {
	@Test func copyToFolderWithName() throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("a.txt", "hello")
		try FileManager.default.createDirectory(at: sandbox.url.appendingPathComponent("d"), withIntermediateDirectories: false)
		#expect(send(copy, ["----": file, "to  ": sandbox.path("d"), "pnam": "b.txt"]).result?.stringValue == sandbox.path("d/b.txt"))
		#expect(try String(contentsOfFile: sandbox.path("d/b.txt"), encoding: .utf8) == "hello")
		#expect(sandbox.exists("a.txt"))
	}

	@Test func replacing() throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("a.txt", "new")
		_ = try sandbox.file("b.txt", "old")
		#expect(send(copy, ["----": file, "into": URL(fileURLWithPath: sandbox.path("b.txt"))]).error == OSAXError(-48))
		#expect(send(copy, ["----": file, "into": URL(fileURLWithPath: sandbox.path("b.txt")), "Repl": true]).error == nil)
		#expect(try String(contentsOfFile: sandbox.path("b.txt"), encoding: .utf8) == "new")
	}

	@Test func listsAndErrors() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("a.txt")
		_ = try sandbox.file("b.txt")
		try FileManager.default.createDirectory(at: sandbox.url.appendingPathComponent("d"), withIntermediateDirectories: false)
		let list = send(copy, ["----": ["a.txt", "b.txt"], "from": sandbox.url, "to  ": sandbox.path("d")])
		#expect(list.result?.numberOfItems == 2)
		#expect(send(copy, ["----": ["a.txt"], "from": sandbox.url, "to  ": sandbox.path("d"), "pnam": "x"]).error == OSAXError(-50))
		#expect(send(copy, ["----": sandbox.path("nope"), "to  ": sandbox.path("d")]).error == OSAXError(-43))
		#expect(send(copy, ["----": sandbox.path("a.txt"), "to  ": sandbox.path("nope")]).error == OSAXError(-43))
		#expect(send(copy, ["----": sandbox.path("a.txt")]).error == .missingParameter)
	}

	/// `with replacing` onto the item itself removed the "existing" target, which was the source, and then failed.
	@Test func ontoItself() throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("a.txt", "keep")
		for command in [copy, move] {
			#expect(send(command, ["----": file, "to  ": sandbox.url]).error == OSAXError(-48))
			#expect(send(command, ["----": file, "to  ": sandbox.url, "Repl": true]).result?.stringValue == sandbox.path("a.txt"))
			#expect(send(command, ["----": file, "into": URL(fileURLWithPath: sandbox.path("A.TXT")), "Repl": true]).error == nil)
			#expect(try String(contentsOfFile: sandbox.path("a.txt"), encoding: .utf8) == "keep")
		}
		// Moving to another spelling renames (the volume is case-insensitive).
		#expect(send(move, ["----": file, "to  ": sandbox.url, "pnam": "A.txt"]).result?.stringValue == sandbox.path("A.txt"))
		#expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.url.path) == ["A.txt"])
	}

	/// The new item is made first, so a failure leaves the old one (and the source of a move).
	@Test func replacingKeepsTheOldItemOnFailure() throws {
		let sandbox = try Sandbox()
		let source = try sandbox.file("s/a.txt", "new")
		_ = try sandbox.file("d/a.txt", "old")
		chmod(sandbox.path("s/a.txt"), 0)
		defer { chmod(sandbox.path("s/a.txt"), 0o644) }
		#expect(send(copy, ["----": source, "to  ": sandbox.path("d"), "Repl": true]).error?.number == -1)
		#expect(try String(contentsOfFile: sandbox.path("d/a.txt"), encoding: .utf8) == "old")
		#expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.path("d")) == ["a.txt"])
		chmod(sandbox.path("s/a.txt"), 0o644)
		// A locked old item can't be removed: the moved source goes back.
		chflags(sandbox.path("d/a.txt"), UInt32(UF_IMMUTABLE))
		#expect(send(move, ["----": source, "to  ": sandbox.path("d"), "Repl": true]).error?.number == -1)
		#expect(try String(contentsOfFile: sandbox.path("s/a.txt"), encoding: .utf8) == "new")
		#expect(try String(contentsOfFile: sandbox.path("d/a.txt"), encoding: .utf8) == "old")
		chflags(sandbox.path("d/a.txt"), 0)
		#expect(send(move, ["----": source, "to  ": sandbox.path("d"), "Repl": true]).error == nil)
		#expect(try String(contentsOfFile: sandbox.path("d/a.txt"), encoding: .utf8) == "new")
		#expect(!sandbox.exists("s/a.txt"))
	}

	@Test func moveFolder() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("s/a.txt")
		try FileManager.default.createDirectory(at: sandbox.url.appendingPathComponent("d"), withIntermediateDirectories: false)
		#expect(send(move, ["----": sandbox.path("s"), "to  ": sandbox.path("d")]).result?.stringValue == sandbox.path("d/s") + "/")
		#expect(sandbox.exists("d/s/a.txt"))
		#expect(!sandbox.exists("s"))
	}
}

struct RemoveTests {
	@Test func removeFilesAndFolders() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("a.txt")
		_ = try sandbox.file("d/b.txt")
		#expect(send(remove, ["----": [sandbox.path("a.txt"), sandbox.path("d")]]).result?.int32Value == 2)
		#expect(!sandbox.exists("a.txt"))
		#expect(!sandbox.exists("d"))
		#expect(send(remove, ["----": sandbox.path("a.txt")]).error == OSAXError(-43))
	}

	/// Satimage always reported 0 here.
	@Test func filesOnly() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("d/a.txt")
		_ = try sandbox.file("d/b.txt")
		_ = try sandbox.file("d/e/c.txt")
		#expect(send(remove, ["----": sandbox.path("d"), "FOnl": true]).result?.int32Value == 2)
		#expect(!sandbox.exists("d/a.txt"))
		#expect(sandbox.exists("d/e/c.txt"))
		#expect(sandbox.exists("d"))
	}

	@Test func dates() throws {
		let sandbox = try Sandbox()
		let old = try sandbox.file("d/old.txt")
		_ = try sandbox.file("d/new.txt")
		try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)
		let cutoff = Date(timeIntervalSince1970: 1_000_000_000)
		#expect(send(remove, ["----": sandbox.path("d"), "FOnl": true, "befo": cutoff]).result?.int32Value == 1)
		#expect(!sandbox.exists("d/old.txt"))
		#expect(sandbox.exists("d/new.txt"))
		#expect(send(remove, ["----": sandbox.path("d"), "FOnl": true, "afte": cutoff]).result?.int32Value == 1)
		#expect(!sandbox.exists("d/new.txt"))
		#expect(send(remove, ["----": sandbox.path("d"), "afte": cutoff]).error == OSAXError(-1))
	}

	@Test func lockedFiles() throws {
		let sandbox = try Sandbox()
		let locked = try sandbox.file("locked.txt")
		chflags(locked.path, UInt32(UF_IMMUTABLE))
		#expect(send(remove, ["----": locked, "CUnl": false]).error == OSAXError(-1))
		#expect(sandbox.exists("locked.txt"))
		#expect(send(remove, ["----": locked]).result?.int32Value == 1)
		#expect(!sandbox.exists("locked.txt"))
	}
}

struct TemporaryTests {
	private func name(_ reply: AppleEventReply) throws -> String {
		try #require(reply.result?.stringValue).split(separator: "/").last.map(String.init) ?? ""
	}

	@Test func mkstemp() throws {
		let sandbox = try Sandbox()
		let reply = send(makeTemporaryFile, ["----": sandbox.url, "pnam": "tmp.txt", "suff": 4])
		let name = try name(reply)
		#expect(name.hasPrefix("tmp") && name.hasSuffix(".txt") && name.count == 13)
		#expect(FileManager.default.fileExists(atPath: try #require(reply.result?.stringValue)))
	}

	@Test func mkstempWildcardsAndMode() throws {
		let sandbox = try Sandbox()
		let reply = send(makeTemporaryFile, ["----": sandbox.url, "pnam": "t", "wild": 3, "Mode": "600"])
		#expect(try name(reply).count == 4)
		let attributes = try FileManager.default.attributesOfItem(atPath: try #require(reply.result?.stringValue))
		#expect((attributes[.posixPermissions] as? Int) == 0o600)
	}

	/// Satimage always used 6 random characters for folders.
	@Test func mkdtempWildcards() throws {
		let sandbox = try Sandbox()
		let reply = send(makeTemporaryFolder, ["----": sandbox.url, "pnam": "d", "wild": 8])
		let path = try #require(reply.result?.stringValue)
		#expect(path.hasSuffix("/"))
		#expect(try name(reply).count == 9)
	}
}

struct SymlinkTests {
	@Test func createAndRead() throws {
		let sandbox = try Sandbox()
		_ = try sandbox.file("a.txt")
		#expect(send(createSymlink, ["----": "a.txt", "in  ": sandbox.url, "pnam": "l"]).error == nil)
		#expect(send(readLink, ["----": sandbox.path("l")]).result?.stringValue == "a.txt")
		#expect(send(testSymlink, ["----": sandbox.path("l")]).result?.booleanValue == true)
		#expect(send(testSymlink, ["----": sandbox.path("a.txt")]).result?.booleanValue == false)
		#expect(send(testSymlink, ["----": sandbox.path("nope")]).result?.booleanValue == false)
	}

	@Test func fileReferenceTargetIsAbsolute() throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("a.txt")
		_ = send(createSymlink, ["----": file, "in  ": sandbox.url])
		#expect(send(readLink, ["----": sandbox.path("a.txt")]).error == OSAXError(-1)) // the file itself isn't a link
		try FileManager.default.createDirectory(at: sandbox.url.appendingPathComponent("d"), withIntermediateDirectories: false)
		_ = send(createSymlink, ["----": file, "in  ": sandbox.path("d")])
		#expect(send(readLink, ["----": sandbox.path("d/a.txt")]).result?.stringValue == file.path)
	}

	@Test func replacing() throws {
		let sandbox = try Sandbox()
		_ = send(createSymlink, ["----": "a", "in  ": sandbox.url, "pnam": "l"])
		#expect(send(createSymlink, ["----": "b", "in  ": sandbox.url, "pnam": "l"]).error == nil)
		#expect(send(readLink, ["----": sandbox.path("l")]).result?.stringValue == "b")
		#expect(send(createSymlink, ["----": "c", "in  ": sandbox.url, "pnam": "l", "Repl": false]).error == OSAXError(-48))
		_ = try sandbox.file("f")
		#expect(send(createSymlink, ["----": "a", "in  ": sandbox.url, "pnam": "f"]).error == OSAXError(-48))
	}
}

/// A `name` from an untrusted source could write outside the folder (`../escaped`).
struct NameTests {
	@Test(arguments: ["../escaped", "sub/file", "..", ".", ""])
	func namesArePlainNames(_ name: String) throws {
		let sandbox = try Sandbox()
		let file = try sandbox.file("f/a.txt")
		let folder = sandbox.path("f")
		for (command, parameters) in [
			(fileNew, ["----": folder]), (makeDirectory, ["----": folder]), (copy, ["----": file.path, "to  ": folder]),
			(move, ["----": file.path, "to  ": folder]), (makeTemporaryFile, ["----": folder]), (makeTemporaryFolder, ["----": folder]),
			(createSymlink, ["----": "/etc/hosts", "in  ": folder]),
		] as [(String, [String: any AppleEventEncodable])] {
			let error = send(command, parameters.merging(["pnam": name]) { $1 }).error
			#expect(error?.number == -1, "\(command)")
			#expect(error?.message?.contains("subfolder") == true, "\(command)")
		}
		#expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.url.path) == ["f"])
		#expect(try FileManager.default.contentsOfDirectory(atPath: folder) == ["a.txt"])
	}
}

struct RegistrationTests {
	@Test func allCommandsRegistered() {
		#expect(FilesAndFolders.commands().count == 13)
	}
}
