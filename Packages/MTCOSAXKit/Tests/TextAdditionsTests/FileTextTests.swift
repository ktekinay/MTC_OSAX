import AppleEventCore
import Foundation
import Testing
@testable import TextAdditions

@MainActor
struct FileTextDecodingTests {
	@Test func byteOrderMarks() {
		let utf8 = FileText.decode(Data([0xEF, 0xBB, 0xBF]) + Data("é".utf8), trimIncompleteEnd: false)
		#expect(utf8.text == "é")
		#expect(utf8.byteOrderMark == Data([0xEF, 0xBB, 0xBF]))

		let utf16 = FileText.decode(Data([0xFF, 0xFE]) + "é".data(using: .utf16LittleEndian)!, trimIncompleteEnd: false)
		#expect(utf16.text == "é")
		#expect(utf16.encoding == .utf16LittleEndian)

		let bigEndian = FileText.decode(Data([0xFE, 0xFF]) + "é".data(using: .utf16BigEndian)!, trimIncompleteEnd: false)
		#expect(bigEndian.text == "é")
	}

	@Test func validUTF8() {
		let contents = FileText.decode(Data("Hé 😀".utf8), trimIncompleteEnd: false)
		#expect(contents.text == "Hé 😀")
		#expect(contents.encoding == .utf8)
	}

	@Test func invalidUTF8IsMacRoman() {
		let contents = FileText.decode(Data([0x43, 0x61, 0x66, 0x8E]), trimIncompleteEnd: false)
		#expect(contents.text == "Café")
		#expect(contents.encoding == .macOSRoman)
	}

	@Test func partialReadOfNothing() {
		#expect(FileText.decode(Data(), trimIncompleteEnd: true).text == "")
	}

	@Test func partialReadDropsCutCharacter() {
		#expect(FileText.decode(Data([0x48, 0xC3]), trimIncompleteEnd: true).text == "H")
		#expect(FileText.decode(Data([0x48, 0xF0, 0x9F, 0x98]), trimIncompleteEnd: true).text == "H")
		#expect(FileText.decode(Data([0x48, 0xC3, 0xA9]), trimIncompleteEnd: true).text == "Hé")
	}

	@Test func ianaNames() throws {
		#expect(try FileText.encoding(named: "UTF-8") == .utf8)
		#expect(try FileText.encoding(named: "MACINTOSH") == .macOSRoman)
		#expect(try FileText.encoding(named: "iso-8859-1") == .isoLatin1)
		#expect(try FileText.encoding(named: "windows-1252") == .windowsCP1252)
		#expect(throws: OSAXError(-1)) { try FileText.encoding(named: "nope") }
	}
}

@MainActor
struct FileTextEncodingTests {
	@Test func missingCharacterPerUTF16Unit() throws {
		let data = try FileText.encode("a😀bé", encoding: .isoLatin1, missingCharacter: "?")
		#expect(data == Data([0x61, 0x3F, 0x3F, 0x62, 0xE9]))
	}

	@Test func unrepresentableWithoutMissingCharacter() {
		#expect(throws: OSAXError(-1)) {
			try FileText.encode("😀", encoding: .isoLatin1, missingCharacter: nil)
		}
	}

	@Test func utf16HasByteOrderMark() throws {
		let data = try FileText.encode("é", encoding: .utf16, missingCharacter: nil)
		#expect(data.prefix(2) == Data([0xFF, 0xFE]))
	}
}

@MainActor
struct FileTextReadWriteTests {
	private func temporaryFile(_ contents: Data) throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("filetext-\(UUID().uuidString).txt")
		try contents.write(to: url)
		return url
	}

	@Test func readRanges() throws {
		let url = try temporaryFile(Data("Hello é".utf8))
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(try FileText.read(url, length: 5).text == "Hello")
		#expect(try FileText.read(url, start: 6, length: 2).text == "é")
		#expect(try FileText.read(url, length: 7).text == "Hello ")
	}

	/// Satimage failed with -1 for a start without a length.
	@Test func startWithoutLengthReadsToEnd() throws {
		let url = try temporaryFile(Data("Hello".utf8))
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(try FileText.read(url, start: 1).text == "ello")
		#expect(try FileText.read(url, start: 5).text == "")
		#expect(throws: OSAXError(-39)) { try FileText.read(url, start: 100, length: 1) }
	}

	@Test func missingFile() {
		#expect(throws: OSAXError(-43)) { try FileText.read(URL(fileURLWithPath: "/nonexistent/file.txt")) }
	}

	@Test func appendCreatesAndAppends() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("filetext-\(UUID().uuidString).txt")
		defer { try? FileManager.default.removeItem(at: url) }
		try FileText.write(Data("one".utf8), to: url, append: true)
		try FileText.write(Data("two".utf8), to: url, append: true)
		#expect(try Data(contentsOf: url) == Data("onetwo".utf8))
	}

	/// writetext replaced a file that can't be written, and with append too (the append couldn't open it, and fell
	/// back to replacing it, losing what was there).
	@Test func writeToReadOnlyFile() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("filetext-\(UUID().uuidString).txt")
		try Data("old".utf8).write(to: url)
		chmod(url.path, 0o444)
		defer {
			chmod(url.path, 0o644)
			try? FileManager.default.removeItem(at: url)
		}
		for append in [false, true] {
			#expect(throws: OSAXError(-54)) { try FileText.write(Data("new".utf8), to: url, append: append) }
			#expect(try Data(contentsOf: url) == Data("old".utf8))
		}
	}

	@Test func writeToMissingFolder() throws {
		// Inside a folder of the test's own: a path at the top of the disk is no place for a write, even one meant
		// to be refused.
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("filetext-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		#expect(throws: OSAXError(-43)) {
			try FileText.write(Data(), to: folder.appendingPathComponent("nonexistent/folder/file.txt"), append: false)
		}
	}
}

@MainActor
struct ByteSearchTests {
	/// Generic UTF-32 was always little-endian, while UTF-16 followed the byte-order mark.
	@Test func byteOrderMarks() {
		#expect(FileText.bytes(of: "A", encoding: .utf32, fileStart: Data([0x00, 0x00, 0xFE, 0xFF])) == Data([0, 0, 0, 0x41]))
		#expect(FileText.bytes(of: "A", encoding: .utf32, fileStart: Data([0xFF, 0xFE, 0x00, 0x00])) == Data([0x41, 0, 0, 0]))
		#expect(FileText.bytes(of: "A", encoding: .utf16, fileStart: Data([0xFE, 0xFF, 0x00, 0x41])) == Data([0, 0x41]))
		#expect(FileText.bytes(of: "A", encoding: .utf16, fileStart: Data()) == Data([0x41, 0]))
	}
}

@MainActor
struct ReadTextURLTests {
	private func read(_ source: any AppleEventEncodable) -> AppleEventReply {
		let dispatcher = CommandDispatcher()
		dispatcher.register(TextAdditions.commands(context: TextContext(dollarReferencesDefault: { false }, regexSyntaxDefault: { .ruby })))
		let event = NSAppleEventDescriptor.untargetedEvent(EventKey(code: "SATIRead"))
		event.setParam(source.appleEventDescriptor, forKeyword: keyDirectObject)
		return dispatcher.dispatch(event)
	}

	/// Only lowercase http:// and https:// text was refused, and a `furl` holding a URL was read from the network.
	@Test func urlsAreRefused() throws {
		#expect(read("HTTPS://example.com/x.txt").error?.number == -1708)
		#expect(read("http://example.com/x.txt").error?.number == -1708)
		let web = try #require(NSAppleEventDescriptor(descriptorType: typeFileURL, data: Data("http://example.com/x.txt".utf8)))
		#expect(read(web).error?.number == -1700)
	}
}

@MainActor
struct ReadTextSpecialFileTests {
	/// /dev/zero was read until memory ran out, and a named pipe waited forever.
	@Test func onlyRegularFiles() throws {
		#expect((#expect(throws: OSAXError.self) { try FileText.read(URL(fileURLWithPath: "/dev/zero")) })?.number == -50)
		let fifo = FileManager.default.temporaryDirectory.appendingPathComponent("fifo-\(UUID().uuidString)")
		#expect(mkfifo(fifo.path, 0o600) == 0)
		defer { try? FileManager.default.removeItem(at: fifo) }
		#expect((#expect(throws: OSAXError.self) { try FileText.read(fifo) })?.number == -50)
		#expect((#expect(throws: OSAXError.self) { try FileText.read(URL(fileURLWithPath: "/nonexistent")) })?.number == -43)
		// The file is opened first now (without waiting), then looked at: the same errors as before.
		#expect((#expect(throws: OSAXError.self) { try FileText.read(FileManager.default.temporaryDirectory) })?.number == 1)
		let locked = FileManager.default.temporaryDirectory.appendingPathComponent("unreadable-\(UUID().uuidString)")
		try Data("x".utf8).write(to: locked)
		chmod(locked.path, 0)
		defer { try? FileManager.default.removeItem(at: locked) }
		#expect((#expect(throws: OSAXError.self) { try FileText.read(locked) })?.number == -54)
	}

	/// A part is read without reading the whole file first.
	@Test func partialReads() throws {
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("part-\(UUID().uuidString).txt")
		try Data("0123456789".utf8).write(to: file)
		defer { try? FileManager.default.removeItem(at: file) }
		#expect(try FileText.read(file, start: 2, length: 3).text == "234")
		#expect(try FileText.read(file, start: 8).text == "89")
		#expect(try FileText.read(file, start: 5, length: 100).text == "56789")
		#expect(try FileText.read(file, start: 10).text == "")
		#expect((#expect(throws: OSAXError.self) { try FileText.read(file, start: 11) })?.number == -39)
		// A symbolic link is followed.
		let link = file.deletingLastPathComponent().appendingPathComponent("link-\(UUID().uuidString)")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
		defer { try? FileManager.default.removeItem(at: link) }
		#expect(try FileText.read(link).text == "0123456789")
	}
}
