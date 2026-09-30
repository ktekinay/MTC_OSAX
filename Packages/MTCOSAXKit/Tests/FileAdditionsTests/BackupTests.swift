import AppleEventCore
import Foundation
import Testing
@testable import FileAdditions

@MainActor
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

	/// Items with the hidden flag (as `chflags hidden` sets) are skipped, like names starting with a dot.
	@Test func hiddenFlagIsSkipped() throws {
		let folder = try source()
		defer { folder.remove() }
		try folder.file("src/flagged.txt")
		try folder.file("src/flagged folder/d.txt")
		#expect(chflags(folder.path("src/flagged.txt"), UInt32(UF_HIDDEN)) == 0)
		#expect(chflags(folder.path("src/flagged folder"), UInt32(UF_HIDDEN)) == 0)
		#expect(report(backup(folder), folder) == ["Items to create : a.txt, b.md, pkg.app, skip, sub"])
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

	/// A destination inside the source used to be backed up into itself, deeper each time, until paths were too long.
	@Test func destinationInsideTheSource() throws {
		let folder = try source()
		defer { folder.remove() }
		#expect(report(backup(folder, ["Repo": 2], onto: "src/Backup"), folder)?.count == 1)
		#expect(files(folder, in: "src/Backup") == ["a.txt", "b.md", "pkg.app/Contents/Info.plist", "skip/e.txt", "sub/c.txt"])
		// Again, now that it exists; and reporting only.
		try folder.file("src/new.txt")
		#expect(backup(folder, ["Repo": 1], onto: "src/Backup").result?.stringValue == "OK")
		#expect(files(folder, in: "src/Backup").count == 6)
		#expect(backup(folder, ["Repo": 0], onto: "src/Backup").result?.stringValue == "OK")
		#expect(send("SATISYNC", ["----": folder.url.appendingPathComponent("src"), "onto": folder.url.appendingPathComponent("src/sub/../")])
			.error?.number == -50)
	}

	/// Links used to be followed, so a link to an ancestor copied the tree (and the growing destination) into itself.
	@Test func linksAreCopiedAsLinks() throws {
		let folder = try source()
		defer { folder.remove() }
		try folder.file("target.txt")
		try folder.folder("other")
		let manager = FileManager.default
		try manager.createSymbolicLink(atPath: folder.path("src/filelink"), withDestinationPath: "../target.txt")
		try manager.createSymbolicLink(atPath: folder.path("src/dirlink"), withDestinationPath: "../other")
		try manager.createSymbolicLink(atPath: folder.path("src/up"), withDestinationPath: "..")
		#expect(report(backup(folder, ["Repo": 2]), folder) == ["Items created : a.txt, b.md, dirlink, filelink, pkg.app, skip/e.txt, sub/c.txt, up"])
		for (name, target) in [("filelink", "../target.txt"), ("dirlink", "../other"), ("up", "..")] {
			#expect(try manager.destinationOfSymbolicLink(atPath: folder.path("dst/\(name)")) == target)
		}
		// Up to date: nothing to do. A newer link replaces the old one.
		#expect(backup(folder, ["Repo": 2]).result?.stringValue == "OK")
		try manager.removeItem(atPath: folder.path("src/filelink"))
		Thread.sleep(forTimeInterval: 0.01)
		try manager.createSymbolicLink(atPath: folder.path("src/filelink"), withDestinationPath: "../other")
		#expect(report(backup(folder, ["Repo": 2]), folder) == ["Items updated : filelink"])
		#expect(try manager.destinationOfSymbolicLink(atPath: folder.path("dst/filelink")) == "../other")
	}

	/// Packages were copied following the links in them: a link to a file became a copy of what it pointed at (a
	/// private key, say, from an untrusted package), and a link to a folder an empty folder.
	@Test func linksInPackagesAreCopiedAsLinks() throws {
		let folder = try source()
		defer { folder.remove() }
		try folder.file("secret.txt", "secret")
		try folder.folder("other")
		let manager = FileManager.default
		try manager.createSymbolicLink(atPath: folder.path("src/pkg.app/Contents/key"), withDestinationPath: folder.path("secret.txt"))
		try manager.createSymbolicLink(atPath: folder.path("src/pkg.app/Contents/dir"), withDestinationPath: "../../../other")
		_ = backup(folder, ["Repo": 1])
		#expect(try manager.destinationOfSymbolicLink(atPath: folder.path("dst/pkg.app/Contents/key")) == folder.path("secret.txt"))
		#expect(try manager.destinationOfSymbolicLink(atPath: folder.path("dst/pkg.app/Contents/dir")) == "../../../other")
	}

	/// A folder where the destination had a link (as an earlier backup of a link leaves) was backed up through the
	/// link, into wherever it pointed.
	@Test func linksInTheDestinationAreNotFollowed() throws {
		let folder = try source()
		defer { folder.remove() }
		try folder.folder("elsewhere")
		try FileManager.default.createSymbolicLink(atPath: folder.path("src/sub2"), withDestinationPath: "../elsewhere")
		_ = backup(folder, ["Repo": 1])
		#expect(try FileManager.default.destinationOfSymbolicLink(atPath: folder.path("dst/sub2")) == "../elsewhere")
		// The link in the source becomes a folder; the one in the destination stays a link.
		try FileManager.default.removeItem(atPath: folder.path("src/sub2"))
		try folder.file("src/sub2/planted.txt")
		let text = backup(folder, ["Repo": 2]).result?.stringValue
		#expect(text?.contains(folder.path("dst/sub2") + "  Error : 20 \n") == true)
		#expect(files(folder, in: "elsewhere").isEmpty)
	}

	/// A newer file used to replace a folder of the same name, and everything in it; and an update removed the old
	/// item before copying, so a failed copy left nothing.
	@Test func nothingIsDeleted() throws {
		let folder = try source()
		defer { folder.remove() }
		_ = backup(folder, ["Repo": 1])
		let later = Date().addingTimeInterval(60)
		// A file where the destination has a folder, and a package where it has a file.
		try FileManager.default.removeItem(atPath: folder.path("src/skip"))
		try folder.file("src/skip", modified: later)
		try FileManager.default.removeItem(atPath: folder.path("dst/pkg.app"))
		try folder.file("dst/pkg.app")
		try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: folder.path("dst/pkg.app"))
		let text = backup(folder, ["Repo": 2]).result?.stringValue
		#expect(text?.contains(folder.path("dst/skip") + "  Error : 21 \n") == true)
		#expect(text?.contains(folder.path("dst/pkg.app") + "  Error : 20 \n") == true)
		#expect(files(folder).contains("skip/e.txt"))
		// A copy that fails leaves the old file.
		try folder.file("src/a.txt", "new", modified: later)
		try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path("src/a.txt"))
		defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: folder.path("src/a.txt")) }
		#expect(backup(folder, ["Repo": 2]).result?.stringValue?.contains(folder.path("dst/a.txt") + "  Error : 13 \n") == true)
		#expect(try String(contentsOfFile: folder.path("dst/a.txt"), encoding: .utf8) == "x")
		#expect(try FileManager.default.contentsOfDirectory(atPath: folder.path("dst")).allSatisfy { !$0.contains("mtc-backup") })
		// An update of a package replaces it whole.
		try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: folder.path("src/a.txt"))
		try FileManager.default.removeItem(atPath: folder.path("dst/pkg.app"))
		_ = backup(folder, ["Repo": 1])
		try folder.file("src/pkg.app/Contents/New.txt")
		try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: folder.path("src/pkg.app"))
		#expect(report(backup(folder, ["Repo": 2]), folder)?.first == "Items updated : pkg.app")
		#expect(files(folder).contains("pkg.app/Contents/New.txt"))
	}

	/// Folders used to be made with 0o777 less the umask, and other levels acted as 2.
	@Test func folderPermissionsAndLevels() throws {
		let folder = try source()
		defer { folder.remove() }
		chmod(folder.path("src/sub"), 0o750)
		_ = backup(folder, ["Repo": 1])
		#expect((try FileManager.default.attributesOfItem(atPath: folder.path("dst/sub"))[.posixPermissions] as? Int) == 0o750)
		for level in [3, -1] {
			#expect(backup(folder, ["Repo": level]).error?.number == -50)
		}
	}

	@Test func parameterErrors() throws {
		let folder = try source()
		defer { folder.remove() }
		#expect(send("SATISYNC", ["----": folder.url.appendingPathComponent("nope"), "onto": folder.url]).error == .parameterError)
		#expect(send("SATISYNC", ["----": folder.url.appendingPathComponent("src/a.txt"), "onto": folder.url]).error == .parameterError)
		#expect(send("SATISYNC", ["----": folder.url]).error == .missingParameter)
	}
}
