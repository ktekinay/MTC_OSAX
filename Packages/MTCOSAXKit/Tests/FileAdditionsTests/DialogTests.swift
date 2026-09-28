import AppleEventCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileAdditions

/// Stands in for the app's dialogs: records the options it was given and answers with fixed results.
final class FakeDialogs: FileDialogs, @unchecked Sendable {
	var chosen: [URL] = []
	var newItem = URL(fileURLWithPath: "/private/tmp/new.txt")
	var canceled = false
	var saveAnswer = 1
	private(set) var chooseOptions: ChooseOptions?
	private(set) var newItemOptions: NewItemOptions?
	private(set) var askSaveArguments: (String?, Int)?

	func choose(_ options: ChooseOptions) throws -> [URL] {
		chooseOptions = options
		if canceled {
			throw OSAXError(-128)
		}
		return chosen
	}

	func chooseNewItem(_ options: NewItemOptions) throws -> URL {
		newItemOptions = options
		if canceled {
			throw OSAXError(-128)
		}
		return newItem
	}

	func askSave(fileName: String?, action: Int) -> Int {
		askSaveArguments = (fileName, action)
		return saveAnswer
	}
}

struct DialogTests {
	private let dialogs = FakeDialogs()
	private let defaults = UserDefaults(suiteName: "mtc-dialog-tests-\(UUID().uuidString)")!

	private func send(_ code: String, _ parameters: [String: any AppleEventEncodable] = [:]) -> AppleEventReply {
		FileAdditionsTests.send(code, parameters, commands: FileAdditions.dialogCommands(dialogs, defaults: defaults))
	}

	@Test func chooseFileOptionsAndResult() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		dialogs.chosen = [try folder.file("a.txt"), try folder.file("b.txt")]
		let reply = send("SATIstdf", ["prmp": "Pick", "Nmxt": ["txt"], "ftyp": ["public.png"], "from": folder.url, "mlfl": false, "vipa": false, "oppa": true, "lfiv": true])
		let options = try #require(dialogs.chooseOptions)
		#expect(options.kind == .files)
		#expect(options.prompt == "Pick")
		#expect(options.allowedTypes == [.png])
		#expect(options.allowedExtensions == ["txt"])
		#expect(options.startingAt?.path == folder.url.path)
		#expect(options.multipleSelection == false)
		#expect(options.showsPackages == false)
		#expect(options.opensPackages == true)
		#expect(options.showsInvisibles == true)
		#expect(reply.result?.descriptorType == typeAEList)
		#expect(reply.result?.atIndex(1)?.descriptorType == typeAlias)
		#expect(relativePaths(reply, in: folder) == ["a.txt", "b.txt"])
	}

	@Test func defaultOptions() throws {
		dialogs.chosen = []
		_ = send("SATIstdf")
		let options = try #require(dialogs.chooseOptions)
		#expect(options.allowedTypes == nil)
		#expect(options.allowedExtensions == nil)
		#expect(options.multipleSelection)
		#expect(options.showsPackages)
		#expect(!options.opensPackages)
		#expect(!options.showsInvisibles)
		#expect(options.startingAt == nil)
	}

	@Test func kinds() {
		_ = send("SATIstfl")
		#expect(dialogs.chooseOptions?.kind == .folders)
		_ = send("SATIstob")
		#expect(dialogs.chooseOptions?.kind == .filesAndFolders)
		_ = send("SATIstvo")
		#expect(dialogs.chooseOptions?.kind == .volumes)
		#expect(dialogs.chooseOptions?.multipleSelection == false)
	}

	@Test func extensionsKeepTheirDot() throws {
		_ = send("SATIstdf", ["Nmxt": [".txt", "md"]])
		#expect(dialogs.chooseOptions?.allowedExtensions == ["txt", "md"])
		#expect(dialogs.chooseOptions?.allowedTypes == nil)
	}

	@Test func fileTypeCodes() throws {
		_ = send("SATIstdf", ["ftyp": ["TEXT"]])
		#expect(dialogs.chooseOptions?.allowedTypes == [UTType("com.apple.traditional-mac-plain-text")!])
	}

	@Test func keyRemembersTheFolder() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		dialogs.chosen = [try folder.file("sub/a.txt")]
		_ = send("SATIstdf", ["key ": 7])
		#expect(dialogs.chooseOptions?.startingAt == nil)
		_ = send("SATIstdf", ["key ": 7])
		#expect(dialogs.chooseOptions?.startingAt?.path == folder.path("sub"))
		_ = send("SATIstdf", ["key ": 7, "from": folder.url])
		#expect(dialogs.chooseOptions?.startingAt?.path == folder.url.path)
		_ = send("SATIstdf", ["key ": 8])
		#expect(dialogs.chooseOptions?.startingAt == nil)
	}

	@Test func cancel() {
		dialogs.canceled = true
		#expect(send("SATIstdf").error == OSAXError(-128))
		#expect(send("SATInwfl").error == OSAXError(-128))
	}

	@Test func newFileName() throws {
		dialogs.newItem = URL(fileURLWithPath: "/private/tmp/some file.txt")
		let reply = send("SATInwfl", ["prmt": "Save as", "dfnm": "x.txt", "wmnu": ["Text", "HTML"], "PInd": 2, "vipa": false])
		let options = try #require(dialogs.newItemOptions)
		#expect(options == {
			var expected = NewItemOptions(folder: false)
			expected.prompt = "Save as"
			expected.defaultName = "x.txt"
			expected.menuItems = ["Text", "HTML"]
			expected.menuIndex = 2
			expected.showsPackages = false
			return expected
		}())
		#expect(reply.result?.descriptorType == typeFileURL)
		#expect(reply.result?.fileURLValue?.path == "/private/tmp/some file.txt")
	}

	@Test func newFolder() throws {
		dialogs.newItem = URL(fileURLWithPath: "/private/tmp/New Folder")
		let reply = send("SATIstnf", ["prmt": "Folder", "key ": 3])
		#expect(dialogs.newItemOptions?.folder == true)
		#expect(dialogs.newItemOptions?.prompt == "Folder")
		#expect(reply.result?.fileURLValue?.absoluteString == "file:///private/tmp/New%20Folder/")
		_ = send("SATIstnf", ["key ": 3])
		#expect(dialogs.newItemOptions?.startingAt?.path == "/private/tmp")
	}

	@Test func askSave() {
		dialogs.saveAnswer = 3
		#expect(send("SATInask", ["fnam": "Doc", "acti": 2]).result?.int32Value == 3)
		#expect(dialogs.askSaveArguments?.0 == "Doc")
		#expect(dialogs.askSaveArguments?.1 == 2)
		#expect(send("SATInask").result?.int32Value == 3)
		#expect(dialogs.askSaveArguments?.1 == 0)
		#expect(send("SATInask", ["acti": 5]).error == .parameterError)
	}

	@Test func withoutDialogsNotHandled() {
		let reply = FileAdditionsTests.send("SATIstdf", [:], commands: FileAdditions.commands())
		#expect(reply.error == .eventNotHandled)
	}
}
