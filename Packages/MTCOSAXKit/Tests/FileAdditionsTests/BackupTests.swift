import AppleEventCore
import Foundation
import Testing
@testable import FileAdditions

struct BackupTests {
	private func source() throws -> TemporaryFolder {
		let folder = try TemporaryFolder()
		try folder.file("src/a.txt")
		try folder.file("src/b.md")
		try folder.file("src/.hidden")
		try folder.file("src/sub/c.txt")
		try folder.file("src/skip/e.txt")
		try folder.file("src/pkg.app/Contents/Info.plist")
		try folder.folder("dst")
		return folder
	}

	private func backup(_ folder: TemporaryFolder, _ parameters: [String: any AppleEventEncodable] = [:], onto: String = "dst") -> AppleEventReply {
		var parameters = parameters
		parameters["----"] = folder.url.appendingPathComponent("src")
		parameters["onto"] = folder.url.appendingPathComponent(onto)
		return send("SATISYNC", parameters)
	}

	/// The report's sections in order, each with its paths relative to the destination, sorted (the order of
	/// items is the file system's).
	private func report(_ reply: AppleEventReply, _ folder: TemporaryFolder) -> [String]? {
		guard let text = reply.result?.stringValue, text.hasSuffix("\n") else {
			return nil
		}
		var sections: [(title: String, items: [String])] = []
		for line in text.replacingOccurrences(of: " : \r", with: " :\n").split(separator: "\n") {
			if line.hasPrefix("\t") {
				sections[sections.count - 1].items.append(line.dropFirst().replacingOccurrences(of: folder.path("dst") + "/", with: ""))
			} else {
				sections.append((String(line), []))
			}
		}
		return sections.map { $0.title + " " + $0.items.sorted().joined(separator: ", ") }
	}

	private func files(_ folder: TemporaryFolder, in relative: String = "dst") -> [String] {
		let root = folder.url.appendingPathComponent(relative)
		let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
		var result: [String] = []
		while let url = enumerator?.nextObject() as? URL {
			if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true {
				result.append(String(url.path.dropFirst(root.path.count + 1)))
			}
		}
		return result.sorted()
	}

	@Test func reportOnly() throws {
		let folder = try source()
		defer { folder.remove() }
		#expect(report(backup(folder), folder) == ["Items to create : a.txt, b.md, pkg.app, skip, sub"])
		#expect(files(folder).isEmpty)
	}

	@Test func synchronize() throws {
		let folder = try source()
		defer { folder.remove() }
		#expect(backup(folder, ["Repo": 1]).result?.stringValue == "OK")
		#expect(files(folder) == ["a.txt", "b.md", "pkg.app/Contents/Info.plist", "skip/e.txt", "sub/c.txt"])
		#expect(backup(folder, ["Repo": 2]).result?.stringValue == "OK")
	}

	@Test func synchronizeAndReport() throws {
		let folder = try source()
		defer { folder.remove() }
		#expect(report(backup(folder, ["Repo": 2]), folder) == ["Items created : a.txt, b.md, pkg.app, skip/e.txt, sub/c.txt"])
	}

	@Test func updatesNewerFilesAndKeepsExtras() throws {
		let folder = try source()
		defer { folder.remove() }
		_ = backup(folder, ["Repo": 1])
		try folder.file("dst/extra.txt")
		try folder.file("src/a.txt", "new", modified: Date().addingTimeInterval(60))
		try folder.file("src/new.txt")
		#expect(report(backup(folder), folder) == ["Items to update : a.txt", "Items to create : new.txt"])
		#expect(report(backup(folder, ["Repo": 2]), folder) == ["Items updated : a.txt", "Items created : new.txt"])
		#expect(try String(contentsOfFile: folder.path("dst/a.txt"), encoding: .utf8) == "new")
		#expect(files(folder).contains("extra.txt"))
	}

	@Test func olderSourceIsNotCopied() throws {
		let folder = try source()
		defer { folder.remove() }
		_ = backup(folder, ["Repo": 1])
		try folder.file("dst/a.txt", "newer", modified: Date().addingTimeInterval(60))
		#expect(backup(folder, ["Repo": 2]).result?.stringValue == "OK")
		#expect(try String(contentsOfFile: folder.path("dst/a.txt"), encoding: .utf8) == "newer")
	}

	@Test func filters() throws {
		let folder = try source()
		defer { folder.remove() }
		_ = backup(folder, ["Repo": 1, "fnam": ["skip", "pkg.app"], "fext": "md", "RECU": true])
		#expect(files(folder) == ["a.txt", "pkg.app/Contents/Info.plist", "sub/c.txt"])
		let only = try source()
		defer { only.remove() }
		_ = backup(only, ["Repo": 1, "oext": ["txt"], "RECU": false])
		#expect(files(only) == ["a.txt"])
		let after = try source()
		defer { after.remove() }
		#expect(backup(after, ["Repo": 2, "afte": Date().addingTimeInterval(3600)]).result?.stringValue == "OK")
	}

	@Test func errorsAreReported() throws {
		let folder = try source()
		defer { folder.remove() }
		try folder.file("dst/sub")
		let text = backup(folder, ["Repo": 2]).result?.stringValue
		#expect(text?.contains("Errors : \r" + folder.path("dst/sub/c.txt") + "  Error : 20 \n") == true)
	}

	@Test func missingDestinationIsCreated() throws {
		let folder = try source()
		defer { folder.remove() }
		_ = backup(folder, ["Repo": 1], onto: "new/deeper")
		#expect(files(folder, in: "new/deeper").count == 5)
	}

	@Test func parameterErrors() throws {
		let folder = try source()
		defer { folder.remove() }
		#expect(send("SATISYNC", ["----": folder.url.appendingPathComponent("nope"), "onto": folder.url]).error == .parameterError)
		#expect(send("SATISYNC", ["----": folder.url.appendingPathComponent("src/a.txt"), "onto": folder.url]).error == .parameterError)
		#expect(send("SATISYNC", ["----": folder.url]).error == .missingParameter)
	}
}
