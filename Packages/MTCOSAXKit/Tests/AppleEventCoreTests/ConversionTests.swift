import Foundation
import Testing
@testable import AppleEventCore

struct FourCharCodeTests {
	@Test(arguments: ["SATI", "$in ", "----", "ut16"])
	func roundTrips(_ code: String) {
		#expect(FourCharCode(fourCharString: code).fourCharString == code)
	}

	@Test func matchesSystemConstants() {
		#expect(FourCharCode(fourCharString: "utxt") == typeUnicodeText)
		#expect(FourCharCode(fourCharString: "----") == keyDirectObject)
	}
}

struct DecodingTests {
	@Test func stringFromText() throws {
		#expect(try String(appleEventDescriptor: NSAppleEventDescriptor(string: "abc")) == "abc")
	}

	@Test func stringFromInteger() throws {
		#expect(try String(appleEventDescriptor: NSAppleEventDescriptor(int32: 42)) == "42")
	}

	@Test func stringRejectsList() {
		#expect(throws: OSAXError.coercionFailed) {
			try String(appleEventDescriptor: ["a", "b"].appleEventDescriptor)
		}
	}

	@Test func intFromIntegralReal() throws {
		#expect(try Int(appleEventDescriptor: NSAppleEventDescriptor(double: 2)) == 2)
	}

	@Test func doubleFromInteger() throws {
		#expect(try Double(appleEventDescriptor: NSAppleEventDescriptor(int32: 3)) == 3)
	}

	@Test func boolFromTrueAndFalseTypes() throws {
		let trueDescriptor = NSAppleEventDescriptor(descriptorType: typeTrue, data: nil)!
		let falseDescriptor = NSAppleEventDescriptor(descriptorType: typeFalse, data: nil)!
		#expect(try Bool(appleEventDescriptor: trueDescriptor))
		#expect(try !Bool(appleEventDescriptor: falseDescriptor))
	}

	@Test func dateRoundTrips() throws {
		let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
		#expect(try Date(appleEventDescriptor: date.appleEventDescriptor) == date)
	}

	@Test func arrayFromList() throws {
		let list = [1, 2, 3].appleEventDescriptor
		#expect(try [Int](appleEventDescriptor: list) == [1, 2, 3])
	}

	@Test func arrayWrapsSingleValue() throws {
		#expect(try [String](appleEventDescriptor: NSAppleEventDescriptor(string: "a")) == ["a"])
	}

	@Test func urlFromFileURL() throws {
		let url = URL(fileURLWithPath: "/tmp/x.txt")
		#expect(try URL(appleEventDescriptor: NSAppleEventDescriptor(fileURL: url)).path == "/tmp/x.txt")
	}

	/// A `furl` holding an http URL used to be read from the network by every file parameter.
	@Test func urlRejectsNonFileURLs() throws {
		let web = try #require(NSAppleEventDescriptor(descriptorType: typeFileURL, data: Data("http://example.com/x.plist".utf8)))
		#expect((#expect(throws: OSAXError.self) { try URL(appleEventDescriptor: web) })?.number == -1700)
	}

	@Test func urlFromPOSIXPath() throws {
		#expect(try URL(appleEventDescriptor: NSAppleEventDescriptor(string: "/tmp/x.txt")).path == "/tmp/x.txt")
	}

	@Test func urlFromTildePath() throws {
		let url = try URL(scriptPath: "~/x.txt")
		#expect(url.path == NSHomeDirectory() + "/x.txt")
	}

	@Test func urlFromHFSPathOnStartupVolume() throws {
		let volume = try #require(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
		#expect(try URL(scriptPath: "\(volume):Users:someone:a/b.txt").path == "/Users/someone/a:b.txt")
		#expect(try URL(scriptPath: "\(volume):Users:").path == "/Users")
	}

	@Test func urlFromHFSPathOnOtherVolume() throws {
		#expect(try URL(scriptPath: "Backup Disk:folder:file").path == "/Volumes/Backup Disk/folder/file")
	}

	@Test func urlFromFileURLString() throws {
		#expect(try URL(scriptPath: "file:///tmp/a%20b.txt").path == "/tmp/a b.txt")
		#expect(throws: OSAXError.coercionFailed) { try URL(scriptPath: "file://") }
	}

	/// Edge cases that used to slip through: another Mac's file URL, schemes in capitals, `..` in HFS paths, no
	/// volume name, and the startup volume's name in another case.
	@Test func urlEdgeCases() throws {
		func number(_ path: String) -> Int? {
			(#expect(throws: OSAXError.self) { try URL(scriptPath: path) })?.number
		}
		#expect(number("file://host/etc/passwd") == -1700)
		#expect(try URL(scriptPath: "file://localhost/tmp/x").path == "/tmp/x")
		#expect(try URL(scriptPath: "FILE:///tmp/x").path == "/tmp/x")
		#expect(number("HTTP://example.com/x") == -1700)
		#expect(number("Vol:private:tmp:..:etc:passwd") == -1700)
		#expect(number(":folder:file") == -1700)
		#expect(number("Vol:a:::b") == -1700)
		#expect(try URL(scriptPath: "Backup:a:b::c").path == "/Volumes/Backup/a/c")
		let volume = try #require(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName)
		#expect(try URL(scriptPath: "\(volume.uppercased()):Users").path == "/Users")
	}

	@Test func urlRejectsRelativePath() {
		#expect(throws: OSAXError.coercionFailed) {
			try URL(scriptPath: "file.txt")
		}
	}
}

struct EncodingTests {
	@Test func smallIntIsInteger() {
		#expect(42.appleEventDescriptor.descriptorType == typeSInt32)
	}

	@Test func largeIntIsReal() {
		let descriptor = 5_000_000_000.appleEventDescriptor
		#expect(descriptor.descriptorType == typeIEEE64BitFloatingPoint)
		#expect(descriptor.doubleValue == 5_000_000_000)
	}

	@Test func recordKeepsKeysAndOrder() {
		let record = AppleEventRecord(["mPos": 2, "mLen": 4, "mRes": "2007"]).appleEventDescriptor
		#expect(DescriptorSnapshot(record).summary == #"reco {mPos: long 2, mLen: long 4, mRes: utxt "2007"}"#)
	}

	@Test func missingValue() {
		#expect(DescriptorSnapshot(.missingValue).summary == "type 'msng'")
	}
}

struct CLengthTests {
	/// Lengths of 2 GB or more used to trap in Int32(_:) before reaching libxml2 or tomlc17.
	@Test func tooLargeIsAnError() throws {
		#expect(try Int32(length: 12) == 12)
		#expect(try Int32(length: Int(Int32.max)) == Int32.max)
		#expect((#expect(throws: OSAXError.self) { try Int32(length: Int(Int32.max) + 1) })?.number == -50)
	}
}

struct WriteReplacingTests {
	/// Saves used to write in place, so a failure part way left a cut-short file.
	@Test func replacesInOneStep() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("replace-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let file = folder.appendingPathComponent("a.txt")
		try Data("new file".utf8).writeReplacing(file)
		#expect(try String(contentsOf: file, encoding: .utf8) == "new file")
		// Permissions are kept.
		chmod(file.path, 0o600)
		try Data("second".utf8).writeReplacing(file)
		#expect(try String(contentsOf: file, encoding: .utf8) == "second")
		#expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) == 0o600)
		// A link's target is replaced, not the link.
		let link = folder.appendingPathComponent("link.txt")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
		try Data("through the link".utf8).writeReplacing(link)
		#expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == file.path)
		#expect(try String(contentsOf: file, encoding: .utf8) == "through the link")
		// Nothing is left behind, and a missing folder is an error.
		#expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["a.txt", "link.txt"])
		#expect(throws: (any Error).self) { try Data().writeReplacing(folder.appendingPathComponent("nope/b.txt")) }
	}
}
