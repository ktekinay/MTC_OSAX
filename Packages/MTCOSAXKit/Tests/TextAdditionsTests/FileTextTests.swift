import AppleEventCore
import Foundation
import Testing
@testable import TextAdditions

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

	@Test func writeToMissingFolder() {
		#expect(throws: OSAXError(-43)) {
			try FileText.write(Data(), to: URL(fileURLWithPath: "/nonexistent/folder/file.txt"), append: false)
		}
	}
}
