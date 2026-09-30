import AppleEventCore
import Foundation
import Testing
@testable import FileAdditions

/// `list files` and `glob`. Order is the file system's, so tests that don't sort by date compare sorted results.
@MainActor
struct ListFilesTests {
	private let listFiles = "SATIlsfl"

	private func tree() throws -> TemporaryFolder {
		let folder = try TemporaryFolder()
		try folder.file("a.txt")
		try folder.file("B.TXT")
		try folder.file(".hidden")
		try folder.file("img.png")
		try folder.file("sub/c.txt")
		try folder.file("sub/.dot.txt")
		try folder.file("sub/deep/d.md")
		try folder.file("pkg.app/Contents/Info.plist")
		try folder.folder("Empty")
		return folder
	}

	private func list(_ folder: TemporaryFolder, _ parameters: [String: any AppleEventEncodable] = [:]) -> [String]? {
		var parameters = parameters
		parameters["----"] = parameters["----"] ?? folder.url
		return relativePaths(send(listFiles, parameters), in: folder)?.sorted()
	}

	@Test func recursiveFilesByDefault() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(list(folder) == ["B.TXT", "a.txt", "img.png", "pkg.app", "sub/c.txt", "sub/deep/d.md"])
		#expect(send(listFiles, ["----": folder.url]).result?.atIndex(1)?.descriptorType == typeFSRef)
	}

	@Test func notRecursivelyListsFolders() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(list(folder, ["recu": false]) == ["B.TXT", "Empty", "a.txt", "img.png", "pkg.app", "sub"])
	}

	@Test func invisibles() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(list(folder, ["invi": true]) == [".hidden", "B.TXT", "a.txt", "img.png", "pkg.app", "sub/.dot.txt", "sub/c.txt", "sub/deep/d.md"])
	}

	@Test func extensionsAreCaseSensitive() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(list(folder, ["Nmxt": "txt"]) == ["a.txt", "sub/c.txt"])
		#expect(list(folder, ["Nmxt": ["TXT", "md"]]) == ["B.TXT", "sub/deep/d.md"])
		#expect(list(folder, ["Nmxt": ".txt"]) == [])
		#expect(list(folder, ["Nmxt": "app"]) == ["pkg.app"])
	}

	@Test func typeIdentifiers() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(list(folder, ["yUTI": "public.image"]) == ["img.png"])
		#expect(list(folder, ["nUTI": "public.text"]) == ["img.png", "pkg.app"])
		#expect(list(folder, ["yUTI": "public.folder", "recu": false]) == ["Empty", "sub"])
		#expect(send(listFiles, ["----": folder.url, "yUTI": "public.text", "nUTI": "public.image"]).error == .parameterError)
	}

	@Test func startingWithIsCaseSensitive() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(list(folder, ["Strw": "a"]) == ["a.txt"])
		#expect(list(folder, ["Strw": "A"]) == [])
	}

	@Test func packages() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(list(folder, ["inBu": true, "Nmxt": "plist"]) == ["pkg.app/Contents/Info.plist"])
		#expect(list(folder, ["----": folder.url.appendingPathComponent("pkg.app")]) == ["pkg.app"])
	}

	@Test func datesSortByModification() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		let now = Date()
		try folder.file("new.txt", modified: now)
		try folder.file("old.txt", modified: now.addingTimeInterval(-3600))
		try folder.file("older.txt", modified: now.addingTimeInterval(-7200))
		try folder.file("ancient.txt", modified: Date(timeIntervalSince1970: 0))
		let reply = send(listFiles, ["----": folder.url, "afte": now.addingTimeInterval(-10000)])
		#expect(relativePaths(reply, in: folder) == ["older.txt", "old.txt", "new.txt"])
		let before = send(listFiles, ["----": folder.url, "befo": now.addingTimeInterval(-1800)])
		#expect(relativePaths(before, in: folder) == ["ancient.txt", "older.txt", "old.txt"])
	}

	@Test func namesOnlyAndForms() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(texts(send(listFiles, ["----": folder.url, "namo": true, "recu": false]))?.sorted() == ["B.TXT", "Empty", "a.txt", "img.png", "pkg.app", "sub"])
		let paths = texts(send(listFiles, ["----": folder.url, "rtyp": typeObject("psxP"), "recu": false]))
		#expect(paths?.contains(folder.path("sub") + "/") == true)
		#expect(paths?.contains(folder.path("a.txt")) == true)
		let urls = texts(send(listFiles, ["----": folder.url, "rtyp": type("utxt"), "recu": false]))
		#expect(urls?.contains("file://" + folder.path("pkg.app") + "/") == true)
		let aliases = send(listFiles, ["----": folder.url, "rtyp": type("alis")]).result
		#expect(aliases?.atIndex(1)?.descriptorType == typeAlias)
	}

	@Test func symbolicLinksAreSkipped() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		try folder.file("a.txt")
		try FileManager.default.createSymbolicLink(atPath: folder.path("link.txt"), withDestinationPath: "a.txt")
		#expect(list(folder) == ["a.txt"])
	}

	@Test func inputs() throws {
		let folder = try tree()
		defer { folder.remove() }
		let expected = list(folder)
		#expect(list(folder, ["----": folder.url.path]) == expected)
		#expect(list(folder, ["----": "file://" + folder.url.path + "/"]) == expected)
		// HFS paths, which SatimageOSAX rejected with -1700.
		let hfs = NSAppleEventDescriptor(fileURL: folder.url).coerce(toDescriptorType: typeUnicodeText)!.stringValue!
		#expect(list(folder, ["----": hfs]) == expected)
		#expect(list(folder, ["----": [folder.url.appendingPathComponent("sub").path, folder.path("nope")]]) == ["sub/c.txt", "sub/deep/d.md"])
		#expect(list(folder, ["----": folder.path("nope")]) == [])
		#expect(send(listFiles, [:]).error == .missingParameter)
	}
}

@MainActor
struct GlobTests {
	private let glob = "SATIGlob"

	/// glob(3) looks for each pattern the braces make in turn: `{a,b}` 25 times, 33 million, held up every script.
	@Test func braceLimit() throws {
		#expect(FileAdditions.braceExpansions("a{b,c}d{e,f,g}") == 6)
		#expect(FileAdditions.braceExpansions("{a,{b,c}}x") == 3)
		#expect(FileAdditions.braceExpansions("\\{a,b}") == 1)
		#expect(FileAdditions.braceExpansions("{a,b") == 1)
		#expect(FileAdditions.braceExpansions(String(repeating: "{a,b}", count: 100)) > 10_000)
		let start = Date()
		#expect(send(glob, ["----": String(repeating: "{a,b}", count: 25), "from": FileManager.default.temporaryDirectory]).error?.number == -50)
		#expect(Date().timeIntervalSince(start) < 5)
		#expect(send(glob, ["----": "{x,y}{1,2}", "from": FileManager.default.temporaryDirectory]).error == nil)
	}

	private func tree() throws -> TemporaryFolder {
		let folder = try TemporaryFolder()
		try folder.file("a.txt")
		try folder.file("Apple.txt")
		try folder.file("B.TXT")
		try folder.file(".hidden")
		try folder.file("sub/c.txt")
		try folder.folder("Empty")
		return folder
	}

	private func matches(_ folder: TemporaryFolder, _ parameters: [String: any AppleEventEncodable]) -> [String]? {
		relativePaths(send(glob, parameters), in: folder)?.sorted()
	}

	@Test func patterns() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(matches(folder, ["----": folder.path("*")]) == ["Apple.txt", "B.TXT", "Empty", "a.txt", "sub"])
		#expect(matches(folder, ["----": folder.path("*.txt")]) == ["Apple.txt", "a.txt"])
		#expect(matches(folder, ["----": folder.path("?.txt")]) == ["a.txt"])
		#expect(matches(folder, ["----": folder.path("[aB]*")]) == ["B.TXT", "a.txt"])
		#expect(matches(folder, ["----": folder.path("{a,B}.*")]) == ["B.TXT", "a.txt"])
		#expect(matches(folder, ["----": folder.path("*/*")]) == ["sub/c.txt"])
		#expect(matches(folder, ["----": folder.path("*.zzz")]) == [])
		#expect(matches(folder, ["----": [folder.path("a*"), folder.path("s*")]]) == ["a.txt", "sub"])
		#expect(matches(folder, ["----": ""]) == [])
	}

	@Test func dotEntriesAreNotMatched() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(matches(folder, ["----": folder.path(".*")]) == [])
		#expect(matches(folder, ["----": folder.path(".*"), "invi": true]) == [".hidden"])
	}

	@Test func from() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(matches(folder, ["----": "*.txt", "from": folder.url]) == ["Apple.txt", "a.txt"])
		#expect(matches(folder, ["----": "sub/*", "from": folder.url.path]) == ["sub/c.txt"])
		#expect(texts(send(glob, ["----": "*", "from": folder.url.appendingPathComponent("sub"), "namo": true])) == ["c.txt"])
		// Without `from`, relative to `/`.
		#expect(texts(send(glob, ["----": "Syste?", "namo": true])) == ["System"])
	}

	/// The folder's name was read as a pattern too: `g[1]` matched nothing (or the folder `g1`).
	@Test func fromFolderWithPatternCharacters() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		for name in ["g[1]", "h*{a,b}?", "back\\slash"] {
			try folder.file("\(name)/x.txt")
			#expect(texts(send(glob, ["----": "*.txt", "from": folder.url.appendingPathComponent(name), "namo": true])) == ["x.txt"], "\(name)")
		}
		try folder.file("g1/y.txt")
		#expect(texts(send(glob, ["----": "*", "from": folder.url.appendingPathComponent("g[1]"), "namo": true])) == ["x.txt"])
	}

	@Test func tildeIsTheRealHomeFolder() {
		#expect(texts(send(glob, ["----": "~", "rtyp": typeObject("psxP")])) == [NSHomeDirectory() + "/"])
	}

	@Test func filters() throws {
		let folder = try tree()
		defer { folder.remove() }
		#expect(matches(folder, ["----": folder.path("*"), "Nmxt": "txt"]) == ["Apple.txt", "a.txt"])
		#expect(matches(folder, ["----": folder.path("*"), "nUTI": "public.folder"]) == ["Apple.txt", "B.TXT", "a.txt"])
		#expect(matches(folder, ["----": folder.path("*"), "afte": Date().addingTimeInterval(3600)]) == [])
	}

	@Test func missingParameter() {
		#expect(send(glob, [:]).error == .missingParameter)
	}
}
