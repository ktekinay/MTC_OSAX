import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileAdditions

/// The rules the app's dialogs use to enable and accept items.
@MainActor
struct PanelRulesTests {
	/// A folder with a text file, a JPEG, a subfolder and an app package with a file inside.
	private func withItems(_ body: (URL) throws -> Void) throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("panel-\(UUID().uuidString)")
		let manager = FileManager.default
		try manager.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
		try manager.createDirectory(at: folder.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)
		try Data("x".utf8).write(to: folder.appendingPathComponent("a.txt"))
		try Data("x".utf8).write(to: folder.appendingPathComponent("b.jpg"))
		try Data("x".utf8).write(to: folder.appendingPathComponent("Tool.app/Contents/Info.plist"))
		defer { try? manager.removeItem(at: folder) }
		try body(folder.resolvingSymlinksInPath())
	}

	@Test func isNeeded() {
		#expect(!PanelRules(showsPackages: true, opensPackages: false, volumesOnly: false).isNeeded)
		#expect(PanelRules(showsPackages: false, opensPackages: false, volumesOnly: false).isNeeded)
		#expect(!PanelRules(showsPackages: false, opensPackages: true, volumesOnly: false).isNeeded)
		#expect(PanelRules(showsPackages: true, opensPackages: false, volumesOnly: true).isNeeded)
		#expect(PanelRules(showsPackages: true, opensPackages: false, volumesOnly: false, allowedExtensions: ["txt"]).isNeeded)
	}

	@Test func typesAndExtensions() throws {
		try withItems { folder in
			let text = PanelRules(showsPackages: true, opensPackages: false, volumesOnly: false, allowedTypes: [.plainText])
			#expect(text.shouldEnable(folder.appendingPathComponent("a.txt")))
			#expect(!text.shouldEnable(folder.appendingPathComponent("b.jpg")))
			#expect(text.shouldEnable(folder.appendingPathComponent("sub")))
			let jpeg = PanelRules(showsPackages: true, opensPackages: false, volumesOnly: false, allowedExtensions: ["JPG"])
			#expect(jpeg.shouldEnable(folder.appendingPathComponent("b.jpg")))
			#expect(!jpeg.shouldEnable(folder.appendingPathComponent("a.txt")))
			#expect(PanelRules(showsPackages: true, opensPackages: false, volumesOnly: false).shouldEnable(folder.appendingPathComponent("b.jpg")))
		}
	}

	@Test func packages() throws {
		try withItems { folder in
			let package = folder.appendingPathComponent("Tool.app")
			let inside = package.appendingPathComponent("Contents")
			let hidden = PanelRules(showsPackages: false, opensPackages: false, volumesOnly: false)
			#expect(!hidden.shouldEnable(package))
			#expect(hidden.refusal(of: inside.appendingPathComponent("Info.plist")) != nil)
			#expect(hidden.refusal(of: folder.appendingPathComponent("a.txt")) == nil)
			#expect(hidden.directory(replacing: inside)?.standardizedFileURL == folder.standardizedFileURL)
			#expect(hidden.directory(replacing: folder.appendingPathComponent("sub")) == nil)
			let shown = PanelRules(showsPackages: true, opensPackages: false, volumesOnly: false)
			#expect(shown.shouldEnable(package))
			#expect(shown.refusal(of: package) == nil)
			#expect(shown.directory(replacing: inside) == nil)
			// A package opened like a folder is a folder.
			let opened = PanelRules(showsPackages: false, opensPackages: true, volumesOnly: false, allowedExtensions: ["txt"])
			#expect(opened.shouldEnable(package))
			#expect(PanelRules.enclosingPackage(inside)?.lastPathComponent == "Tool.app")
			#expect(PanelRules.enclosingPackage(folder) == nil)
			// These never finished.
			#expect(PanelRules.enclosingPackage(URL(string: "relative/x")!) == nil)
			#expect(PanelRules.enclosingPackage(URL(string: "file:")!) == nil)
		}
	}

	@Test func volumes() throws {
		try withItems { folder in
			let volumes = PanelRules(showsPackages: true, opensPackages: false, volumesOnly: true)
			#expect(volumes.shouldEnable(URL(fileURLWithPath: "/")))
			#expect(!volumes.shouldEnable(folder))
			#expect(volumes.refusal(of: URL(fileURLWithPath: "/")) == nil)
			#expect(volumes.refusal(of: folder) != nil)
		}
	}
}
