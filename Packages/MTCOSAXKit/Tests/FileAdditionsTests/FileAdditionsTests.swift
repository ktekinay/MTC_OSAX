import AppleEventCore
import Foundation
import Testing
@testable import FileAdditions

// MARK: Helpers

@MainActor
func send(_ code: String, _ parameters: [String: any AppleEventEncodable], commands: [CommandDefinition] = FileAdditions.commands()) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(commands)
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return dispatcher.dispatch(event)
}

/// A new temporary folder (a real path, as results report it), removed by `remove()`.
struct TemporaryFolder {
	let url: URL

	init() throws {
		let base = FileManager.default.temporaryDirectory.appendingPathComponent("file-additions-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		url = URL(fileURLWithPath: FileAdditions.realPath(base.path)!, isDirectory: true)
	}

	func path(_ relative: String) -> String {
		url.appendingPathComponent(relative).path
	}

	@discardableResult
	func file(_ relative: String, _ contents: String = "x", modified: Date? = nil) throws -> URL {
		let file = url.appendingPathComponent(relative)
		try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data(contents.utf8).write(to: file)
		if let modified {
			try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
		}
		return file
	}

	@discardableResult
	func folder(_ relative: String) throws -> URL {
		let folder = url.appendingPathComponent(relative, isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder
	}

	func remove() {
		try? FileManager.default.removeItem(at: url)
	}
}

/// The paths in a list of file references, aliases or file URLs, relative to `folder`.
func relativePaths(_ reply: AppleEventReply, in folder: TemporaryFolder) -> [String]? {
	guard let list = reply.result, list.descriptorType == typeAEList else {
		return nil
	}
	return (0 ..< list.numberOfItems).map { index in
		let item = list.atIndex(index + 1)!
		let path = item.fileReferencePath ?? item.coerce(toDescriptorType: typeFileURL)?.fileURLValue?.path ?? item.stringValue ?? "?"
		return path.hasPrefix(folder.url.path + "/") ? String(path.dropFirst(folder.url.path.count + 1)) : path
	}
}

func texts(_ reply: AppleEventReply) -> [String]? {
	guard let list = reply.result, list.descriptorType == typeAEList else {
		return nil
	}
	return (0 ..< list.numberOfItems).map { list.atIndex($0 + 1)!.stringValue ?? "?" }
}

/// `unix path` (`psxP`) or `path` (`FTPc`) as a script sends them in an `as` parameter: a property specifier.
func typeObject(_ property: String) -> NSAppleEventDescriptor {
	let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier)!
	specifier.setDescriptor(NSAppleEventDescriptor(enumCode: FourCharCode(fourCharString: "prop")), forKeyword: AEKeyword(keyAEKeyForm))
	specifier.setDescriptor(NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: "prop")), forKeyword: AEKeyword(keyAEDesiredClass))
	specifier.setDescriptor(NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: property)), forKeyword: AEKeyword(keyAEKeyData))
	specifier.setDescriptor(.null(), forKeyword: AEKeyword(keyAEContainer))
	return specifier
}

func type(_ code: String) -> NSAppleEventDescriptor {
	NSAppleEventDescriptor(typeCode: FourCharCode(fourCharString: code))
}

// MARK: Result forms

@MainActor
struct ResultFormTests {
	private func form(_ value: NSAppleEventDescriptor?) -> ResultForm {
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: "SATIlsfl"))
		if let value {
			event.setParam(value, forKeyword: FourCharCode(fourCharString: "rtyp"))
		}
		return ResultForm(AppleEventRequest(event), default: .fileReference)
	}

	@Test func types() {
		#expect(form(nil) == .fileReference)
		#expect(form(type("alis")) == .alias)
		#expect(form(type("file")) == .fileURL)
		#expect(form(type("furl")) == .fileURL)
		#expect(form(type("utxt")) == .urlText)
		#expect(form(type("TEXT")) == .urlText)
		#expect(form(type("ctxt")) == .urlText)
		#expect(form(type("long")) == .fileURL)
		#expect(form(typeObject("psxP")) == .posixPath)
		#expect(form(typeObject("FTPc")) == .escapedPath)
	}

	@Test func descriptors() throws {
		let folder = try TemporaryFolder()
		defer { folder.remove() }
		let file = try folder.file("a b.txt")
		#expect(try ResultForm.posixPath.descriptor(for: folder.url, isDirectory: true).stringValue == folder.url.path + "/")
		#expect(try ResultForm.escapedPath.descriptor(for: file, isDirectory: false).stringValue?.hasSuffix("/a%20b.txt") == true)
		#expect(try ResultForm.urlText.descriptor(for: file, isDirectory: false).stringValue == "file://" + folder.url.path + "/a%20b.txt")
		#expect(try ResultForm.fileReference.descriptor(for: file, isDirectory: false).descriptorType == typeFSRef)
		#expect(try ResultForm.alias.descriptor(for: file, isDirectory: false).descriptorType == typeAlias)
		#expect(throws: OSAXError(-43)) { try ResultForm.alias.descriptor(for: folder.url.appendingPathComponent("nope"), isDirectory: false) }
	}
}
