import AppleEventCore
import Foundation
import Testing
@testable import TextAdditions

/// Commands that never worked in SatimageOSAX (they replied -1708), implemented from their documentation.

private func send(_ code: String, _ parameters: [String: any AppleEventEncodable]) -> AppleEventReply {
	let dispatcher = CommandDispatcher()
	dispatcher.register(TextAdditions.commands(context: TextContext(dollarReferencesDefault: { false })))
	let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: code))
	for (keyword, value) in parameters {
		event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
	}
	return dispatcher.dispatch(event)
}

private func temporaryFile(_ contents: Data) throws -> URL {
	let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixed-\(UUID().uuidString).txt")
	try contents.write(to: url)
	return url
}

struct FileOffsetTests {
	private let fileOffset = "SATIFoff"

	@Test func offsets() throws {
		let url = try temporaryFile(Data("0123456789abcdefé123".utf8))
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(send(fileOffset, ["----": "abc", "in  ": url]).result?.int32Value == 10)
		#expect(send(fileOffset, ["----": "abc", "in  ": url, "incl": true]).result?.int32Value == 13)
		#expect(send(fileOffset, ["----": "é", "in  ": url]).result?.int32Value == 16)
		#expect(send(fileOffset, ["----": "123", "in  ": url, "strt": 5]).result?.int32Value == 18)
		#expect(send(fileOffset, ["----": "123", "in  ": url.path]).result?.int32Value == 1)
	}

	@Test func notFound() throws {
		let url = try temporaryFile(Data("abc".utf8))
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(send(fileOffset, ["----": "z", "in  ": url]).error == OSAXError(-2763))
		#expect(send(fileOffset, ["----": "", "in  ": url]).error == OSAXError(-2763))
	}

	@Test func encodings() throws {
		let utf16 = try temporaryFile(Data([0xFF, 0xFE]) + "UTF16 é".data(using: .utf16LittleEndian)!)
		let bigEndian = try temporaryFile(Data([0xFE, 0xFF]) + "UTF16 é".data(using: .utf16BigEndian)!)
		let latin1 = try temporaryFile(Data([0x43, 0x61, 0x66, 0xE9]))
		defer { [utf16, bigEndian, latin1].forEach { try? FileManager.default.removeItem(at: $0) } }
		#expect(send(fileOffset, ["----": "é", "in  ": utf16, "enco": "UTF-16"]).result?.int32Value == 14)
		#expect(send(fileOffset, ["----": "é", "in  ": bigEndian, "enco": "UTF-16"]).result?.int32Value == 14)
		#expect(send(fileOffset, ["----": "é", "in  ": latin1, "enco": "ISO-8859-1"]).result?.int32Value == 3)
	}

	@Test func missingFile() {
		#expect(send(fileOffset, ["----": "a", "in  ": URL(fileURLWithPath: "/nonexistent.txt")]).error == OSAXError(-43))
	}
}

struct FilterTextTests {
	private let filterText = "SATIGPli"
	private let people = "John is ten\nAnna is twelve\nJohn is at school\nAnna sleeps"

	private func plist(_ reply: AppleEventReply) throws -> [String: Any] {
		let text = try #require(reply.result?.stringValue)
		return try #require(PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any])
	}

	@Test func documentationExampleAsList() throws {
		let reply = send(filterText, ["----": "^([A-z]+) is (.*)", "$in ": people, "key ": "\\1", "by  ": "\\2", "rtyp": NSAppleEventDescriptor(typeCode: typeAEList)])
		let result = try plist(reply)
		#expect(result["John"] as? [String] == ["ten", "at school"])
		#expect(result["Anna"] as? [String] == ["twelve"])
	}

	@Test func asStringJoinsWithSeparator() throws {
		#expect(try plist(send(filterText, ["----": "^([A-z]+) is (.*)", "$in ": people, "key ": "\\1", "by  ": "\\2"]))["John"] as? String == "ten\nat school")
		#expect(try plist(send(filterText, ["----": "^([A-z]+) is (.*)", "$in ": people, "key ": "\\1", "by  ": "\\2", "sepa": ", "]))["John"] as? String == "ten, at school")
	}

	@Test func defaultValueIsWholeMatch() throws {
		#expect(try plist(send(filterText, ["----": "^(Anna) \\w+", "$in ": people, "key ": "\\1"]))["Anna"] as? String == "Anna is\nAnna sleeps")
	}

	@Test func duplicates() throws {
		let parameters: [String: any AppleEventEncodable] = ["----": "^([A-z]+) (is)", "$in ": people, "key ": "\\1", "by  ": "\\2", "rtyp": NSAppleEventDescriptor(typeCode: typeAEList)]
		#expect(try plist(send(filterText, parameters))["John"] as? [String] == ["is", "is"])
		var without = parameters
		without["Dupl"] = false
		#expect(try plist(send(filterText, without))["John"] as? [String] == ["is"])
	}

	@Test func noMatchesIsEmptyDictionary() throws {
		#expect(try plist(send(filterText, ["----": "zzz", "$in ": people, "key ": "\\0"])).isEmpty)
	}

	@Test func xmlText() throws {
		let text = try #require(send(filterText, ["----": "(a)", "$in ": "a", "key ": "k"]).result?.stringValue)
		#expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
		#expect(text.contains("<key>k</key>\n\t<string>a</string>"))
	}

	@Test func intoFile() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("filter-\(UUID().uuidString).plist")
		defer { try? FileManager.default.removeItem(at: url) }
		let reply = send(filterText, ["----": "(a)", "$in ": "a", "key ": "k", "into": url])
		#expect(reply.error == nil)
		#expect(reply.result == nil)
		let written = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String]
		#expect(written == ["k": "a"])
	}

	@Test func intoPropertyListReference() throws {
		var written: [(key: String, value: Any)] = []
		let dispatcher = CommandDispatcher()
		dispatcher.register(TextAdditions.commands(context: TextContext(dollarReferencesDefault: { false }, propertyLists: { _, entries in written = entries })))
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: filterText))
		let reference = NSAppleEventDescriptor(descriptorType: FourCharCode(fourCharString: "CFob"), data: Data(count: 16))!
		for (keyword, value) in ["----": "^([A-z]+) is (.*)", "$in ": people, "key ": "\\1", "by  ": "\\2", "into": reference] as [String: any AppleEventEncodable] {
			event.setParam(value.appleEventDescriptor, forKeyword: FourCharCode(fourCharString: keyword))
		}
		let reply = dispatcher.dispatch(event)
		#expect(reply.error == nil && reply.result == nil)
		#expect(written.map(\.key) == ["John", "Anna"])
		#expect(written.first?.value as? String == "ten\nat school")
		#expect(send(filterText, ["----": "(a)", "$in ": "a", "key ": "k", "into": reference]).error == .eventNotHandled)
	}

	@Test func errors() {
		#expect(send(filterText, ["----": "(", "$in ": "a", "key ": "k"]).error == OSAXError(-117))
		#expect(send(filterText, ["----": "a", "$in ": "a"]).error == .missingParameter)
		#expect(send(filterText, ["----": "(a)", "$in ": "a", "key ": "\\5"]).error == OSAXError(-207))
	}
}
